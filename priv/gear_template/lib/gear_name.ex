use Croma

defmodule <%= gear_name_camel %> do
  use Antikythera.GearApplication
  alias Antikythera.{ExecutorPool, Conn}

  @type child_spec :: :supervisor.child_spec() | {module, term} | module

  defun children() :: [child_spec] do
    [
      # gear-specific workers/supervisors
    ]
  end

  defun executor_pool_for_web_request(_conn :: v[Conn.t()]) :: ExecutorPool.Id.t() do
    # specify executor pool to use; change the following line if your gear serves to multiple tenants
    {:gear, :<%= gear_name %>}
  end
end
