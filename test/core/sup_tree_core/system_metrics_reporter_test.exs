# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.SystemMetricsReporterTest do
  use Croma.TestCase
  alias Antikythera.Time
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.Metrics.AggregateStrategy.Gauge

  setup do
    {:ok, pid} = SystemMetricsReporter.start_link([self()]) # will be killed together with `self` when each test is completed
    {:ok, [pid: pid]}
  end

  test "should report metrics data on every :timeout", context do
    start_time = Time.now()
    pid = context[:pid]
    send(pid, :timeout)
    {t, data_list, :nopool} = GenServerHelper.receive_cast_message()
    assert start_time <= t
    assert Enum.any?(data_list, &match?({"vm_messages_in_mailboxes", Gauge, _}, &1))
    assert Enum.any?(data_list, &match?({"vm_reductions"           , Gauge, _}, &1))
  end
end
