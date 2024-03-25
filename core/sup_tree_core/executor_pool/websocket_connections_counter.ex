# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter do
  @moduledoc """
  A `GenServer` to count number of websocket connections that belong to the executor pool.

  Before termination of the current host, all monitored websocket connections will be disconnected
  in order to prompt clients to reconnect to other active nodes
  (this is executed within temporary processes but uses monitors created by this `GenServer`).
  """

  use GenServer
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName

  def start_link([max, name]) do
    start_link(max, name)
  end

  defunp start_link(max :: v[non_neg_integer], name :: v[atom]) :: {:ok, pid} do
    GenServer.start_link(__MODULE__, max, name: name)
  end

  @impl true
  def init(max) do
    {:ok, %{count: 0, max: max, rejected: 0}}
  end

  @impl true
  def handle_call({:increment, pid}, _from, %{count: count, max: max, rejected: rejected} = state) do
    if count < max do
      Process.monitor(pid)
      {:reply, :ok, %{state | count: count + 1}}
    else
      {:reply, {:error, :too_many_connections}, %{state | rejected: rejected + 1}}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply, state, %{state | rejected: 0}}
  end

  @impl true
  def handle_cast({:set_max, max}, state) do
    {:noreply, %{state | max: max}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, %{count: count} = state) do
    {:noreply, %{state | count: count - 1}}
  end

  #
  # Public API
  #
  defun increment(epool_id :: v[EPoolId.t()], ws_pid :: v[pid]) ::
          :ok | {:error, :too_many_connections} do
    GenServer.call(RegName.websocket_connections_counter(epool_id), {:increment, ws_pid})
  end

  defun stats(epool_id :: v[EPoolId.t()]) :: %{(:count | :max | :rejected) => non_neg_integer} do
    GenServer.call(RegName.websocket_connections_counter(epool_id), :stats)
  end

  defun set_max(epool_id :: v[EPoolId.t()], max :: v[non_neg_integer]) :: :ok do
    GenServer.cast(RegName.websocket_connections_counter(epool_id), {:set_max, max})
  end

  #
  # terminating websocket connection processes
  #
  @random_wait_time_max if Antikythera.Env.compiling_for_cloud?(), do: 10 * 60_000, else: 10
  @deadline_to_kill_all_connections if Antikythera.Env.compiling_for_cloud?(),
                                      do: 30 * 60_000,
                                      else: 50

  defun start_terminating_all_ws_connections() :: :ok do
    spawn(&gradually_terminate_all_ws_connections/0)
    :ok
  end

  # This is originally private; it's public just in order to call it in testgear's test code
  defun gradually_terminate_all_ws_connections() :: :ok do
    Supervisor.which_children(AntikytheraCore.ExecutorPool.Sup)
    |> Enum.each(fn {_, exec_pool_sup, _, _} ->
      counter_pid =
        Supervisor.which_children(exec_pool_sup)
        |> Enum.find_value(fn
          {__MODULE__, pid, _, _} -> pid
          _ -> nil
        end)

      spawn_monitor(fn -> gradually_terminate_ws_connections(counter_pid) end)
    end)
  end

  defunp gradually_terminate_ws_connections(counter_pid :: v[pid]) :: :ok do
    # In addition to per-connection delays, for each exec pool we introduce random delay before starting termination
    # in order not to create many timers at once.
    # Note that all connections will be terminated within (approximately) 40 minutes
    # (`@random_wait_time_max + @deadline_to_kill_all_connections`).
    :timer.sleep(:rand.uniform(@random_wait_time_max))

    case Process.info(counter_pid, :monitors) do
      # counter_pid is not alive
      nil ->
        :ok

      {:monitors, []} ->
        :ok

      {:monitors, ms} ->
        {pids_with_index, len} =
          Enum.map_reduce(ms, 0, fn {:process, pid}, i -> {{pid, i}, i + 1} end)

        interval = @deadline_to_kill_all_connections / len

        Enum.each(pids_with_index, fn {pid, i} ->
          Process.send_after(pid, {:antikythera_internal, :close}, round(interval * i))
        end)
    end
  end
end
