# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Cluster.NodeId do
  @moduledoc """
  ID of instance that is visible to gear developers.

  Note that the ID string here uses short hostname (`hostname -s`) instead of fully-qualified one (`hostname -f`)
  in order to make it short by truncating common parts.
  """

  alias Antikythera.NodeId

  @table_name AntikytheraCore.Ets.SystemCache.table_name()
  @key        :node_id

  defun init() :: :ok do
    {:ok, h} = :inet.gethostname()
    node_id = List.to_string(h)
    true = NodeId.valid?(node_id)
    :ets.insert(@table_name, {@key, node_id})
    :ok
  end

  defun get() :: NodeId.t do
    :ets.lookup_element(@table_name, @key, 2)
  end
end
