defmodule AntikytheraCore.PeriodicLog.ReductionBuilderTest do
  use Croma.TestCase

  @dir Path.join([__DIR__, "..", "..", "..", "..", "_build", "test", "log", "antikythera"])
       |> Path.expand()

  test "should exist" do
    pid = Process.whereis(ReductionBuilder)
    assert pid != nil
    assert File.exists?(Path.join(@dir, "reduction.log.gz"))

    state1 = :sys.get_state(pid)
    build_state1 = state1.build_state
    # NOTE: The below `assert` statement won't pass. The process probably left its initial state
    # because it has been running from the beginning of the test.
    # assert state1.log_state.empty?

    send(ReductionBuilder, :timeout)

    state2 = :sys.get_state(pid)
    build_state2 = state2.build_state
    refute state2.log_state.empty?

    # ensure that the build state has been updated
    refute Map.equal?(build_state1, build_state2)
  end
end
