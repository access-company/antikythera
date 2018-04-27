# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Context do
  @moduledoc """
  Definition of `SolomonLib.Context` struct which represents a context for an execution of gear code.

  Note that `gear_entry_point` is basically of type `{module, atom}`, it is `nil` during
  (1) `executor_pool_web_request/1` and (2) `no_route/1` error handler.
  """

  alias SolomonLib.{Time, GearName, ContextId, ExecutorPool}

  defmodule GearEntryPoint do
    use Croma.SubtypeOfTuple, elem_modules: [Croma.Atom, Croma.Atom]
  end

  use Croma.Struct, recursive_new?: true, fields: [
    start_time:       Time,
    context_id:       ContextId,
    gear_name:        GearName,
    executor_pool_id: Croma.TypeGen.nilable(ExecutorPool.Id),
    gear_entry_point: Croma.TypeGen.nilable(GearEntryPoint),
  ]
end
