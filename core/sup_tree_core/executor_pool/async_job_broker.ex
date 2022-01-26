# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.AsyncJobBroker do
  @moduledoc """
  A broker that finds a pair of "a runnable job in job queue" and "an available `AsyncJobRunner` process in worker pool".

  This `GenServer` becomes `:active` when both antikythera and the job queue for the same executor pool are ready.
  When entering `:active` phase it notifies `AntikytheraCore.TerminationManager` of the pid
  so that it will be notified afterward.
  Before host termination it becomes `:inactive` on receipt of a message from `AntikytheraCore.TerminationManager`;
  from then on it won't start new jobs.

  During `:active` phase it checks out a process from the async job worker pool of the same executor pool,
  fetches a job from the job queue, and tells the process to run the job.

  Communications between broker and job queue are basically event-driven,
  i.e., no polling mechanism is needed for them to work, most of the time.
  However, in rare occasions, messages between them may be lost
  due to e.g. failure of majority members in the job queue's consensus group.
  Therefore we also use periodic polling to recover from this kind of troubles.
  """

  use GenServer
  alias AntikytheraCore.{StartupManager, TerminationManager}
  alias AntikytheraCore.ExecutorPool.AsyncJobRunner
  alias AntikytheraCore.AsyncJob.Queue
  require AntikytheraCore.Logger, as: L

  @readiness_check_interval_during_startup 500
  @job_queue_polling_interval 10 * 60_000

  defmodule Phase do
    use Croma.SubtypeOfAtom, values: [:startup, :active, :inactive]
  end

  defmodule State do
    use Croma.Struct,
      recursive_new?: true,
      fields: [
        phase: Phase,
        pool_name: Croma.Atom,
        queue_name: Croma.Atom
      ]
  end

  def start_link([pool_name, queue_name, broker_name]) do
    GenServer.start_link(__MODULE__, {pool_name, queue_name}, name: broker_name)
  end

  @impl true
  def init({pool_name, queue_name}) do
    make_readiness_check_timer(0)
    {:ok, %State{phase: :startup, pool_name: pool_name, queue_name: queue_name}}
  end

  @impl true
  def handle_cast(:deactivate, %State{queue_name: queue_name} = state) do
    Queue.remove_broker_from_waiting_list(queue_name)
    %State{state | phase: :inactive} |> noreply()
  end

  def handle_cast(:job_registered, state) do
    noreply_try_run_jobs_if_active(state)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    noreply_try_run_jobs_if_active(state)
  end

  def handle_info(:polling_timeout, state) do
    make_job_polling_timer()
    noreply_try_run_jobs_if_active(state)
  end

  def handle_info(:readiness_check_timeout, %State{phase: phase} = state) do
    if phase == :startup do
      become_active_if_ready(state)
    else
      state
    end
    |> noreply()
  end

  def handle_info(_, state) do
    # neglect other message (possibly a delayed reply from the queue)
    noreply(state)
  end

  defp noreply(state) do
    {:noreply, state}
  end

  #
  # Initialization-related functions
  #
  defp make_readiness_check_timer(millis \\ @readiness_check_interval_during_startup) do
    Process.send_after(self(), :readiness_check_timeout, millis)
  end

  defp become_active_if_ready(state) do
    if StartupManager.initialized?() and ensure_queue_added(state) do
      case TerminationManager.register_broker() do
        :ok -> become_active(state)
        # in this case go directly to `:inactive` phase
        {:error, :not_in_service} -> %State{state | phase: :inactive}
      end
    else
      # retry at the next time
      make_readiness_check_timer()
      state
    end
  end

  defp ensure_queue_added(%{queue_name: queue_name}) do
    try do
      groups = RaftFleet.consensus_groups()

      if Map.has_key?(groups, queue_name) do
        true
      else
        add_consensus_group(queue_name)
      end
    rescue
      # If `RaftFleet.consensus_groups/1` times-out (due to recovery from large snapshot/logs),
      # the caller should retry afterward in the hope that the consensus group will become ready.
      e ->
        L.error("failed to get consensus groups #{queue_name}: #{inspect(e)}")
        false
    end
  end

  defp add_consensus_group(queue_name) do
    # Note that the consensus group may already be started by some other node, resulting in `:already_added`.
    # If `RaftFleet.add_consensus_group/1` times-out (due to recovery from large snapshot/logs),
    # the caller should retry afterward in the hope that the consensus group will become ready.
    case RaftFleet.add_consensus_group(queue_name) do
      :ok ->
        true

      {:error, :already_added} ->
        true

      {:error, reason} ->
        L.error("failed to add consensus group #{queue_name}: #{inspect(reason)}")
        false
    end
  end

  # We have encountered several times (so far only in dev envoronment) an issue
  # where many newly-started AsyncJobBroker processes crashed due to timeout in `PoolSup.checkout_nonblocking/1`.
  # Although the issue is automatically resolved by supervisor restarts,
  # we try to prevent it by introducing random delay on startup of AsyncJobBroker processes.
  @base_wait_time_before_accepting_jobs if Antikythera.Env.compiling_for_cloud?(),
                                          do: 5_000,
                                          else: 0
  @random_wait_time_max_before_accepting_jobs if Antikythera.Env.compiling_for_cloud?(),
                                                do: 60_000,
                                                else: 1

  defp become_active(state1) do
    wait_time =
      @base_wait_time_before_accepting_jobs +
        :rand.uniform(@random_wait_time_max_before_accepting_jobs)

    make_job_polling_timer(wait_time)
    %State{state1 | phase: :active}
  end

  #
  # Functions for matchmaking jobs and workers during `:active` phase
  #
  defp make_job_polling_timer(millis \\ @job_queue_polling_interval) do
    Process.send_after(self(), :polling_timeout, millis)
  end

  defp noreply_try_run_jobs_if_active(%State{phase: phase} = state) do
    if phase == :active do
      try_run_jobs(state)
    end

    noreply(state)
  end

  defp try_run_jobs(state) do
    case try_run_a_job(state) do
      :ok -> try_run_jobs(state)
      _no_worker_or_no_job -> :ok
    end
  end

  defp try_run_a_job(%State{pool_name: pool_name, queue_name: queue_name}) do
    case PoolSup.checkout_nonblocking(pool_name) do
      nil ->
        :no_worker

      pid ->
        case Queue.fetch_job(queue_name) do
          nil ->
            PoolSup.checkin(pool_name, pid)
            :no_job

          {job_key, job} ->
            Process.monitor(pid)
            # in this case the worker checks-in itself
            AsyncJobRunner.run(pid, queue_name, job_key, job)
            :ok
        end
    end
  end

  #
  # Public API
  #
  defun notify_job_registered(pid :: v[pid]) :: :ok do
    GenServer.cast(pid, :job_registered)
  end

  defun notify_pool_capacity_may_have_changed(name :: v[atom]) :: :ok do
    # what to do on capacity change is exactly the same as `notify_job_registered`; reuse the same message
    GenServer.cast(name, :job_registered)
  end

  defun deactivate(pid :: v[pid]) :: :ok do
    GenServer.cast(pid, :deactivate)
  end
end
