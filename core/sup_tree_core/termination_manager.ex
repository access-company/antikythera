# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.TerminationManager do
  @moduledoc """
  A GenServer that periodically checks the status of `Node.self/0`.

  When this `GenServer` notices that this host is going to be terminated, it prepares for termination:

  - deactivate `RaftFleet` so that all consensus members in this node will be migrated to other active nodes
  - deactivate `AntikytheraCore.ExecutorPool.AsyncJobBroker`s so that they don't start new async jobs

  Depends on `AntikytheraCore.ClusterHostsPoller`.
  """

  use GenServer
  alias AntikytheraCore.Cluster
  alias AntikytheraCore.ClusterHostsPoller
  require AntikytheraCore.Logger, as: L

  defmodule State do
    alias AntikytheraCore.ExecutorPool.AsyncJobBroker
    alias AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter
    alias AntikytheraCore.GearLog.Writer
    alias AntikytheraCore.GearManager
    alias AntikytheraCore.VersionUpgradeTaskQueue

    use Croma.Struct, recursive_new?: true, fields: [
      in_service?:          Croma.Boolean,
      log_flushed?:         Croma.Boolean,
      not_in_service_count: Croma.NonNegInteger,
      brokers:              Croma.TypeGen.list_of(Croma.Pid),
    ]

    defun new() :: t do
      %__MODULE__{in_service?: true, log_flushed?: false, not_in_service_count: 0, brokers: []}
    end

    @threshold_count 3
    # Ensure 30 minutes have passed since the async job brokers stopped in `cleanup/1`
    @flush_log_threshold_count @threshold_count + 11

    defun next(%__MODULE__{in_service?: in_service?, log_flushed?: log_flushed?, not_in_service_count: count, brokers: brokers} = state,
               now_in_service? :: v[boolean]) :: t do
      new_count = if now_in_service?, do: 0, else: count + 1
      cond do
        in_service? and new_count >= @threshold_count ->
          L.info("confirmed that this host is to be terminated; start cleanup...")
          VersionUpgradeTaskQueue.disable()
          cleanup(brokers)
          %State{state | not_in_service_count: new_count, in_service?: false}
        !log_flushed? and new_count >= @flush_log_threshold_count ->
          L.info("start flushing gear logs...")
          flush_gear_logs()
          %State{state | not_in_service_count: new_count, log_flushed?: true}
        true ->
          %State{state | not_in_service_count: new_count}
      end
    end

    defp cleanup(brokers) do
      RaftFleet.deactivate()
      Enum.each(brokers, &AsyncJobBroker.deactivate/1)
      WebsocketConnectionsCounter.start_terminating_all_ws_connections()
    end

    defp flush_gear_logs() do
      Enum.each(GearManager.running_gear_names(), &Writer.rotate/1)
    end
  end

  @interval 180_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    set_timer()
    {:ok, State.new()}
  end

  @impl true
  def handle_call({:register_broker, pid}, _from, state) do
    case state do
      %State{in_service?: true, brokers: bs} -> {:reply, :ok, %State{state | brokers: [pid | bs]}}
      %State{in_service?: false}             -> {:reply, {:error, :not_in_service}, state}
    end
  end

  @impl true
  def handle_info(:check_host_status, state) do
    new_state =
      case ClusterHostsPoller.current_hosts() do
        {:ok, hosts}                   -> State.next(state, Map.get(hosts, Cluster.node_to_host(Node.self()), false))
        {:error, :not_yet_initialized} -> state
      end
    set_timer()
    {:noreply, new_state}
  end

  defp set_timer() do
    Process.send_after(self(), :check_host_status, @interval)
  end

  #
  # Public API
  #
  defun register_broker() :: :ok | {:error, :not_in_service} do
    GenServer.call(__MODULE__, {:register_broker, self()})
  end
end
