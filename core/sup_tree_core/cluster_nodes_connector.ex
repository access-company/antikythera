# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ClusterNodesConnector do
  @moduledoc """
  A `GenServer` that tries to keep connections to other known nodes.

  Depends on `AntikytheraCore.ClusterHostsPoller`.
  """

  use GenServer
  alias AntikytheraCore.Cluster
  alias AntikytheraCore.ClusterHostsPoller

  def start_link() do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    # node-to-node connections are already established in `AntikytheraCore.start/2`; majority of nodes are connected.
    {:ok, %{}, interval(true)}
  end

  @impl true
  def handle_info(:timeout, state) do
    majority_connected? =
      case ClusterHostsPoller.current_hosts() do
        {:ok, hosts}                   -> Cluster.connect_to_other_nodes(hosts)
        {:error, :not_yet_initialized} -> true # assuming that it's still connected to majority
      end
    {:noreply, state, interval(majority_connected?)}
  end

  defp interval(true ), do: 180_000
  defp interval(false), do:  60_000
end
