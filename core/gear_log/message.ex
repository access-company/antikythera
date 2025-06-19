# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.Message do
  alias Antikythera.ContextId
  alias AntikytheraCore.GearLog
  alias AntikytheraCore.GearLog.Level
  @type t :: {GearLog.Time.t(), Level.t(), ContextId.t(), String.t()}
end
