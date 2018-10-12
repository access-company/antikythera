# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma
alias Croma.Result, as: R

defmodule AntikytheraCore.Cluster do
  require AntikytheraCore.Logger, as: L
  alias AntikytheraEal.ClusterConfiguration

  defun connect_to_other_nodes_on_start() :: R.t(boolean) do
    ClusterConfiguration.running_hosts()
    |> R.map(&connect_to_other_nodes/1)
  end

  defun connect_to_other_nodes(running_hosts :: %{String.t => boolean}) :: boolean do
    connected_hosts = [Node.self() | Node.list()] |> Enum.map(&node_to_host/1)
    # Compare hostnames so as not to be confused by "name" part of nodenames (substring before '@').
    unconnected_in_service_hosts = Map.keys(running_hosts) -- connected_hosts
    Enum.each(unconnected_in_service_hosts, &connect/1)
    connected_to_majority?(map_size(running_hosts))
  end

  defunp connect(host :: v[String.t]) :: :ok do
    # The following `String.to_atom` is inevitable; fortunately number of nodes is not too many.
    # Note that the following naming scheme is defined in the boot script and passed to relx's script: see `NODENAME` env var.
    nodename = String.to_atom("antikythera@" <> host)
    case Node.connect(nodename) do
      :ignored -> L.info("failed to connect to #{host} (this node is not alive)")
      false    -> L.info("failed to connect to #{host}")
      true     -> L.info("successfully connected to #{host}")
    end
  end

  defunp connected_to_majority?(n_all_hosts :: v[non_neg_integer]) :: boolean do
    2 * (length(Node.list()) + 1) > n_all_hosts
  end

  defun node_to_host(n :: v[atom]) :: String.t do
    Atom.to_string(n) |> String.split("@") |> Enum.at(1)
  end
end
