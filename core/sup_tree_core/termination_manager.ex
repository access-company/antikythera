# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

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
    alias AntikytheraCore.VersionUpgradeTaskQueue

    use Croma.Struct, recursive_new?: true, fields: [
      in_service?:          Croma.Boolean,
      not_in_service_count: Croma.NonNegInteger,
      brokers:              Croma.TypeGen.list_of(Croma.Pid),
    ]

    @threshold_count 3

    defun next(%__MODULE__{in_service?: in_service?, not_in_service_count: count, brokers: brokers} = state,
               now_in_service? :: v[boolean]) :: t do
      new_count = if now_in_service?, do: 0, else: count + 1
      if in_service? and new_count >= @threshold_count do
        L.info("confirmed that this host is to be terminated; start cleanup...")
        VersionUpgradeTaskQueue.disable()
        cleanup(brokers)
        %State{state | in_service?: false, not_in_service_count: new_count}
      else
        %State{state | not_in_service_count: new_count}
      end
    end

    defp cleanup(brokers) do
      RaftFleet.deactivate()
      Enum.each(brokers, &AsyncJobBroker.deactivate/1)
      WebsocketConnectionsCounter.start_terminating_all_ws_connections()
    end
  end

  @interval 180_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    set_timer()
    {:ok, %State{in_service?: true, not_in_service_count: 0, brokers: []}}
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
