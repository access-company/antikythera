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

  test "should report hackney default connection pool metrics when the pool exists", context do
    # The default pool is created lazily and shared, so only start/stop it if it isn't already running.
    pool_started_by_test = :hackney_pool.find_pool(:default) == :undefined
    if pool_started_by_test, do: :ok = :hackney_pool.start_pool(:default, max_connections: 11)

    try do
      stats = :hackney_pool.get_stats(:default)
      in_use = Keyword.fetch!(stats, :in_use_count)
      free = Keyword.fetch!(stats, :free_count)

      send(context[:pid], :timeout)
      {_t, data_list, :nopool} = GenServerHelper.receive_cast_message()

      assert Enum.any?(
               data_list,
               &match?({"default_connection_pool_in_use_count", Gauge, ^in_use}, &1)
             )

      assert Enum.any?(data_list, &match?({"default_connection_pool_in_use_%", Gauge, _}, &1))

      assert Enum.any?(
               data_list,
               &match?({"default_connection_pool_free_count", Gauge, ^free}, &1)
             )
    after
      if pool_started_by_test, do: :hackney_pool.stop_pool(:default)
    end
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
