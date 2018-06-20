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

  @default_lifetime 1800
  @default_ratio    0.9

  alias Croma.Result, as: R
  alias Antikythera.Time
  alias AntikytheraCore.ExecutorPool.MemcacheManager
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Ets.Memcache
  alias Antikythera.Memcache.NormalizedFloat

  defun read(key :: term, epool_id :: v[EPoolId.t]) :: R.t(term, :not_found) do
    case Memcache.read(key, epool_id) do
      {:ok, {_, expire_at, prob_expire_at, value}} ->
        if is_expired(expire_at, prob_expire_at) do
          {:error, :not_found}
        else
          {:ok, value}
        end
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defun write(key                 :: term,
              value               :: term,
              epool_id            :: v[EPoolId.t],
              lifetime_in_sec     :: v[non_neg_integer] \\ @default_lifetime,
              prob_lifetime_ratio :: v[NormalizedFloat.t] \\ @default_ratio) :: :ok | {:error, :too_large_object} do
    MemcacheManager.write(key, value, epool_id, lifetime_in_sec, prob_lifetime_ratio)
  end

  defp is_expired(expire_at, prob_expire_at) do
    case Time.now() do
      now when now < prob_expire_at -> false
      now when expire_at < now      -> true
      now ->
        rnd = :rand.uniform()
        t0 = Time.diff_milliseconds(expire_at, prob_expire_at)
        t1 = Time.diff_milliseconds(now      , prob_expire_at)
        rnd < (t1 / t0)
    end
  end

  defmodule NormalizedFloat do
    use Croma.SubtypeOfFloat, min: 0.0, max: 1.0
  end
end
