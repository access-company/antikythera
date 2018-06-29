# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.MnesiaNodesCleaner do
  @moduledoc """
  A GenServer that periodically removes extra nodes from mnesia schema.

  When a new node is started it automatically starts to sync both mnesia schema and data with other participating nodes.
  On the other hand when a node is terminated it's not automatically removed from mnesia schema
  (because mnesia has no idea whether the node will re-join the cluster or not).

  This GenServer periodically cleans up any already-terminated nodes from mnesia schema
  by using hosts information from the underlying infrastructure.
  Without this cleanup the "already terminated nodes" would accumulate in mnesia schema
  and make startup of new nodes really slow (new node tries to sync with nonexisting nodes until timeout).

  Depends on `AntikytheraCore.ClusterHostsPoller`.
  """

  @interval 300_000

  use GenServer
  alias AntikytheraCore.Cluster
  alias AntikytheraCore.ClusterHostsPoller
  require AntikytheraCore.Logger, as: L

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}, @interval}
  end

  @impl true
  def handle_info(:timeout, state) do
    case ClusterHostsPoller.current_hosts() do
      {:ok, hosts}                   -> clean_nonexisting_nodes_from_mnesia(hosts)
      {:error, :not_yet_initialized} -> :ok # nothing we can do; just wait and retry again
    end
    {:noreply, state, @interval}
  end

  defp clean_nonexisting_nodes_from_mnesia(hosts) do
    # Compare "host"s (String.t) instead of "node"s (atom) and avoid unnecessary conversions from String.t to atom.
    connected_hosts     = [Node.self() | Node.list()] |> MapSet.new(&Cluster.node_to_host/1)
    current_known_hosts = Enum.into(hosts, connected_hosts, fn {h, _} -> h end)
    :mnesia.system_info(:db_nodes)
    |> Enum.reject(fn n -> MapSet.member?(current_known_hosts, Cluster.node_to_host(n)) end)
    |> Enum.each(fn n ->
      L.info("removing #{n} from mnesia schema")
      # :mnesia.del_table_copy(:schema, node) is idempotent; it's OK for multiple nodes to concurrently call this.
      {:atomic, :ok} = :mnesia.del_table_copy(:schema, n)
    end)
  end
end
