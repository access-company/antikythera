# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.ExecutorPool.UsageReporterTest do
  use Croma.TestCase
  alias Antikythera.Time
  alias Antikythera.Test.ProcessHelper
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.Metrics.AggregateStrategy.Gauge

  @epool_id {:gear, :testgear}

  setup do
    {:ok, exec_pool_pid} = ExecutorPool.start_link(@epool_id, self(), EPoolSetting.default())

    {_, pid, _, _} =
      Supervisor.which_children(exec_pool_pid)
      |> Enum.find(&match?({UsageReporter, _, :worker, _}, &1))

    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)

    on_exit(fn ->
      ExecutorPoolHelper.kill_and_wait(@epool_id, fn -> :auto_killed_and_do_nothing end)
    end)

    {:ok, [pid: pid]}
  end

  test "should report usage metrics of its sibling PoolSup.Multi and PoolSup processes",
       context do
    t0 = Time.now()
    ProcessHelper.flush()
    send(context[:pid], :timeout)
    {t, data_list, @epool_id} = GenServerHelper.receive_cast_message()
    assert t0 <= t
    assert Enum.any?(data_list, &match?({"epool_working_action_runner_count", Gauge, 0}, &1))
    assert Enum.any?(data_list, &match?({"epool_working_action_runner_%", Gauge, 0.0}, &1))
    assert Enum.any?(data_list, &match?({"epool_working_job_runner_count", Gauge, 0}, &1))
    assert Enum.any?(data_list, &match?({"epool_working_job_runner_%", Gauge, 0.0}, &1))
    assert Enum.any?(data_list, &match?({"epool_websocket_connections_count", Gauge, 0}, &1))
    assert Enum.any?(data_list, &match?({"epool_websocket_connections_%", Gauge, 0.0}, &1))
    assert Enum.any?(data_list, &match?({"epool_websocket_rejected_count", Gauge, 0}, &1))
  end
end
