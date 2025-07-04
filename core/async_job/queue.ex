# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.AsyncJob.Queue do
  @moduledoc """
  A queue-like data structure, replicated using `RaftedValue`, to store `AntikytheraCore.AsyncJob` structs.
  """

  alias Croma.Result, as: R
  alias RaftedValue.Data, as: RVData
  alias Antikythera.{Time, Cron, MilliSecondsSinceEpoch}
  alias Antikythera.AsyncJob.{Id, MaxDuration, StateLabel, Status}
  alias AntikytheraCore.AsyncJob
  alias AntikytheraCore.AsyncJob.{RateLimit, RaftedValueConfigMaker}
  alias AntikytheraCore.ExecutorPool.AsyncJobBroker, as: Broker
  alias AntikytheraCore.GearLog

  @max_jobs 1000
  # just for documentation
  def max_jobs(), do: @max_jobs

  defmodule JobsMap do
    defmodule Triplet do
      use Croma.SubtypeOfTuple, elem_modules: [AsyncJob, MilliSecondsSinceEpoch, StateLabel]
    end

    use Croma.SubtypeOfMap, key_module: Id, value_module: Triplet
  end

  defmodule JobKey do
    # make unique sort keys by time(milliseconds) and job ID
    use Croma.SubtypeOfTuple, elem_modules: [MilliSecondsSinceEpoch, Id]
  end

  defmodule SecondaryIndex do
    @type t :: :gb_sets.set(JobKey.t())

    defun valid?(s :: any) :: boolean, do: :gb_sets.is_set(s)
  end

  defmodule IdJobPair do
    use Croma.SubtypeOfTuple, elem_modules: [Id, AsyncJob]
  end

  use Croma.Struct,
    fields: [
      jobs: JobsMap,
      index_waiting: SecondaryIndex,
      index_runnable: SecondaryIndex,
      index_running: SecondaryIndex,
      brokers_waiting: Croma.TypeGen.list_of(Croma.Pid),
      # to propagate information to leader hook
      brokers_to_notify: Croma.TypeGen.list_of(Croma.Pid),
      # to propagate information to leader hook
      abandoned_jobs: Croma.TypeGen.list_of(IdJobPair)
    ]

  @behaviour RVData

  @impl true
  defun new() :: t do
    set = :gb_sets.empty()

    %__MODULE__{
      jobs: %{},
      index_waiting: set,
      index_runnable: set,
      index_running: set,
      brokers_waiting: [],
      brokers_to_notify: [],
      abandoned_jobs: []
    }
  end

  @impl true
  defun command(q1 :: v[t], cmd :: RVData.command_arg()) :: {RVData.command_ret(), t} do
    case cmd do
      {{:add, job_key, job}, now_millis} ->
        insert(q1, job_key, job) |> maintain_invariants_and_return(now_millis)

      {{:fetch, broker}, now_millis} ->
        fetch(q1, broker, now_millis) |> maintain_invariants_and_return(now_millis)

      {{:remove_locked, job_key}, now_millis} ->
        {:ok, remove_locked(q1, job_key, now_millis)}
        |> maintain_invariants_and_return(now_millis)

      {{:unlock_for_retry, job_key}, now_millis} ->
        {:ok, unlock_for_retry(q1, job_key, now_millis)}
        |> maintain_invariants_and_return(now_millis)

      {{:remove_broker_from_waiting_list, pid}, now_millis} ->
        {:ok, remove_broker(q1, pid)} |> maintain_invariants_and_return(now_millis)

      {{:cancel, job_id}, now_millis} ->
        cancel_job(q1, job_id) |> maintain_invariants_and_return(now_millis)

      {:get_metrics, now_millis} ->
        {metrics(q1), q1} |> maintain_invariants_and_return(now_millis)

      # failsafe: not to crash on unexpected command
      _ ->
        {:ok, q1}
    end
  end

  defp maintain_invariants_and_return({ret, q}, now_millis) do
    {ret, maintain_invariants(q, now_millis)}
  end

  defp maintain_invariants(q, now_millis) do
    q
    |> release_locks_of_jobs_running_too_long(now_millis)
    |> move_now_runnable_jobs(now_millis)
  end

  defunp release_locks_of_jobs_running_too_long(q :: v[t], now_millis :: v[pos_integer]) :: t do
    %__MODULE__{q | abandoned_jobs: []}
    |> move_jobs_running_too_long(now_millis)
  end

  defunp move_jobs_running_too_long(
           %__MODULE__{index_running: index_running} = q :: v[t],
           now_millis :: v[pos_integer]
         ) :: v[t] do
    threshold_time = now_millis - MaxDuration.max()

    case take_smallest_with_earlier_timestamp(index_running, threshold_time) do
      nil ->
        q

      {job_key, index_running2} ->
        %__MODULE__{q | index_running: index_running2}
        |> abandon_job_or_requeue_for_retry(job_key, now_millis)
        |> move_jobs_running_too_long(threshold_time)
    end
  end

  defunp abandon_job_or_requeue_for_retry(
           %__MODULE__{
             jobs: jobs,
             index_waiting: index_waiting,
             abandoned_jobs: abandoned_jobs
           } = q :: v[t],
           {_, job_id} = job_key :: v[JobKey.t()],
           now_millis :: v[pos_integer]
         ) :: v[t] do
    case Map.get_and_update!(jobs, job_id, &try_update_job_triplet_for_retry/1) do
      {{%AsyncJob{remaining_attempts: 1} = job, _, :running}, cleaned_jobs} ->
        %__MODULE__{
          q
          | jobs: cleaned_jobs,
            abandoned_jobs: [{job_id, job} | abandoned_jobs]
        }
        |> requeue_if_recurring(job, job_id, now_millis)

      {{_, _, :running}, updated_jobs} ->
        index_waiting2 = :gb_sets.add(job_key, index_waiting)
        %__MODULE__{q | jobs: updated_jobs, index_waiting: index_waiting2}
    end
  end

  defunp try_update_job_triplet_for_retry(
           {job, time, :running} = current :: v[JobsMap.Triplet.t()]
         ) :: {JobsMap.Triplet.t(), JobsMap.Triplet.t()} | :pop do
    case job.remaining_attempts do
      1 -> :pop
      remaining -> {current, {%AsyncJob{job | remaining_attempts: remaining - 1}, time, :waiting}}
    end
  end

  defp take_smallest_with_earlier_timestamp(set, time) do
    case safe_take_smallest(set) do
      {{t, _}, _} = tuple when t <= time -> tuple
      _ -> nil
    end
  end

  defp safe_take_smallest(set) do
    case :gb_sets.is_empty(set) do
      true -> nil
      false -> :gb_sets.take_smallest(set)
    end
  end

  defunp move_now_runnable_jobs(q :: v[t], now_millis :: v[pos_integer]) :: t do
    %__MODULE__{q | brokers_to_notify: []}
    |> move_now_runnable_jobs_impl(now_millis)
  end

  defunp move_now_runnable_jobs_impl(
           %__MODULE__{
             jobs: jobs,
             index_waiting: index_waiting,
             index_runnable: index_runnable,
             brokers_waiting: brokers_waiting
           } = q :: v[t],
           now_millis :: v[pos_integer]
         ) :: v[t] do
    case take_smallest_with_earlier_timestamp(index_waiting, now_millis) do
      nil ->
        q

      {{_, job_id} = job_key, index_waiting2} ->
        jobs2 = Map.update!(jobs, job_id, fn {j, t, :waiting} -> {j, t, :runnable} end)
        index_runnable2 = :gb_sets.add(job_key, index_runnable)

        q2 = %__MODULE__{
          q
          | jobs: jobs2,
            index_waiting: index_waiting2,
            index_runnable: index_runnable2
        }

        brokers_waiting
        |> move_waiting_broker_to_be_notified(q2)
        |> move_now_runnable_jobs_impl(now_millis)
    end
  end

  defp move_waiting_broker_to_be_notified([], q), do: q

  defp move_waiting_broker_to_be_notified([b | bs], q) do
    %__MODULE__{q | brokers_waiting: bs, brokers_to_notify: [b | q.brokers_to_notify]}
  end

  defp insert(
         %__MODULE__{jobs: jobs, index_waiting: index_waiting} = q,
         {start_time, job_id} = job_key,
         job
       ) do
    if map_size(jobs) < @max_jobs do
      if Map.has_key?(jobs, job_id) do
        {{:error, :existing_id}, q}
      else
        index_waiting2 = :gb_sets.add(job_key, index_waiting)
        jobs2 = Map.put(jobs, job_id, {job, start_time, :waiting})
        {:ok, %__MODULE__{q | jobs: jobs2, index_waiting: index_waiting2}}
      end
    else
      {{:error, :full}, q}
    end
  end

  defunp fetch(
           %__MODULE__{brokers_waiting: bs_waiting} = q :: v[t],
           broker :: v[Croma.Pid.t()],
           now_millis :: v[pos_integer]
         ) :: {{JobKey.t(), AsyncJob.t()} | nil, t} do
    # to avoid duplication, first remove the fetching broker's pid
    bs_waiting2 = remove_brokers_by_node(bs_waiting, broker)
    q_with_bs_waiting2 = %__MODULE__{q | brokers_waiting: bs_waiting2}

    with nil <- fetch_job_with_lock_from_runnable(q_with_bs_waiting2, now_millis),
         nil <- fetch_job_with_lock_from_waiting(q_with_bs_waiting2, now_millis) do
      {nil,
       %__MODULE__{
         q_with_bs_waiting2
         | brokers_waiting: [broker | q_with_bs_waiting2.brokers_waiting]
       }}
    end
  end

  defp remove_brokers_by_node(bs, target_broker) do
    # From `bs` remove (if any) both
    # - `target_broker` itself
    # - stale broker pid before restart (since exactly 1 broker exists per node, pid with the same node must already be dead)
    n = node(target_broker)
    Enum.reject(bs, fn b -> node(b) == n end)
  end

  defunp fetch_job_with_lock_from_runnable(
           %__MODULE__{index_runnable: index_runnable} = q :: v[t],
           now_millis :: v[pos_integer]
         ) :: {{JobKey.t(), AsyncJob.t()}, t} | nil do
    with {{_, job_id}, index_runnable2} <-
           take_smallest_with_earlier_timestamp(index_runnable, now_millis) do
      lock_and_return_job(%__MODULE__{q | index_runnable: index_runnable2}, job_id, now_millis)
    end
  end

  defunp fetch_job_with_lock_from_waiting(
           %__MODULE__{index_waiting: index_waiting} = q :: v[t],
           now_millis :: v[pos_integer]
         ) :: {{JobKey.t(), AsyncJob.t()}, t} | nil do
    with {{_, job_id}, index_waiting2} <-
           take_smallest_with_earlier_timestamp(index_waiting, now_millis) do
      lock_and_return_job(%__MODULE__{q | index_waiting: index_waiting2}, job_id, now_millis)
    end
  end

  defp lock_and_return_job(
         %__MODULE__{jobs: jobs, index_running: index_running} = q,
         job_id,
         now_millis
       ) do
    locked_job_key = {now_millis, job_id}
    index_running2 = :gb_sets.add(locked_job_key, index_running)

    {job, jobs2} =
      Map.get_and_update!(jobs, job_id, fn {j, _, _} -> {j, {j, now_millis, :running}} end)

    {{locked_job_key, job}, %__MODULE__{q | jobs: jobs2, index_running: index_running2}}
  end

  defp remove_locked(
         %__MODULE__{jobs: jobs, index_running: index_running} = q,
         {_, job_id} = job_key,
         now_millis
       ) do
    if :gb_sets.is_member(job_key, index_running) do
      {{j, _, :running}, jobs2} = Map.pop(jobs, job_id)

      %__MODULE__{q | jobs: jobs2, index_running: :gb_sets.delete(job_key, index_running)}
      |> requeue_if_recurring(j, job_id, now_millis)
    else
      q
    end
  end

  defp requeue_if_recurring(
         %__MODULE__{jobs: jobs, index_waiting: index_waiting} = q,
         j,
         job_id,
         now_millis
       ) do
    case j.schedule do
      {:once, _} ->
        q

      {:cron, cron} ->
        # reset `remaining_attempts`
        j2 = %AsyncJob{j | remaining_attempts: j.attempts}
        next_time = Cron.next_in_epoch_milliseconds(cron, now_millis)
        jobs2 = Map.put(jobs, job_id, {j2, next_time, :waiting})
        index_waiting2 = :gb_sets.add({next_time, job_id}, index_waiting)
        %__MODULE__{q | jobs: jobs2, index_waiting: index_waiting2}
    end
  end

  defp unlock_for_retry(
         %__MODULE__{jobs: jobs, index_waiting: index_waiting, index_running: index_running} = q,
         {_, job_id} = job_key,
         now_millis
       ) do
    if :gb_sets.is_member(job_key, index_running) do
      {job, _, :running} = Map.fetch!(jobs, job_id)
      next_start = now_millis + AsyncJob.compute_retry_interval(job)
      new_job = %AsyncJob{job | remaining_attempts: job.remaining_attempts - 1}
      index_running2 = :gb_sets.delete(job_key, index_running)
      index_waiting2 = :gb_sets.add({next_start, job_id}, index_waiting)
      jobs2 = Map.put(jobs, job_id, {new_job, next_start, :waiting})
      %__MODULE__{q | jobs: jobs2, index_waiting: index_waiting2, index_running: index_running2}
    else
      q
    end
  end

  defp remove_broker(%__MODULE__{brokers_waiting: brokers} = q, pid) do
    %__MODULE__{q | brokers_waiting: remove_brokers_by_node(brokers, pid)}
  end

  defunp cancel_job(
           %__MODULE__{jobs: jobs} = q :: v[t],
           job_id :: v[Id.t()]
         ) :: {:ok | {:error, :not_found}, t} do
    case Map.pop(jobs, job_id) do
      {nil, _} ->
        {{:error, :not_found}, q}

      {{_, t, state}, new_jobs} ->
        job_key = {t, job_id}
        q2 = cancel_job_impl(state, %__MODULE__{q | jobs: new_jobs}, job_key)
        {:ok, q2}
    end
  end

  defp cancel_job_impl(:waiting, %__MODULE__{index_waiting: index_waiting} = q, job_key) do
    %__MODULE__{q | index_waiting: :gb_sets.delete(job_key, index_waiting)}
  end

  defp cancel_job_impl(:runnable, %__MODULE__{index_runnable: index_runnable} = q, job_key) do
    %__MODULE__{q | index_runnable: :gb_sets.delete(job_key, index_runnable)}
  end

  defp cancel_job_impl(:running, %__MODULE__{index_running: index_running} = q, job_key) do
    %__MODULE__{q | index_running: :gb_sets.delete(job_key, index_running)}
  end

  defp metrics(%__MODULE__{
         index_waiting: index_waiting,
         index_runnable: index_runnable,
         index_running: index_running,
         brokers_waiting: brokers
       }) do
    {
      :gb_sets.size(index_waiting),
      :gb_sets.size(index_runnable),
      :gb_sets.size(index_running),
      length(brokers)
    }
  end

  @impl true
  defun query(q :: v[t], arg :: RVData.query_arg()) :: RVData.query_ret() do
    case arg do
      {:status, job_id} -> get_status(q, job_id)
      :list -> list_jobs(q)
      # failsafe and for testing
      _ -> q
    end
  end

  defp get_status(%__MODULE__{jobs: jobs}, job_id) do
    case jobs[job_id] do
      nil -> {:error, :not_found}
      triplet -> {:ok, triplet}
    end
  end

  defp list_jobs(%__MODULE__{
         index_waiting: waiting,
         index_runnable: runnable,
         index_running: running
       }) do
    {running, runnable, waiting}
  end

  defmodule Hook do
    alias Antikythera.ContextId
    alias AntikytheraCore.AsyncJob.Queue
    alias AntikytheraCore.GearLog.Writer
    alias AntikytheraCore.GearModule
    require AntikytheraCore.Logger, as: L

    @behaviour RaftedValue.LeaderHook

    @impl true
    def on_command_committed(_, _, _, %Queue{
          brokers_to_notify: bs,
          abandoned_jobs: abandoned_jobs
        }) do
      Enum.each(bs, &Broker.notify_job_registered/1)
      Enum.each(abandoned_jobs, &log_abandoned_job/1)
    end

    @impl true
    def on_query_answered(_, _, _), do: nil
    @impl true
    def on_follower_added(_, _), do: nil
    @impl true
    def on_follower_removed(_, _), do: nil
    @impl true
    def on_elected(_), do: nil
    @impl true
    def on_restored_from_files(_), do: nil

    defp log_abandoned_job({id, %AsyncJob{gear_name: gear_name}}) do
      message_common = "abandoned a job that has been running too long: id=#{id}"
      L.error("#{message_common} gear_name=#{gear_name}")
      logger = GearModule.logger(gear_name)

      Writer.error(
        logger,
        GearLog.Time.now(),
        ContextId.system_context(),
        "<async_job> #{message_common}"
      )
    end
  end

  #
  # Public API
  #
  @default_rv_config_options Keyword.put(
                               RaftedValueConfigMaker.options(),
                               :leader_hook_module,
                               Hook
                             )

  defun make_rv_config(opts :: Keyword.t() \\ @default_rv_config_options) ::
          RaftedValue.Config.t() do
    # :leader_hook_module must not be modified
    opts = Keyword.put(opts, :leader_hook_module, Hook)
    RaftedValue.make_config(__MODULE__, opts)
  end

  defun add_job(
          queue_name :: v[atom],
          job_id :: v[Id.t()],
          job :: v[AsyncJob.t()],
          start_time_millis :: v[pos_integer],
          now_millis :: v[pos_integer]
        ) :: :ok | {:error, :full | :existing_id | {:rate_limit_reached, pos_integer}} do
    run_command_with_rate_limit_check!(
      queue_name,
      {:add, {start_time_millis, job_id}, job},
      now_millis
    )
  end

  defun cancel(queue_name :: v[atom], job_id :: v[Id.t()]) ::
          :ok | {:error, :not_found | {:rate_limit_reached, pos_integer}} do
    run_command_with_rate_limit_check!(
      queue_name,
      {:cancel, job_id},
      System.system_time(:millisecond)
    )
  end

  defp run_command_with_rate_limit_check!(queue_name, cmd, now_millis) do
    case RateLimit.check_for_command(queue_name) do
      :ok -> run_command!(queue_name, cmd, now_millis)
      {:error, millis_to_wait} -> {:error, {:rate_limit_reached, millis_to_wait}}
    end
  end

  defun fetch_job(queue_name :: v[atom]) :: nil | {JobKey.t(), AsyncJob.t()} do
    run_command!(queue_name, {:fetch, self()})
  end

  defun remove_locked_job(queue_name :: v[atom], job_key :: v[JobKey.t()]) :: :ok do
    :ok = run_command!(queue_name, {:remove_locked, job_key})
  end

  defun unlock_job_for_retry(queue_name :: v[atom], job_key :: v[JobKey.t()]) :: :ok do
    :ok = run_command!(queue_name, {:unlock_for_retry, job_key})
  end

  defun remove_broker_from_waiting_list(queue_name :: v[atom]) :: :ok do
    case run_command(queue_name, {:remove_broker_from_waiting_list, self()}) do
      {:ok, :ok} -> :ok
      # We don't care if this operation succeeds or not, as this node is being terminated anyway.
      {:error, :no_leader} -> :ok
    end
  end

  defp run_command!(queue_name, cmd, now_millis \\ System.system_time(:millisecond)) do
    run_command(queue_name, cmd, now_millis) |> R.get!()
  end

  defp run_command(queue_name, cmd, now_millis \\ System.system_time(:millisecond)) do
    RaftFleet.command(queue_name, {cmd, now_millis})
  end

  defun start_jobs_and_get_metrics(pid :: v[pid]) :: nil | tuple do
    # Note that:
    # - we call `RaftedValue.command` instead of `RaftFleet.command` in order not to send message to remote node
    # - we use command instead of query so that it can trigger some of the stored jobs
    now_millis = System.system_time(:millisecond)

    case RaftedValue.command(pid, {:get_metrics, now_millis}) do
      {:ok, metrics_data} -> metrics_data
      {:error, _} -> nil
    end
  end

  defun status(queue_name :: v[atom], job_id :: v[Id.t()]) :: R.t(Status.t()) do
    {:ok, result} =
      RateLimit.check_with_retry_for_query(queue_name, fn ->
        RaftFleet.query(queue_name, {:status, job_id})
      end)

    R.map(result, fn {job, start_time_millis, state} ->
      job_to_status(job, job_id, start_time_millis, state)
    end)
  end

  defp job_to_status(
         %AsyncJob{
           gear_name: gear_name,
           module: module,
           payload: payload,
           schedule: schedule,
           max_duration: max_duration,
           attempts: attempts,
           remaining_attempts: remaining_attempts,
           retry_interval: retry_interval
         },
         job_id,
         start_time_millis,
         state
       ) do
    %Status{
      id: job_id,
      start_time: Time.from_epoch_milliseconds(start_time_millis),
      state: state,
      gear_name: gear_name,
      module: module,
      payload: if(is_binary(payload), do: :erlang.binary_to_term(payload), else: payload),
      schedule: schedule,
      max_duration: max_duration,
      attempts: attempts,
      remaining_attempts: remaining_attempts,
      retry_interval: retry_interval
    }
  end

  defun list(queue_name :: v[atom]) :: [{Time.t(), Id.t(), StateLabel.t()}] do
    # data conversions should be done at caller side (raft leader should not do CPU-intensive works)
    {:ok, {running, runnable, waiting}} =
      RateLimit.check_with_retry_for_query(queue_name, fn ->
        RaftFleet.query(queue_name, :list)
      end)

    [
      {:gb_sets.to_list(running), :running},
      {:gb_sets.to_list(runnable), :runnable},
      {:gb_sets.to_list(waiting), :waiting}
    ]
    |> Enum.flat_map(fn {list, state} ->
      Enum.map(list, fn {millis, id} -> {Time.from_epoch_milliseconds(millis), id, state} end)
    end)
  end
end
