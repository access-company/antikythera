# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.ProcessHelper do
  @moduledoc """
  Helper functions to work with processes in test code.
  """

  def monitor_wait(pid_or_regname) do
    pid = if is_pid(pid_or_regname), do: pid_or_regname, else: Process.whereis(pid_or_regname)
    Process.monitor(pid)

    receive do
      {:DOWN, _monitor_ref, :process, ^pid, _reason} -> :ok
    after
      10_000 ->
        raise "DOWN message about #{inspect(pid_or_regname)} has not come in within 10 seconds"
    end
  end

  def flush() do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
