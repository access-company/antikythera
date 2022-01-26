# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.OsUtil do
  alias AntikytheraCore.Ets.SystemCache

  defun init() :: :ok do
    :ets.insert(
      SystemCache.table_name(),
      {:total_memory_size_in_bytes, get_total_memory_size_in_bytes()}
    )

    :ok
  end

  defun total_memory_size_in_bytes() :: pos_integer do
    [{_, bytes}] = :ets.lookup(SystemCache.table_name(), :total_memory_size_in_bytes)
    bytes
  end

  defunp get_total_memory_size_in_bytes() :: pos_integer do
    case :os.type() do
      {:unix, :linux} -> total_memory_size_linux()
      {:unix, :darwin} -> total_memory_size_darwin()
    end
  end

  defp total_memory_size_linux() do
    {output, 0} = System.cmd("free", ["-b"])
    [_, l | _] = String.split(output, "\n")
    [_, n | _] = String.split(l)
    String.to_integer(n)
  end

  defp total_memory_size_darwin() do
    {output, 0} = System.cmd("sysctl", ["-n", "hw.memsize"])
    String.trim_trailing(output) |> String.to_integer()
  end
end
