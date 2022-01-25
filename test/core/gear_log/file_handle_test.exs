# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.FileHandleTest do
  use Croma.TestCase
  alias Antikythera.Time

  @tmp_dir Path.join([__DIR__, "..", "..", "tmp"]) |> Path.expand()
  @log_file_path Path.join([@tmp_dir, "log", "gear.log"]) |> Path.expand()
  @log_time Time.now()
  @context_id AntikytheraCore.Context.make_context_id(@log_time)
  @gear_log {@log_time, :info, @context_id, "test_log"}

  setup do
    File.rm_rf(@tmp_dir)
    on_exit(fn -> {:ok, _} = File.rm_rf(@tmp_dir) end)
  end

  defp assert_file_content(logs) do
    logs_on_file = File.read!(@log_file_path) |> :zlib.gunzip() |> String.split("\n", trim: true)

    expected_logs =
      Enum.flat_map(logs, fn {time, level, context_id, message} ->
        String.split(message, "\n", trim: true)
        |> Enum.map(fn line ->
          Time.to_iso_timestamp(time) <> " [#{level}] context=#{context_id} #{line}"
        end)
      end)

    assert logs_on_file == expected_logs
  end

  test "write/2 should persist log message" do
    log_with_linebreak = {@log_time, :info, @context_id, "line1\nline2"}
    handle = FileHandle.open(@log_file_path)
    {:kept_open, _} = FileHandle.write(handle, @gear_log)
    {:kept_open, _} = FileHandle.write(handle, log_with_linebreak)
    FileHandle.close(handle)
    assert_file_content([@gear_log, log_with_linebreak])
  end

  test "write/2 should ensure file size is not too large" do
    handle1 = FileHandle.open(@log_file_path)
    over_4k_byte_log = {@log_time, :info, @context_id, String.duplicate("a", 10_000_000)}
    {:kept_open, _} = FileHandle.write(handle1, over_4k_byte_log)
    # Wait until size check interval elapses
    :timer.sleep(110)

    log_msg =
      {Time.now(), :info, @context_id, "next message after the log file size exceeds limit"}

    {:rotated, handle2} = FileHandle.write(handle1, log_msg)
    FileHandle.close(handle2)
    assert_file_content([log_msg])
  end

  test "write/2 should accept malformed (non-UTF8) log message" do
    log_with_malformed_msg = {@log_time, :info, @context_id, :crypto.strong_rand_bytes(10)}
    handle = FileHandle.open(@log_file_path)
    {:kept_open, _} = FileHandle.write(handle, @gear_log)
    {:kept_open, _} = FileHandle.write(handle, log_with_malformed_msg)
    {:kept_open, _} = FileHandle.write(handle, @gear_log)
    FileHandle.close(handle)
    assert_file_content([@gear_log, log_with_malformed_msg, @gear_log])
  end

  test "rotate/1" do
    handle1 = FileHandle.open(@log_file_path)
    log_before_rotate = {@log_time, :info, @context_id, "before_rotate"}
    FileHandle.write(handle1, log_before_rotate)

    handle2 = FileHandle.rotate(handle1)
    assert elem(handle1, 2) != elem(handle2, 2)

    log_after_rotate = {@log_time, :info, @context_id, "after_rotate"}
    FileHandle.write(handle2, log_after_rotate)
    FileHandle.close(handle2)
    assert_file_content([log_after_rotate])
  end
end
