# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Memcache do
  @moduledoc """
  In-memory cache for each executor pool.

      iex> Antikythera.Memcache.write("foo", "bar", epool_id)
      :ok
      iex> Antikythera.Memcache.read("foo", epool_id)
      {:ok, "bar"}
  """

  @default_ratio 0.9

  alias Croma.Result, as: R
  alias AntikytheraCore.ExecutorPool.MemcacheWriter
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Ets.Memcache
  alias Antikythera.Memcache.NormalizedFloat

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

  defun write(key                 :: term,
              value               :: term,
              epool_id            :: v[EPoolId.t],
              lifetime_in_sec     :: v[non_neg_integer],
              prob_lifetime_ratio :: v[NormalizedFloat.t] \\ @default_ratio) :: :ok do
    MemcacheWriter.write(key, value, epool_id, lifetime_in_sec, prob_lifetime_ratio)
  end

  defmodule NormalizedFloat do
    use Croma.SubtypeOfFloat, min: 0.0, max: 1.0
  end
end
