# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets.TenantToGearsMapping do
  alias Antikythera.{GearName, TenantId}

  @table_name :antikythera_tenant_to_gears_mapping
  defun(table_name() :: atom, do: @table_name)

  defun init() :: :ok do
    AntikytheraCore.Ets.create_read_optimized_table(@table_name)
  end

  defun set(tenant_id :: v[TenantId.t()], gear_names :: [GearName.t()]) :: :ok do
    :ets.insert(@table_name, {tenant_id, gear_names})
    :ok
  end

  defun unset(tenant_id :: v[TenantId.t()]) :: :ok do
    :ets.delete(@table_name, tenant_id)
    :ok
  end

  defun associated?(tenant_id :: v[TenantId.t()], gear_name :: v[GearName.t()]) :: boolean do
    case :ets.lookup(@table_name, tenant_id) do
      [] -> false
      [{_, gear_names}] -> gear_name in gear_names
    end
  end
end
