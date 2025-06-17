# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.Context do
  use Croma.Struct,
    fields: [
      start_monotonic_time: Croma.Integer
    ]

  defun make() :: __MODULE__.t() do
    %__MODULE__{
      start_monotonic_time: System.monotonic_time(:millisecond)
    }
  end
end
