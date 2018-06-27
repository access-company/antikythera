# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Memcache do
  @moduledoc """
  In-memory cache for each executor pool.

  Antikythera provides in-memory cache controlled by AntikytheraCore for each executor pool.
  Objects are stored in ETS internally.

  ## Usage

  Memcache behaves as a key-value storage.

      iex> Antikythera.Memcache.write("foo", "bar", epool_id, 3_600)
      :ok
      iex> Antikythera.Memcache.read("foo", epool_id)
      {:ok, "bar"}

  ## Limitation

  The number of records and the size of keys and values is limited.

  - The maximum number of records for each executor pool is #{AntikytheraCore.ExecutorPool.MemcacheWriter.max_records()}.
    - If exceeds the limit, records whose expiration time is nearest are evicted.
  - The maximum size of keys and values is defined in `Antikythera.Memcache.Key` and `Antikythera.Memcache.Value`.
    - To know how the size of keys and values is calculated, see `Antikythera.TermUtil`.
    - If exceeds the limit, `write/5` returns an error `:too_large_key` or `:too_large_value`.

  ## Lifetime of records

  There are 2 cases where records in memcache are evicted:

  1. Records are expired (see [Mechanism of Expiration](#module-mechanism-of-expiration) below for more details)
  2. Reach the maximum number of records for each executor pool

  If it is the case of (2), records whose expiration time is nearest are evicted to keep the maximum number of records.

  Please note that records in memcache could be evicted anytime.

  ## Mechanism of Expiration

  The lifetime of records must be set as `lifetime_in_sec` in `write/5`.
  This lifetime does not guarantee that records remain in the entire specified lifetime.

  To avoid the thundering herd, whether records are expired is decided probabilistically.
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
  Read the value associated with the `key` from memcache.

  Please note that records in memcache could be evicted anytime so the error handling must be needed.
  """
  defun read(key :: term, epool_id :: v[EPoolId.t]) :: R.t(term, :not_found) do
    Memcache.read(key, epool_id)
    |> R.bind(fn {_, expire_at, prob_expire_at, value} ->
      if expired?(expire_at, prob_expire_at) do
        {:error, :not_found}
      else
        {:ok, value}
      end
    end)
  end

  defp expired?(expire_at, prob_expire_at) do
    case System.monotonic_time(:milliseconds) do
      now when now < prob_expire_at -> false
      now when expire_at < now      -> true
      now ->
        rnd = :rand.uniform()
        t0 = expire_at - prob_expire_at
        t1 = now       - prob_expire_at
        rnd < (t1 / t0)
    end
  end

  @doc """
  Write a key-value pair to memcache.

  See above descriptions for more details.
  """
  defun write(key                 :: Key.t,
              value               :: Value.t,
              epool_id            :: v[EPoolId.t],
              lifetime_in_sec     :: v[non_neg_integer],
              prob_lifetime_ratio :: v[NormalizedFloat.t] \\ @default_ratio) :: :ok | {:error, :too_large_key} | {:error, :too_large_value} do
    cond do
      not Key.valid?(key)     -> {:error, :too_large_key}
      not Value.valid?(value) -> {:error, :too_large_value}
      true                    -> MemcacheWriter.write(key, value, epool_id, lifetime_in_sec, prob_lifetime_ratio)
    end
  end

  defmodule Key do
    @max_size 128

    @moduledoc """
    A type module of keys for memcache.

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
    @max_size 65536

    @moduledoc """
    A type module of values for memcache.

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
