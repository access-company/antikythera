# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.LoggerFilterTest do
  use Croma.TestCase

  describe "reject_mnesia_down/2" do
    test "stops the mnesia-down error emitted by :syn on node termination" do
      event = %{
        level: :error,
        msg: {~c"Received a MNESIA down event, removing node nonode@nohost", []},
        meta: %{}
      }

      assert LoggerFilter.reject_mnesia_down(event, []) == :stop
    end

    test "ignores other error-level format logs" do
      event = %{level: :error, msg: {~c"some unrelated error occurred", []}, meta: %{}}
      assert LoggerFilter.reject_mnesia_down(event, []) == :ignore
    end

    test "ignores report-shaped events (non-format msg)" do
      event = %{level: :error, msg: {:report, %{reason: :boom}}, meta: %{}}
      assert LoggerFilter.reject_mnesia_down(event, []) == :ignore
    end

    test "ignores non-error levels even with the matching text" do
      event = %{level: :info, msg: {~c"Received a MNESIA down event", []}, meta: %{}}
      assert LoggerFilter.reject_mnesia_down(event, []) == :ignore
    end
  end

  describe "reject_poolsup_kill/2" do
    test "stops supervisor child_terminated reports originating from PoolSup" do
      event = %{
        level: :error,
        msg:
          {:report,
           %{
             label: {:supervisor, :child_terminated},
             report: [supervisor: {self(), PoolSup.Callback}, errorContext: :child_terminated]
           }},
        meta: %{}
      }

      assert LoggerFilter.reject_poolsup_kill(event, []) == :stop
    end

    test "ignores child_terminated reports from other supervisors (genuine crashes still log)" do
      event = %{
        level: :error,
        msg:
          {:report,
           %{
             label: {:supervisor, :child_terminated},
             report: [supervisor: {self(), SomeOther.Supervisor}, errorContext: :child_terminated]
           }},
        meta: %{}
      }

      assert LoggerFilter.reject_poolsup_kill(event, []) == :ignore
    end

    test "ignores unrelated events" do
      event = %{level: :error, msg: {~c"not a supervisor report", []}, meta: %{}}
      assert LoggerFilter.reject_poolsup_kill(event, []) == :ignore
    end
  end
end
