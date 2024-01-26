# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Mix.Task do
  @moduledoc """
  Helper functions for making mix tasks in gears.

  **Functions in this module can only be used in mix tasks.**
  """

  alias Antikythera.{NodeId, Time}
  alias AntikytheraCore.Context
  alias AntikytheraCore.GearLog.ContextHelper

  @doc """
  Starts the current antikythera instance and its dependency applications without web server functionality.

  If you need web server functionality in your mix task,
  use `Application.ensure_all_started(Antikythera.Env.antikythera_instance_name())`.
  """
  defun prepare_antikythera_instance() :: :ok do
    System.put_env("NO_LISTEN", "true")
    {:ok, _} = Application.ensure_all_started(Antikythera.Env.antikythera_instance_name())
    :ok
  end

  @doc """
  Set the specified `node_id` to the `Antikythera.ContextId` in GearLog.

  If you want to use GearLog in mix task, you must set `node_id` before you call GearLog functions.

  The `Antikythera.ContextId` in GearLog will become `{timestamp}_{node_id}_{PID}`.
  The `timestamp` and `PID` are automatically got from system.
  """
  defun set_node_id_to_gear_log_context(node_id :: v[NodeId.t()]) :: :ok do
    context_id = Context.make_context_id(Time.now(), node_id)
    ContextHelper.set(context_id)
  end
end
