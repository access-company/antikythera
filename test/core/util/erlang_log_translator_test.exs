# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ErlangLogTranslatorTest do
  use Croma.TestCase
  alias AntikytheraCore.ExecutorPool.ActionRunner

  setup do
    :meck.new(ErlangLogTranslator, [:passthrough])
    on_exit(&:meck.unload/0)
  end

  test "should neglect SASL progress report from supervisor" do
    # Use ActionRunner as just a GenServer, not as a PoolSup worker
    children = [{ActionRunner, [nil]}]
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, name: :test_supervisor)

    # ensure logging
    Process.sleep(100)

    [{_pid, {ErlangLogTranslator, :translate, args}, return}] = :meck.history(ErlangLogTranslator)

    supervisor =
      if System.otp_release() >= "21" do
        [_min_level, :info, :report, {{:supervisor, :progress}, data}] = args
        data[:supervisor]
      else
        [_min_level, :info, :report, {:progress, data}] = args
        data[:supervisor]
      end

    assert return == :skip
    assert supervisor == {:local, :test_supervisor}
  end

  test "should neglect SASL supervisor report on brutal kill of a worker process in nameless PoolSup" do
    {:ok, pool_sup_pid} = PoolSup.start_link(ActionRunner, nil, 1, 0)
    worker_pid = PoolSup.checkout(pool_sup_pid)
    Process.exit(worker_pid, :kill)

    # ensure logging
    Process.sleep(100)

    [{_pid, {ErlangLogTranslator, :translate, args}, return}] = :meck.history(ErlangLogTranslator)

    supervisor =
      if System.otp_release() >= "21" do
        [_min_level, :error, :report, {{:supervisor, :child_terminated}, data}] = args
        data[:supervisor]
      else
        [_min_level, :error, :report, {:supervisor_report, data}] = args
        data[:supervisor]
      end

    assert return == :skip
    assert match?({_pid, PoolSup.Callback}, supervisor)
  end
end
