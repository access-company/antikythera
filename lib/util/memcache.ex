# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Memcache do
  @moduledoc """
  Easy-to-use in-memory cache for each executor pool.

  #{inspect(__MODULE__)} behaves as a key-value storage.
  Cached key-value pairs are internally stored in ETS.
  It accepts arbitrary (but not too large) terms as both keys and values.

  ## Usage

      iex> Antikythera.Memcache.write("foo", "bar", epool_id, 3_600)
      :ok
      iex> Antikythera.Memcache.read("foo", epool_id)
      {:ok, "bar"}

  ## Limits

  The number of records and the size of keys and values are limited.

  - The maximum number of records for each executor pool
    is #{AntikytheraCore.ExecutorPool.MemcacheWriter.max_records()}.
      - If exceeds the limit, a record nearest to expiration is evicted so that a new record can be inserted.
  - The maximum size of keys and values is defined in `Antikythera.Memcache.Key` and `Antikythera.Memcache.Value`.
      - To know how the size of keys and values is calculated, see `Antikythera.TermUtil`.
      - If exceeds the limit, `write/5` returns an error `:too_large_key` or `:too_large_value`.

  ## Lifetime of records

  There are 2 cases where records in #{inspect(__MODULE__)} are evicted:

  1. Records are expired (see [Mechanism of Expiration](#module-mechanism-of-expiration) below for more details)
  2. Reach the maximum number of records for each executor pool (as mentioned in [Limits](#module-limits))

  Please note that records in #{inspect(__MODULE__)} could be evicted anytime.

  ## Mechanism of Expiration

  The lifetime of records must be set as `lifetime_in_sec` in `write/5`.
  This lifetime does not guarantee that records remain in the entire specified lifetime.

  To avoid the [thundering herd](https://en.wikipedia.org/wiki/Thundering_herd_problem), whether records are expired is decided probabilistically.
  The probability of expiration is shown in the following.

  ![Mechanism of Expiration](assets/MemcacheExpiration.png)

  If the thundering herd becomes a big problem, adjust `prob_lifetime_ratio` in `write/5`.
  """

  @default_ratio 0.9

  alias Croma.Result, as: R
  alias AntikytheraCore.ExecutorPool.MemcacheWriter
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Ets.Memcache
  alias Antikythera.Memcache.{Key, Value, NormalizedFloat}

  @doc """
  Read the value associated with the `key` from #{inspect(__MODULE__)}.

  Please note that records in #{inspect(__MODULE__)} could be evicted anytime so the error handling must be needed.
  """
  defun read(key :: Key.t(), epool_id :: v[EPoolId.t()]) :: R.t(Value.t(), :not_found) do
    Memcache.read(key, epool_id)
    |> R.bind(fn {_, expire_at, prob_expire_at, value} ->
      if expired?(expire_at, prob_expire_at) do
        {:error, :not_found}
      else
        {:ok, value}
      end
    end)
  end

  @doc """
  Try to read a value associated with the `key` from #{inspect(__MODULE__)} and if that fails,
  write a value returned by `fun` to #{inspect(__MODULE__)}.

  `fun` is evaluated only if a value is not found,
  and the new value returned by `fun` is stored in #{inspect(__MODULE__)}.
  If a value is found in #{inspect(__MODULE__)} or writing the new value to #{inspect(__MODULE__)} succeeds,
  the value is returned as `{:ok, value}`, but if writing the new value fails, an error is returned in the same manner as `write/5`.

  Parameters `lifetime_in_sec` and `prob_lifetime_ratio` are used to call `write/5` and the details are described above.
  """
  defun read_or_else_write(
          key :: Key.t(),
          epool_id :: v[EPoolId.t()],
          lifetime_in_sec :: v[non_neg_integer],
          prob_lifetime_ratio :: v[NormalizedFloat.t()] \\ @default_ratio,
          fun :: (() -> Value.t())
        ) :: R.t(Value.t(), :too_large_key | :too_large_value) do
    case read(key, epool_id) do
      {:ok, value} ->
        {:ok, value}

      {:error, _not_found} ->
        value = fun.()

        case write(key, value, epool_id, lifetime_in_sec, prob_lifetime_ratio) do
          :ok -> {:ok, value}
          err -> err
        end
    end
  end

  defp expired?(expire_at, prob_expire_at) do
    case System.monotonic_time(:millisecond) do
      now when now < prob_expire_at ->
        false

      now when expire_at < now ->
        true

      now ->
        rnd = :rand.uniform()
        t0 = expire_at - prob_expire_at
        t1 = now - prob_expire_at
        rnd < t1 / t0
    end
  end

  @doc """
  Write a key-value pair to #{inspect(__MODULE__)}.

  See above descriptions for more details.
  """
  defun write(
          key :: Key.t(),
          value :: Value.t(),
          epool_id :: v[EPoolId.t()],
          lifetime_in_sec :: v[non_neg_integer],
          prob_lifetime_ratio :: v[NormalizedFloat.t()] \\ @default_ratio
        ) :: :ok | {:error, :too_large_key | :too_large_value} do
    cond do
      not Key.valid?(key) -> {:error, :too_large_key}
      not Value.valid?(value) -> {:error, :too_large_value}
      true -> MemcacheWriter.write(key, value, epool_id, lifetime_in_sec, prob_lifetime_ratio)
    end
  end

  defmodule Key do
    @max_size 128

    @moduledoc """
    A type module of keys for `Antikythera.Memcache`.

    The maximum size of keys is #{@max_size} bytes.
    To know how the size is calculated, see `Antikythera.TermUtil`.
    """

    @type t :: any
    defun valid?(key :: term) :: boolean do
      Antikythera.TermUtil.size_smaller_or_equal?(key, @max_size)
    end

    defun max_size() :: non_neg_integer, do: @max_size
  end

  defmodule Value do
    @max_size 65_536

    @moduledoc """
    A type module of values for `Antikythera.Memcache`.

    The maximum size of values is #{@max_size} bytes.
    To know how the size is calculated, see `Antikythera.TermUtil`.
    """

    @type t :: any
    defun valid?(value :: term) :: boolean do
      Antikythera.TermUtil.size_smaller_or_equal?(value, @max_size)
    end

    defun max_size() :: non_neg_integer, do: @max_size
  end

  defmodule NormalizedFloat do
    use Croma.SubtypeOfFloat, min: 0.0, max: 1.0
  end
end
