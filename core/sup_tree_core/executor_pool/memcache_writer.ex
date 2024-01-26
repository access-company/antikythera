# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.MemcacheWriter do
  @moduledoc """
  A `GenServer` to manage memcache for each executor pool.
  """

  @timeout 300_000
  @max_records_num 100

  use GenServer
  alias AntikytheraCore.Ets.Memcache
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  def start_link([name, epool_id]) do
    GenServer.start_link(__MODULE__, epool_id, name: name)
  end

  @impl true
  def init(epool_id) do
    {:ok, %{epool_id: epool_id, records: %{}, expire_at_set: :gb_sets.new()}, @timeout}
  end

  @impl true
  def handle_call({:write, key, value, lifetime, ratio}, _from, state) do
    new_state =
      state
      |> evict_expired_records(System.monotonic_time(:millisecond))
      |> do_write(key, value, lifetime, ratio)
      |> evict_head_records_if_exceeds_limit()

    {:reply, :ok, new_state, @timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    new_state = evict_expired_records(state, System.monotonic_time(:millisecond))
    {:noreply, new_state, @timeout}
  end

  defp evict_expired_records(
         %{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state,
         current_time
       ) do
    if :gb_sets.is_empty(expire_at_set) do
      state
    else
      {{expire_at, key}, new_expire_at_set} = :gb_sets.take_smallest(expire_at_set)

      if expire_at < current_time do
        Memcache.delete(key, epool_id)
        new_records = Map.delete(records, key)
        new_state = %{state | records: new_records, expire_at_set: new_expire_at_set}
        evict_expired_records(new_state, current_time)
      else
        state
      end
    end
  end

  defp evict_head_records_if_exceeds_limit(
         %{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state
       ) do
    if map_size(records) > @max_records_num do
      {{_expire_at, key}, new_expire_at_set} = :gb_sets.take_smallest(expire_at_set)
      Memcache.delete(key, epool_id)
      new_records = Map.delete(records, key)
      new_state = %{state | records: new_records, expire_at_set: new_expire_at_set}
      evict_head_records_if_exceeds_limit(new_state)
    else
      state
    end
  end

  defp do_write(
         %{records: records, expire_at_set: expire_at_set, epool_id: epool_id} = state,
         key,
         value,
         lifetime,
         ratio
       ) do
    now = System.monotonic_time(:millisecond)
    expire_at = now + lifetime * 1_000
    prob_expire_at = now + round(lifetime * ratio * 1_000)
    Memcache.write(key, value, expire_at, prob_expire_at, epool_id)
    new_expire_at_set = insert_new_expire_at(expire_at_set, expire_at, key, records)
    new_records = Map.put(records, key, expire_at)
    %{state | records: new_records, expire_at_set: new_expire_at_set}
  end

  defp insert_new_expire_at(expire_at_set, expire_at, key, records) do
    new_expire_at_set =
      case Map.fetch(records, key) do
        :error -> expire_at_set
        {:ok, old_expire_at} -> :gb_sets.delete({old_expire_at, key}, expire_at_set)
      end

    :gb_sets.insert({expire_at, key}, new_expire_at_set)
  end

  #
  # Public API
  #
  defun max_records() :: non_neg_integer, do: @max_records_num

  defun write(
          key :: term,
          value :: term,
          epool_id :: EPoolId.t(),
          lifetime_in_sec :: integer,
          prob_lifetime_ratio :: float
        ) :: :ok do
    GenServer.call(
      RegName.memcache_writer(epool_id),
      {:write, key, value, lifetime_in_sec, prob_lifetime_ratio}
    )
  end
end
