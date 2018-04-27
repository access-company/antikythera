# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets.SystemCache do
  defun init() :: :ok do
    AntikytheraCore.Ets.create_read_optimized_table(table_name())
    AntikytheraCore.Cluster.NodeId.init()
    AntikytheraCore.Config.EncryptionKey.init()
    AntikytheraCore.Handler.SystemInfoExporter.AccessToken.init()
  end

  defun table_name() :: atom do
    :antikythera_system_cache
  end
end
