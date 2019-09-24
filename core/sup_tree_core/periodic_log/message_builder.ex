# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.PeriodicLog.MessageBuilder do
  @max_proc_to_log     5
  @max_msg_to_log      10
  @queue_len_threshold 100

  def init() do
    nil
  end

  def build_log(state) do
    procs =
      :recon.proc_count(:message_queue_len, @max_proc_to_log)
      |> Enum.filter(fn({_pid, qlen, _info}) -> qlen >= @queue_len_threshold end)
    if procs != [] do
      log_time = Antikythera.Time.to_iso_timestamp(Antikythera.Time.now())
      log =
        procs
        |> Enum.reduce(log_time, fn({pid, qlen, info}, acc) ->
          acc2 = acc <> "\n" <> Integer.to_string(qlen) <> " " <> inspect(info, structs: false)
          process_info = Process.info(pid)
          if process_info != nil do
            process_info
            |> Keyword.get(:messages)
            |> Enum.take(@max_msg_to_log)
            |> Enum.reduce(acc2, fn(msg, acc) -> acc <> "\n\t" <> inspect(msg, structs: false) end)
          else
            # Since the process is already dead, write minimal information
            acc2
          end
        end)
      {log, state}
    else
      {nil, state}
    end
  end
end
