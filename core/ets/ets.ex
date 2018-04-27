# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets do
  defun init_all() :: :ok do
    AntikytheraCore.Ets.SystemCache.init()
    AntikytheraCore.Ets.ConfigCache.init()
    AntikytheraCore.Ets.GearActionRunnerPools.init()
    AntikytheraCore.Ets.TenantToGearsMapping.init()
  end

  defun create_read_optimized_table(table_name :: v[atom]) :: :ok do
    _table_id = :ets.new(table_name, [:public, :named_table, {:read_concurrency, true}])
    :ok
  end
end
