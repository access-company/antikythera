# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.MemcacheManager do
  @moduledoc """
  A `GenServer` to manage memcache for each executor pool.
  """

  @timeout         300_000
  @max_records_num 10
  @max_record_size 65536

  use GenServer
  alias AntikytheraCore.Ets.Memcache
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  def start_link(name, epool_id) do
    GenServer.start_link(__MODULE__, epool_id, [name: name])
  end

  @impl true
  def init(epool_id) do
    {:ok, %{epool_id: epool_id, records: %{}, expire_at_set: :gb_sets.new()}, @timeout}
  end

  @impl true
  def handle_call({:write, key, value, lifetime, ratio}, _from, state) do
    evicted_state = evict_expired_records(state, System.monotonic_time(:milliseconds))
    if :erts_debug.flat_size(value) > @max_record_size do
      {:reply, {:error, :too_large_object}, evicted_state, @timeout}
    else
      new_state =
        evicted_state
        |> evict_head_record_if_exceeds_limit()
        |> do_write(key, value, lifetime, ratio)
      {:reply, :ok, new_state, @timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    new_state = evict_expired_records(state, System.monotonic_time(:milliseconds))
    {:noreply, new_state, @timeout}
  end

  defp evict_expired_records(%{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state, current_time) do
    if :gb_sets.is_empty(expire_at_set) do
      state
    else
      {{expire_at, key}, new_expire_at_set} = :gb_sets.take_largest(expire_at_set)
      if expire_at < current_time do
        Memcache.delete(key, epool_id)
        new_records = Map.delete(records, key)
        evict_expired_records(%{state | records: new_records, expire_at_set: new_expire_at_set}, current_time)
      else
        state
      end
    end
  end

  defp evict_head_record_if_exceeds_limit(%{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state) do
    if map_size(records) == @max_records_num do
      {{_expire_at, key}, new_expire_at_set} = :gb_sets.take_largest(expire_at_set)
      Memcache.delete(key, epool_id)
      new_records = Map.delete(records, key)
      %{state | records: new_records, expire_at_set: new_expire_at_set}
    else
      state
    end
  end

  defp do_write(%{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state, key, value, lifetime, ratio) do
    now            = System.monotonic_time(:milliseconds)
    expire_at      = now + lifetime * 1_000
    prob_expire_at = now + round(lifetime * ratio * 1_000)
    Memcache.write(key, value, expire_at, prob_expire_at, epool_id)
    new_expire_at_set = insert_new_expire_at(expire_at_set, expire_at, key, records)
    new_records       = Map.put(records, key, expire_at)
    %{state | records: new_records, expire_at_set: new_expire_at_set}
  end

  defp insert_new_expire_at(expire_at_set, expire_at, key, records) do
    new_expire_at_set =
      case Map.fetch(records, key) do
        :error               -> expire_at_set
        {:ok, old_expire_at} -> :gb_sets.delete({old_expire_at, key}, expire_at_set)
      end
    :gb_sets.insert({expire_at, key}, new_expire_at_set)
  end

  #
  # Public API
  #
  defun write(key                 :: term,
              value               :: term,
              epool_id            :: v[EPoolId.t],
              lifetime_in_sec     :: integer,
              prob_lifetime_ratio :: float) :: :ok | {:error, :too_large_object} do
    GenServer.call(RegName.memcache_manager(epool_id), {:write, key, value, lifetime_in_sec, prob_lifetime_ratio})
  end
end
