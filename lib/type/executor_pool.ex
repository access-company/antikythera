# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ExecutorPool.Id do
  alias Antikythera.{GearName, TenantId}

  @type nopool_t :: :nopool
  @type t :: {:gear, GearName.t()} | {:tenant, TenantId.t()}

  def nopool(), do: :nopool

  defun valid?(v :: term) :: boolean do
    {:gear, gear_name} -> GearName.valid?(gear_name)
    {:tenant, tenant_id} -> TenantId.valid?(tenant_id)
    _ -> false
  end

  defun to_string(epool_id :: t) :: String.t() do
    {:gear, gear_name} -> "gear-#{gear_name}"
    {:tenant, tenant_id} -> "tenant-#{tenant_id}"
  end
end

defmodule Antikythera.ExecutorPool.BadIdReason do
  alias Antikythera.TenantId
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  @type t :: {:invalid_executor_pool, EPoolId.t()} | {:unavailable_tenant, TenantId.t()}

  defun valid?(term :: term) :: boolean do
    {:invalid_executor_pool, epool_id} -> EPoolId.valid?(epool_id)
    {:unavailable_tenant, tenant_id} -> TenantId.valid?(tenant_id)
    _ -> false
  end
end
