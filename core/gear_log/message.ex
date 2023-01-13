# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.Message do
  alias Antikythera.{Time, ContextId}
  alias AntikytheraCore.GearLog.Level
  @type t :: {Time.t(), Level.t(), ContextId.t(), String.t()}
end
