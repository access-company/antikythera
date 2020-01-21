# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.PeriodicLog.ReductionBuilder do
  @max_proc_to_log 20

  def init() do
    get_reduction_map()
  end

  def build_log(prev_reduction) do
    log_time = Antikythera.Time.to_iso_timestamp(Antikythera.Time.now())
    current_reduction = get_reduction_map()
    msg =
      make_diff(current_reduction, prev_reduction)
      |> Enum.take(@max_proc_to_log)
      |> Enum.reduce(log_time, fn(diff, acc) ->
        acc <> "\n" <> inspect(diff, structs: false)
      end)
    {msg, current_reduction}
  end

  defp get_reduction_map() do
    # If the second argument (number of processes to be acquired) is too small,
    # the difference in reduction cannot be calculated correctly. But if it is
    # too large, the load is high. So sufficiently large value is specified.
    # The number of processes in a normal production environment is less than 5,000.
    :recon.proc_count(:reductions, 20_000) |> Map.new(fn {pid, count, other} -> {pid, {count, other}} end)
  end

  defp make_diff(current, prev) do
    current
    |> Enum.map(fn {pid, {count, other}} ->
      prev_cnt = Map.get(prev, pid, {0, nil}) |> elem(0)
      {pid, {count - prev_cnt, other}}
    end)
    |> Enum.sort_by(fn {_pid, {c, _}} -> c end, &>=/2)
  end
end

