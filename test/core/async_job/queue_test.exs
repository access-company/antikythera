# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.AsyncJob.QueueTest do
  use Croma.TestCase
  alias Antikythera.{Time, Cron}
  alias Antikythera.Test.{GenServerHelper, AsyncJobHelper}
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.ExecutorPool.AsyncJobBroker, as: Broker
  alias AntikytheraCore.AsyncJob
  alias AntikytheraCore.AsyncJob.RateLimit

  defmodule TestJob do
    use Antikythera.AsyncJob

    @impl true
    def run(_payload, _metadata, _context) do
      :ok
    end
  end

  @epool_id   {:gear, :testgear}
  @queue_name RegName.async_job_queue_unsafe(@epool_id)
  @setting    %EPoolSetting{n_pools_a: 2, pool_size_a: 1, pool_size_j: 1, ws_max_connections: 10}
  @payload    %{foo: "bar"}
  @job_id     "foobar"

  defp register_job(opts) do
    case AsyncJob.register(:testgear, TestJob, @payload, @epool_id, opts) do
      {:ok, _} -> :ok
      error    -> error
    end
  end

  defp waiting_brokers() do
    {:ok, %Queue{brokers_waiting: bs}} = RaftFleet.query(@queue_name, :all)
    bs
  end

  setup do
    AsyncJobHelper.reset_rate_limit_status(@epool_id)
    ExecutorPool.start_executor_pool(@epool_id, @setting)
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)
    {_, broker_pid, _, _} =
      Supervisor.which_children(RegName.supervisor(@epool_id))
      |> Enum.find(&match?({Broker, _, :worker, _}, &1))
    Broker.deactivate(broker_pid)  # don't run jobs throughout this test case
    _ = :sys.get_state(broker_pid) # wait until deactivate message gets processed
    queue_pid = Process.whereis(@queue_name)
    assert Process.alive?(queue_pid)
    assert Process.info(queue_pid, :priority) == {:priority, :high}
    on_exit(fn ->
      ExecutorPoolHelper.kill_and_wait(@epool_id)
    end)
  end

  test "register and fetch job" do
    # fetch => register; receives a notification
    assert waiting_brokers()                      == []
    assert Queue.fetch_job(@queue_name)           == nil
    assert waiting_brokers()                      == [self()]
    assert Queue.fetch_job(@queue_name)           == nil
    assert waiting_brokers()                      == [self()]
    assert register_job([])                       == :ok
    assert GenServerHelper.receive_cast_message() == :job_registered
    assert waiting_brokers()                      == []
    {_job_key, job1} = Queue.fetch_job(@queue_name)
    assert :erlang.binary_to_term(job1.payload) == @payload
    assert waiting_brokers()                    == []

    # fetch => register with start time; no notification
    assert Queue.fetch_job(@queue_name) == nil
    assert waiting_brokers()            == [self()]
    start_time = Time.shift_milliseconds(Time.now(), 10)
    assert register_job([schedule: {:once, start_time}]) == :ok
    refute_received(_)
    :timer.sleep(10)
    {_job_key, job2} = Queue.fetch_job(@queue_name)
    assert :erlang.binary_to_term(job2.payload) == @payload
    assert waiting_brokers()                    == []

    # register => fetch; no notification
    assert register_job([]) == :ok
    {_job_key, job3} = Queue.fetch_job(@queue_name)
    assert :erlang.binary_to_term(job3.payload) == @payload
    assert waiting_brokers()                    == []
    refute_received(_)
  end

  test "register should validate options" do
    [
      id:             "",
      id:             "ID with invalid chars",
      id:             String.duplicate("a", 33),
      schedule:       {:unexpected_tuple, "foo"},
      schedule:       {:once, Time.shift_milliseconds(Time.now(), -10)},
      schedule:       {:once, Time.shift_days(Time.now(), 51)},
      attempts:       0,
      attempts:       11,
      max_duration:   0,
      max_duration:   1_800_001,
      retry_interval: {-1, 2.0},
      retry_interval: {300_001, 2.0},
      retry_interval: {10_000, 0.9},
      retry_interval: {10_000, 5.1},
    ] |> Enum.each(fn option_pair ->
      {:error, {:invalid_value, _}} = register_job([option_pair])
    end)

    [
      [bypass_job_queue: true, retry_interval: {0, 2.0}                                  ],
      [bypass_job_queue: true, attempts:       9                                         ],
      [bypass_job_queue: true, schedule:       {:once, Time.shift_seconds(Time.now(), 1)}],
    ] |> Enum.each(fn options ->
      {:error, {:invalid_key_combination, _, _}} = register_job(options)
    end)

    [
      id:               String.duplicate("a", 32),
      schedule:         {:once, Time.shift_seconds(Time.now(), 1)},
      schedule:         {:once, Time.shift_days(Time.now(), 49)},
      schedule:         {:cron, Cron.parse!("* * * * *")},
      attempts:         1,
      attempts:         10,
      max_duration:     1,
      max_duration:     1_800_000,
      retry_interval:   {0, 2.0},
      retry_interval:   {300_000, 2.0},
      retry_interval:   {10_000, 1.0},
      retry_interval:   {10_000, 5.0},
      bypass_job_queue: true,
      bypass_job_queue: false,
    ] |> Enum.each(fn option_pair ->
      AsyncJobHelper.reset_rate_limit_status(@epool_id)
      assert register_job([option_pair]) == :ok
    end)
  end

  test "register should reject to add job with existing ID" do
    assert register_job([id: "foobar"]) == :ok
    assert register_job([id: "foobar"]) == {:error, :existing_id}
  end

  test "register should reject to add more than 1000 jobs" do
    Enum.each(1..Queue.max_jobs(), fn _ ->
      AsyncJobHelper.reset_rate_limit_status(@epool_id)
      assert register_job([]) == :ok
    end)
    assert register_job([]) == {:error, :full}
  end

  test "register should reject to use executor pool which is unavailable to the gear" do
    [
      {:gear, :unknown_gear},
    ] |> Enum.each(fn epool_id ->
      assert AsyncJob.register(:testgear, TestJob, @payload, epool_id, []) == {:error, {:invalid_executor_pool, epool_id}}
    end)
  end

  test "register should not add a job with :bypass_job_queue option to the queue" do
    assert Queue.fetch_job(@queue_name)           == nil
    assert register_job([bypass_job_queue: true]) == :ok
    assert Queue.fetch_job(@queue_name)           == nil
  end

  test "register => remove_locked" do
    assert register_job([]) == :ok
    {job_key, _job} = Queue.fetch_job(@queue_name)
    assert Queue.remove_locked_job(@queue_name, job_key) == :ok
    assert Queue.fetch_job(@queue_name) == nil
  end

  test "register => unlock_for_retry: should decrement remaining_attempts" do
    assert register_job([retry_interval: {0, 1.0}]) == :ok
    {{t1, ref} = job_key, job1} = Queue.fetch_job(@queue_name)
    assert Queue.unlock_job_for_retry(@queue_name, job_key) == :ok
    {{t2, ^ref}, job2} = Queue.fetch_job(@queue_name)
    assert t1 <= t2
    assert job2.remaining_attempts == job1.remaining_attempts - 1
    assert Map.delete(job2, :remaining_attempts) == Map.delete(job1, :remaining_attempts)
    assert Queue.fetch_job(@queue_name) == nil
  end

  test "cancel nonexisting job" do
    assert Queue.cancel(@queue_name, @job_id) == {:error, :not_found}
  end

  test "cancel waiting job" do
    second_after = Time.now() |> Time.shift_seconds(1)
    assert register_job([id: @job_id, schedule: {:once, second_after}]) == :ok
    {:ok, status1} = Queue.status(@queue_name, @job_id)
    assert status1.state                      == :waiting
    assert Queue.cancel(@queue_name, @job_id) == :ok
    assert Queue.cancel(@queue_name, @job_id) == {:error, :not_found}
  end

  test "cancel runnable job" do
    assert Queue.fetch_job(@queue_name) == nil
    assert register_job([id: @job_id])  == :ok
    assert Queue.start_jobs_and_get_metrics(Process.whereis(@queue_name))
    assert_receive({:"$gen_cast", :job_registered})
    {:ok, status2} = Queue.status(@queue_name, @job_id)
    assert status2.state                      == :runnable
    assert Queue.cancel(@queue_name, @job_id) == :ok
    assert Queue.cancel(@queue_name, @job_id) == {:error, :not_found}
  end

  test "cancel running job" do
    assert register_job([id: @job_id]) == :ok
    {_key, _job} = Queue.fetch_job(@queue_name)
    {:ok, status3} = Queue.status(@queue_name, @job_id)
    assert status3.state                      == :running
    assert Queue.cancel(@queue_name, @job_id) == :ok
    assert Queue.cancel(@queue_name, @job_id) == {:error, :not_found}
  end

  test "consecutive registrations/cancels should be rejected by rate limit" do
    n = div(RateLimit.max_tokens(), RateLimit.tokens_per_command())
    Enum.each(1..n, fn i ->
      assert register_job([id: @job_id <> "#{i}"]) == :ok
    end)
    {:error, {:rate_limit_reached, _}} = register_job([id: @job_id <> "0"])
    AsyncJobHelper.reset_rate_limit_status(@epool_id)
    assert register_job([id: @job_id <> "0"]) == :ok
    AsyncJobHelper.reset_rate_limit_status(@epool_id)
    Enum.each(1..n, fn i ->
      assert Queue.cancel(@queue_name, @job_id <> "#{i}") == :ok
    end)
    {:error, {:rate_limit_reached, _}} = Queue.cancel(@queue_name, @job_id <> "0")
  end

  test "consecutive fetchings of status should sleep-and-retry on hitting rate limit" do
    t1 = System.system_time(:millisecond)
    Enum.each(1..RateLimit.max_tokens(), fn _ ->
      assert Queue.status(@queue_name, @job_id) == {:error, :not_found}
    end)
    t2 = System.system_time(:millisecond)
    assert t2 - t1 < 100
    assert Queue.status(@queue_name, @job_id) == {:error, :not_found}
    t3 = System.system_time(:millisecond)
    assert t3 - t2 > RateLimit.milliseconds_per_token() - 100
  end

  test "consecutive listings should sleep-and-retry on hitting rate limit" do
    t1 = System.system_time(:millisecond)
    Enum.each(1..RateLimit.max_tokens(), fn _ ->
      assert Queue.list(@queue_name) == []
    end)
    t2 = System.system_time(:millisecond)
    assert t2 - t1 < 100
    assert Queue.list(@queue_name) == []
    t3 = System.system_time(:millisecond)
    assert t3 - t2 > RateLimit.milliseconds_per_token() - 100
  end
end

defmodule AntikytheraCore.AsyncJob.QueueCommandTest do
  use ExUnit.Case
  alias Croma.Result, as: R
  alias Antikythera.{Time, Cron}
  alias Antikythera.AsyncJob.{Id, MaxDuration}
  alias AntikytheraCore.AsyncJob
  alias AntikytheraCore.AsyncJob.Queue

  @now_millis System.system_time(:millisecond)
  @now        Time.from_epoch_milliseconds(@now_millis)
  @cron       Cron.parse!("* * * * *")
  @job_id     Id.generate()
  @job_key    {@now_millis, @job_id}
  @job        AsyncJob.make_job(:testgear, Testgear.DummyModule, %{}, {:once, @now }, true, []) |> R.get!()
  @job_cron   AsyncJob.make_job(:testgear, Testgear.DummyModule, %{}, {:cron, @cron}, true, []) |> R.get!()

  defp make_queue_with_started_job(job) do
    q0 = Queue.new()
    {_, q1} = Queue.command(q0, {{:add, @job_key, job}, @now_millis - 1_000})
    assert_job_waiting(q1)
    {{@job_key, ^job}, q2} = Queue.command(q1, {{:fetch, self()}, @now_millis})
    assert_job_running(q2)
    q2
  end

  defp index_has_id?(index) do
    :gb_sets.to_list(index) |> Enum.any?(fn {_time, id} -> id == @job_id end)
  end

  defp assert_job_waiting(q) do
    assert Map.has_key?(q.jobs, @job_id)
    assert index_has_id?(q.index_waiting)
    refute index_has_id?(q.index_runnable)
    refute index_has_id?(q.index_running)
  end

  defp assert_job_runnable(q) do
    assert Map.has_key?(q.jobs, @job_id)
    refute index_has_id?(q.index_waiting)
    assert index_has_id?(q.index_runnable)
    refute index_has_id?(q.index_running)
  end

  defp assert_job_running(q) do
    assert Map.has_key?(q.jobs, @job_id)
    refute index_has_id?(q.index_waiting)
    refute index_has_id?(q.index_runnable)
    assert index_has_id?(q.index_running)
  end

  defp assert_job_removed(q) do
    refute Map.has_key?(q.jobs, @job_id)
    refute index_has_id?(q.index_waiting)
    refute index_has_id?(q.index_runnable)
    refute index_has_id?(q.index_running)
  end

  test "command/2 success or failure_abandon (once) => remove" do
    q0 = make_queue_with_started_job(@job)
    {:ok, q1} = Queue.command(q0, {{:remove_locked, @job_key}, @now_millis})
    assert_job_removed(q1)
  end

  test "command/2 success or failure_abandon (cron) => requeue" do
    q0 = make_queue_with_started_job(@job_cron)
    {:ok, q1} = Queue.command(q0, {{:remove_locked, @job_key}, @now_millis})
    assert_job_waiting(q1)
    {_, next_time, :waiting} = q1.jobs[@job_id]
    assert next_time == @now_millis - rem(@now_millis, 60_000) + 60_000
  end

  test "command/2 failure_retry (once and cron)" do
    [
      make_queue_with_started_job(@job),
      make_queue_with_started_job(@job_cron),
    ] |> Enum.each(fn q1 ->
      {:ok, q2} = Queue.command(q1, {{:unlock_for_retry, @job_key}, @now_millis})
      assert_job_waiting(q2)
      {j, _, :waiting} = q2.jobs[@job_id]
      assert j.remaining_attempts == @job.remaining_attempts - 1
    end)
  end

  test "command/2 retry by running too long (once and cron)" do
    [
      make_queue_with_started_job(@job),
      make_queue_with_started_job(@job_cron),
    ] |> Enum.each(fn q1 ->
      {_, q2} = Queue.command(q1, {:get_metrics, @now_millis + MaxDuration.max()})
      assert_job_runnable(q2)
      {j, _, :runnable} = q2.jobs[@job_id]
      assert j.remaining_attempts == @job.remaining_attempts - 1
    end)
  end

  test "command/2 abandon by running too long (once) => remove" do
    j = %AsyncJob{@job | remaining_attempts: 1}
    q0 = make_queue_with_started_job(j)
    assert q0.abandoned_jobs == []
    {_, q1} = Queue.command(q0, {:get_metrics, @now_millis + MaxDuration.max()})
    assert q1.abandoned_jobs == [{@job_id, j}]
    assert_job_removed(q1)
  end

  test "command/2 abandon by running too long (cron) => requeue" do
    j = %AsyncJob{@job_cron | remaining_attempts: 1}
    q0 = make_queue_with_started_job(j)
    assert q0.abandoned_jobs == []
    current_time = @now_millis + MaxDuration.max()
    {_, q1} = Queue.command(q0, {:get_metrics, current_time})
    assert q1.abandoned_jobs == [{@job_id, j}]
    assert_job_waiting(q1)
    {j2, next_time, :waiting} = q1.jobs[@job_id]
    assert j2.remaining_attempts == 3
    assert next_time             == current_time - rem(current_time, 60_000) + 60_000
  end

  test "command/2 move waiting jobs that have become runnable" do
    q0 = Queue.new()
    {_, q1} = Queue.command(q0, {{:add, @job_key, @job}, @now_millis - 1_000})
    assert_job_waiting(q1)
    {_, q2} = Queue.command(q1, {:get_metrics, @now_millis + 1_000})
    assert_job_runnable(q2)
  end

  test "command/2 add/remove broker" do
    q0 = Queue.new()
    assert q0.brokers_waiting == []
    {nil, q1} = Queue.command(q0, {{:fetch, self()}, @now_millis})
    assert q1.brokers_waiting == [self()]
    {nil, q2} = Queue.command(q1, {{:fetch, self()}, @now_millis})
    assert q2.brokers_waiting == [self()]
    {:ok, q3} = Queue.command(q2, {{:remove_broker_from_waiting_list, self()}, @now_millis})
    assert q3.brokers_waiting == []
    {:ok, q4} = Queue.command(q3, {{:remove_broker_from_waiting_list, self()}, @now_millis})
    assert q4.brokers_waiting == []
  end

  test "command/2 and query/2 should not crash on receipt of unexpected command" do
    q = Queue.new()
    assert Queue.command(q, nil) == {:ok, q}
    assert Queue.query(q, nil)   == q
  end

  test "remove_locked with outdated job key should simply be ignored" do
    q0 = make_queue_with_started_job(@job)
    job_key_old = {@now_millis - 1000, @job_id}
    {:ok, q1} = Queue.command(q0, {{:remove_locked, job_key_old}, @now_millis})
    assert q1 == q0
  end
end
