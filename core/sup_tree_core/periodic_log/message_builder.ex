# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.PeriodicLog.MessageBuilder do
  @max_proc_to_log     5
  @max_msg_to_log      10
  @queue_len_threshold 100

  def init() do
    nil
  end

  def build_log(state) do
    log =
      :recon.proc_count(:message_queue_len, @max_proc_to_log)
      |> Enum.filter(fn({_pid, qlen, _info}) -> qlen >= @queue_len_threshold end)
      |> build_log_from_processes()
    {log, state}
  end

  defp build_log_from_processes([]), do: nil
  defp build_log_from_processes(procs) do
    log_time = Antikythera.Time.to_iso_timestamp(Antikythera.Time.now())
    procs
    |> Enum.reduce(log_time, fn({pid, qlen, info}, acc) ->
      acc2 = acc <> "\n" <> Integer.to_string(qlen) <> " " <> inspect(info, structs: false)
      append_messages_to_log(acc2, Process.info(pid))
    end)
  end

  defp append_messages_to_log(log, nil), do: log <> "\n    This process has already exited."
  defp append_messages_to_log(log, process_info) do
    process_info
    |> Keyword.get(:messages)
    |> Enum.take(@max_msg_to_log)
    |> Enum.reduce(log, fn(msg, acc) -> acc <> "\n    " <> inspect(msg, structs: false) end)
  end
end
