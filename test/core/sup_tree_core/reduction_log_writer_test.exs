defmodule AntikytheraCore.ReductionLogWriterTest do
  use Croma.TestCase

  @dir Path.join([__DIR__, "..", "..", "..", "_build", "test", "log", "antikythera"]) |> Path.expand()

  test "should exists" do
    assert Process.whereis(AntikytheraCore.ReductionLogWriter) != nil
    send(AntikytheraCore.ReductionLogWriter, :timeout)
    assert File.exists?(Path.join(@dir, "reduction.log.gz"))
  end
end
