defmodule <%= gear_name_camel %> do
  use Antikythera.GearApplication
  alias Antikythera.{ExecutorPool, Conn}

  @type child_spec :: [:supervisor.child_spec | {module, term} | module]

  @spec children :: child_spec
  def children() do
    [
      # gear-specific workers/supervisors
    ]
  end

  @spec executor_pool_for_web_request(Conn.t) :: ExecutorPool.Id.t
  def executor_pool_for_web_request(_conn) do
    # specify executor pool to use; change the following line if your gear serves to multiple tenants
    {:gear, :<%= gear_name %>}
  end
end
