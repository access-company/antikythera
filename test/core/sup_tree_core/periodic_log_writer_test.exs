defmodule AntikytheraCore.PeriodicLogWriterTest do
  use Croma.TestCase

  @dir Path.join([__DIR__, "..", "..", "..", "_build", "test", "log", "antikythera"]) |> Path.expand()

  test "should exists" do
    assert Process.whereis(PeriodicLogWriter.Reduction) != nil
    send(PeriodicLogWriter.Reduction, :timeout)
    assert File.exists?(Path.join(@dir, "reduction.log.gz"))
  end
end
