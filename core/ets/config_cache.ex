# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets.ConfigCache do
  defun init() :: :ok do
    AntikytheraCore.Ets.create_read_optimized_table(table_name())
  end

  defun table_name() :: atom do
    :antikythera_config_cache
  end
end

defmodule AntikytheraCore.Ets.ConfigCache.Core do
  @table_name AntikytheraCore.Ets.ConfigCache.table_name()

  defun read() :: map do
    :ets.lookup_element(@table_name, :antikythera, 2)
  end

  defun write(m :: v[map]) :: :ok do
    :ets.insert(@table_name, {:antikythera, m})
    :ok
  end
end

defmodule AntikytheraCore.Ets.ConfigCache.Gear do
  @table_name AntikytheraCore.Ets.ConfigCache.table_name()
  alias Antikythera.GearName
  alias AntikytheraCore.Config.Gear, as: GearConfig

  defun read(gear_name :: v[GearName.t]) :: nil | GearConfig.t do
    case :ets.lookup(@table_name, gear_name) do
      []                          -> nil
      [{_gear_name, gear_config}] -> gear_config
    end
  end

  defun write(gear_name :: v[GearName.t], conf :: v[GearConfig.t]) :: :ok do
    :ets.insert(@table_name, {gear_name, conf})
    :ok
  end
end
