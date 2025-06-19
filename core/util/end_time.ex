# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.EndTime do
  # Antikythera uses different "time" for different purposes.

  alias AntikytheraCore.GearLog
  alias Antikythera.Time

  use Croma.Struct,
    fields: [
      # For calculating execution time
      monotonic: Croma.Integer,
      # For logging
      gear_log: GearLog.Time,
      # For general purposes
      antikythera_time: Time
    ]

  defun now() :: __MODULE__.t() do
    %__MODULE__{
      monotonic: System.monotonic_time(:millisecond),
      gear_log: GearLog.Time.now(),
      antikythera_time: Time.now()
    }
  end
end
