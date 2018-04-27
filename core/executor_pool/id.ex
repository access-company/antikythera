# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.Id do
  alias Antikythera.{Env, GearName, TenantId}
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  @type reason :: {:invalid_executor_pool, EPoolId.t} | {:unavailable_tenant, TenantId.t}

  defun validate_association(epool_id :: v[EPoolId.t], gear_name :: v[GearName.t]) :: {:ok, EPoolId.t} | {:error, reason} do
    case epool_id do
      {:gear, ^gear_name}  -> {:ok, epool_id}
      {:tenant, tenant_id} -> find_tenant_executor_pool_id(tenant_id, gear_name)
      _                    -> {:error, {:invalid_executor_pool, epool_id}}
    end
  end

  if Env.compiling_for_release?() do
    defp find_tenant_executor_pool_id(tenant_id, gear_name) do
      alias AntikytheraCore.Ets.TenantToGearsMapping
      if TenantToGearsMapping.associated?(tenant_id, gear_name) do
        {:ok, {:tenant, tenant_id}}
      else
        {:error, {:unavailable_tenant, tenant_id}}
      end
    end
  else
    # If not for release, fall back to gear executor pool (since correctly setting-up tenant executor pools is hard)
    defp find_tenant_executor_pool_id(_tenant_id, gear_name), do: {:ok, {:gear, gear_name}}
  end
end
