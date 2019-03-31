# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.MetricsUploaderTest do
  use Croma.TestCase, alias_as: U
  alias Antikythera.Time
  alias AntikytheraCore.Metrics.AggregateStrategy.Average
  alias AntikytheraCore.Cluster.NodeId
  alias AntikytheraEal.MetricsStorage, as: Storage

  test "submit should reject invalid arguments" do
    catch_error U.submit(U, [                                                        ])
    catch_error U.submit(U, [{:not_a_string  , :average             , 1             }])
    catch_error U.submit(U, [{"metrics_type1", :nonexisting_strategy, 1.5           }])
    catch_error U.submit(U, [{"metrics_type1", :average             , "not a number"}])
  end

  defp submit(t, values, epool_id \\ :nopool) do
    metrics_data = Enum.map(values, fn v -> {"metrics1", :average, v} end)
    U.submit_with_time(U, t, metrics_data, epool_id)
  end

  defp force_data_flushing() do
    send(U, :flush_data)
    :sys.get_state(U).buffer
  end

  defp download_and_get_value(t) do
    t1 = Time.truncate_to_minute(t)
    t2 = Time.shift_minutes(t1, 1)
    Storage.Memory.download(:antikythera, :nopool, t1, t2)
    |> Enum.map(fn {_time, doc} ->
      assert_document_properties(doc)
      doc
    end)
    |> Enum.find_value(fn doc -> doc["metrics1_avg"] end)
  end

  defp clear_existing_metrics() do
    Agent.update(Storage.Memory, fn _ -> %{} end)
  end

  defp assert_document_properties(doc) do
    assert doc["node_id"     ] == NodeId.get()
    assert doc["otp_app_name"] == "antikythera"
  end

  test "data should be correctly transferred by submit => flush => download" do
    now = Time.now()
    t_past = Time.shift_minutes(now, -1)

    # Metrics not associated to ExecutorPool
    submit(t_past, [0.1, 0.2, 0.3])
    buffer1 = force_data_flushing()
    assert buffer1[Time.truncate_to_minute(t_past)] == nil
    assert_in_delta(download_and_get_value(t_past), 0.2, 0.00001)

    t_future = Time.shift_minutes(now, 1)
    submit(t_future, [0.4, 0.5, 0.6])
    buffer2 = force_data_flushing() # should not flush anything
    future_unit = {Time.truncate_to_minute(t_future), :nopool}
    assert buffer2[future_unit] == %{{"metrics1", Average} => {3, 1.5}}
    assert_in_delta(download_and_get_value(t_past), 0.2, 0.00001)
    assert download_and_get_value(t_future) == nil
    clear_existing_metrics()

    # Metrics associated to ExecutorPool
    submit(t_past, [0.1, 0.2, 0.3], {:gear, :testgear})
    submit(t_past, [0.4, 0.5, 0.6], {:tenant, "g_12345678"})
    _ = force_data_flushing()

    [{_t, %{"metrics1_avg" => v1}}] = Storage.Memory.download(:antikythera, {:gear, :testgear}, t_past, t_future)
    assert_in_delta(v1, 0.2, 0.00001)
    [{_t, %{"metrics1_avg" => v2}}] = Storage.Memory.download(:antikythera, {:tenant, "g_12345678"}, t_past, t_future)
    assert_in_delta(v2, 0.5, 0.00001)
  end

  test "data should be transferred on termination" do
    epool_id = {:gear, :testgear}
    t1 = Time.truncate_to_minute(Time.now())
    t2 = Time.shift_minutes(t1, 1)
    assert Storage.Memory.download(:testgear, epool_id, t1, t2) == []
    {:ok, pid} = U.start_link([:testgear, Testgear.MetricsUploader])
    U.submit(pid, [{"metrics1", :average, 5.0}], epool_id)
    :ok = GenServer.stop(pid)
    [{_time, data}] = Storage.Memory.download(:testgear, epool_id, t1, t2)
    assert data["metrics1_avg"] == 5.0
  end
end
