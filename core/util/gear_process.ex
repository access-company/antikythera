# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearProcess do
  @max_heap_size String.to_integer(System.get_env("GEAR_PROCESS_MAX_HEAP_SIZE") || "50000000") # 400MB in 64bit architecture
  defun max_heap_size() :: non_neg_integer, do: @max_heap_size

  defun set_max_heap_size() :: :ok do
    # Avoid using `Process.flag/2` as it would be warned by dialyzer
    :erlang.process_flag(:max_heap_size, @max_heap_size)
    :ok
  end

  defun spawn_monitor(m :: v[module], f :: v[atom], as :: [any]) :: {pid, reference} do
    Process.spawn(m, f, as, [:monitor, {:max_heap_size, @max_heap_size}])
  end
end
