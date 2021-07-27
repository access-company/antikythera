# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.PeriodicLog.MessageBuilderTest do
  use Croma.TestCase

  @max_proc_to_log 5
  @max_msg_to_log 10
  @queue_len_threshold 100

  defp mock_recon_proc_count_with_one_process(pid) do
    :meck.expect(:recon, :proc_count, fn :message_queue_len, @max_proc_to_log ->
      [{pid, @queue_len_threshold, [:dummy]}]
    end)
  end

  setup do
    on_exit(&:meck.unload/0)
  end

  describe "build_log/1" do
    test "should build log without messages if the process has already exited" do
      pid = spawn(fn -> :ok end)
      mock_recon_proc_count_with_one_process(pid)

      refute Process.alive?(pid)

      {log, nil} = MessageBuilder.build_log(nil)
      assert String.ends_with?(log, "This process has already exited.")
    end

    test "should build log containing messages if the process has some messages" do
      pid = spawn(fn -> Process.sleep(1_000) end)
      mock_recon_proc_count_with_one_process(pid)

      messages = Enum.map(1..@max_msg_to_log, &{:hello, &1})
      Enum.each(messages, &send(pid, &1))

      {log, nil} = MessageBuilder.build_log(nil)

      Enum.each(messages, fn msg ->
        assert String.contains?(log, inspect(msg, structs: false))
      end)

      Process.exit(pid, :kill)
    end
  end
end
