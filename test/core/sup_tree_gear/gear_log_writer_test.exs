# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.WriterTest do
  use Croma.TestCase
  alias Antikythera.Time
  alias Antikythera.Test.GearConfigHelper
  alias AntikytheraCore.Context

  @dir         Path.join([__DIR__, "..", "..", "..", "_build", "test", "log", "testgear"]) |> Path.expand()
  @logger_name Testgear.Logger # GearLog.Writer API call must use registered name atom

  defp clean() do
    File.rm_rf!(@dir)
  end

  defp write(msg) do
    now = Time.now()
    Writer.info(@logger_name, now, Context.make_context_id(now), msg) # Testgear.AlertManager process/name atom are not required for info/4 call
  end

  defp assert_content_of_rotated(msg) do
    rotated_files = Path.wildcard(@dir <> "/testgear.log.*.gz")
    assert length(rotated_files) == 1
    rotated_path = hd(rotated_files)
    file_content = File.read!(rotated_path) |> :zlib.gunzip()
    assert String.ends_with?(file_content, msg <> "\n")
  end

  defp assert_empty?(pid, b) do
    assert :sys.get_state(pid).log_state.empty? == b
  end

  defp wait_for_timer(pid) do
    timer1 = get_timer(pid)
    :timer.sleep(Process.read_timer(timer1) + 100)
    assert Process.read_timer(timer1) == false
    _ = :sys.get_state(pid) # ensure that the :rotate message has been processed
    timer1
  end

  defp get_timer(pid) do
    :sys.get_state(pid).log_state |> Map.get(:timer)
  end

  setup_all do
    # To run log writer process for `:testgear`
    GearConfigHelper.set_config(:testgear, %{})
  end

  setup do
    clean()
    {:ok, pid} = Writer.start_link([:testgear, @logger_name])
    on_exit(&clean/0)
    {:ok, [pid: pid]}
  end

  test "should not overwrite existing log file", context do
    assert File.exists?(Path.join(@dir, "testgear.log.gz"))
    pid1 = context[:pid]
    assert_empty?(pid1, true)
    write("message 1")
    assert_empty?(pid1, false)
    :ok = GenServer.stop(pid1)

    {:ok, pid2} = Writer.start_link([:testgear, @logger_name])
    assert_content_of_rotated("message 1")
    GenServer.stop(pid2)
  end

  test "should rotate log file over time", context do
    assert Path.wildcard(@dir <> "/testgear.log.*.gz") == []
    pid = context[:pid]
    assert_empty?(pid, true)
    write("message 1")
    assert_empty?(pid, false)
    timer1 = wait_for_timer(pid)
    assert_empty?(pid, true)
    assert_content_of_rotated("message 1")
    timer2 = get_timer(pid)
    assert timer2 != timer1
    assert Process.read_timer(timer2) # timer2 should be valid
  end

  test "should not rotate log file and just reset timer if nothing is ever written", context do
    assert Path.wildcard(@dir <> "/testgear.log.*.gz") == []
    pid = context[:pid]
    timer1 = get_timer(pid)
    assert_empty?(pid, true)
    wait_for_timer(pid)
    assert_empty?(pid, true)
    timer2 = get_timer(pid)
    assert timer2 != timer1
    assert Path.wildcard(@dir <> "/testgear.log.*.gz") == []
  end
end
