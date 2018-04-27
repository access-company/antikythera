# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ExecutorPool.Id do
  alias Antikythera.{GearName, TenantId}

  @type nopool_t :: :nopool
  @type t        :: {:gear, GearName.t} | {:tenant, TenantId.t}

  def nopool(), do: :nopool

  defun valid?(v :: term) :: boolean do
    {:gear, gear_name}   -> GearName.valid?(gear_name)
    {:tenant, tenant_id} -> TenantId.valid?(tenant_id)
    _                    -> false
  end

  defun to_string(epool_id :: t) :: String.t do
    {:gear  , gear_name} -> "gear-#{gear_name}"
    {:tenant, tenant_id} -> "tenant-#{tenant_id}"
  end
end
