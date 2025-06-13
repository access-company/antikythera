# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.Context do
  alias AntikytheraCore.GearLog

  use Croma.Struct,
    fields: [
      start_monotonic_time: Croma.Integer,
      start_time_for_log: GearLog.Time
    ]

  defun make() :: __MODULE__.t() do
    %__MODULE__{
      start_monotonic_time: System.monotonic_time(:millisecond),
      start_time_for_log: GearLog.Time.now()
    }
  end
end
