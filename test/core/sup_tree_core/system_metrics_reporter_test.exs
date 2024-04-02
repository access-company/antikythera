# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.SystemMetricsReporterTest do
  use Croma.TestCase
  alias Antikythera.Time
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.Metrics.AggregateStrategy.Gauge

  setup do
    # will be killed together with `self` when each test is completed
    {:ok, pid} = SystemMetricsReporter.start_link([self()])
    {:ok, [pid: pid]}
  end

  test "should report metrics data on every :timeout", context do
    start_time = Time.now()
    pid = context[:pid]
    send(pid, :timeout)
    {t, data_list, :nopool} = GenServerHelper.receive_cast_message()
    assert start_time <= t
    assert Enum.any?(data_list, &match?({"vm_messages_in_mailboxes", Gauge, _}, &1))
    assert Enum.any?(data_list, &match?({"vm_reductions", Gauge, _}, &1))
  end

  describe "get_recon_infos_for_too_many_messages/1" do
    test "should return a list containing five elements if threshold is zero" do
      infos = SystemMetricsReporter.list_details_of_too_many_messages_processes(0)
      assert length(infos) == 5
    end

    test "should return an empty list if threshold is large enough" do
      infos = SystemMetricsReporter.list_details_of_too_many_messages_processes(1_000_000_000)
      assert infos == []
    end
  end
end
