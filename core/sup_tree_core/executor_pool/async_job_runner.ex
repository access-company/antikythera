# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.AsyncJobRunner do
  @moduledoc """
  An ephemeral `GenServer` process under `PoolSup` that manages an execution of an async job.

  Actual execution of gear's code is done within a separate process for the following reasons:
  - for cleaner error handling
  - to introduce timeout of job execution
  - to be responsive to system messages

  When the separate process terminates, this `GenServer` updates/deletes the locked job in the queue
  depending on the result of the execution.

  Note that when no job is registered in the job queue, successfully checked-out process is immediately checked in.
  See implementation of `AntikytheraCore.ExecutorPool.AsyncJobBroker`.
  """

  use GenServer
  alias Antikythera.{Time, Context, ErrorReason}
  alias Antikythera.AsyncJob.Metadata
  alias AntikytheraCore.GearTask
  alias AntikytheraCore.{GearModule, GearProcess, MetricsUploader}
  alias AntikytheraCore.AsyncJob
  alias AntikytheraCore.AsyncJob.Queue
  alias AntikytheraCore.AsyncJob.Queue.JobKey
  alias AntikytheraCore.Context, as: CoreContext
  alias AntikytheraCore.GearLog.{Writer, ContextHelper}
  alias AntikytheraCore.ExecutorPool.AsyncJobLog.Writer, as: JobLogWriter
  require AntikytheraCore.Logger, as: L

  @idle_timeout 60_000

  @abandon_callback_max_duration 10_000
  # for documentation
  def abandon_callback_max_duration(), do: @abandon_callback_max_duration

  def start_link(epool_id) do
    GenServer.start_link(__MODULE__, epool_id)
  end

  @impl true
  def init(epool_id) do
    {:ok, %{executor_pool_id: epool_id}, @idle_timeout}
  end

  @impl true
  def handle_cast({:run, queue_name, {run_at_ms, job_id} = job_key, job}, %{
        executor_pool_id: epool_id
      }) do
    run_at = Time.from_epoch_milliseconds(run_at_ms)
    metadata = make_metadata(job, job_id, run_at)
    context = %Context{start_time: context_start_time} = make_context(job, epool_id)
    logger_name = GearModule.logger(job.gear_name)
    decoded_payload = decode_payload(job.payload)
    log_prefix = log_prefix(job, job_id, run_at, decoded_payload)
    write_start_log(context, logger_name, log_prefix)
    {pid, monitor_ref, timer_ref} = start_monitor(job, metadata, context, decoded_payload)

    new_state = %{
      epool_id: epool_id,
      # can be `nil` if the job is executed with `:bypass_job_queue` option
      queue_name: queue_name,
      worker: pid,
      monitor: monitor_ref,
      timer: timer_ref,
      job_key: job_key,
      job: job,
      metadata: metadata,
      context: context,
      logger_name: logger_name,
      log_prefix: log_prefix,
      start_time: context_start_time
    }

    {:noreply, new_state}
  end

  defp make_context(%AsyncJob{gear_name: gear_name, module: module}, epool_id) do
    now = Time.now()

    %Context{
      start_time: now,
      context_id: CoreContext.make_context_id(now),
      gear_name: gear_name,
      executor_pool_id: epool_id,
      gear_entry_point: {module, :run}
    }
  end

  defp make_metadata(
         %AsyncJob{
           max_duration: max_duration,
           attempts: attempts,
           remaining_attempts: remaining_attempts,
           retry_interval: retry_interval
         },
         job_id,
         run_at
       ) do
    %Metadata{
      id: job_id,
      run_at: run_at,
      max_duration: max_duration,
      attempts: attempts,
      remaining_attempts: remaining_attempts,
      retry_interval: retry_interval
    }
  end

  defp log_prefix(
         %AsyncJob{module: module, attempts: attempts, remaining_attempts: remaining},
         job_id,
         run_at,
         decoded_payload
       ) do
    mod_str = Atom.to_string(module) |> String.replace_leading("Elixir.", "")
    run_at_str = Time.to_iso_timestamp(run_at)

    prefix =
      "<async_job> module=#{mod_str} job_id=#{job_id} attempt=#{attempts - remaining + 1}th/#{attempts} run_at=#{run_at_str} "

    try do
      module.inspect_payload(decoded_payload)
    rescue
      # `inspect_payload/1` has bug or `module` has already been removed/renamed.
      _ -> ""
    end
    |> case do
      "" -> prefix
      payload_str -> prefix <> "payload=#{payload_str} "
    end
  end

  defp write_start_log(
         %Context{start_time: context_start_time, context_id: context_id},
         logger_name,
         log_prefix
       ) do
    Writer.info(logger_name, context_start_time, context_id, log_prefix <> "START")
    JobLogWriter.info("context=" <> context_id <> " " <> log_prefix <> "START")
  end

  defp start_monitor(
         %AsyncJob{module: module, max_duration: max_duration},
         metadata,
         context,
         decoded_payload
       ) do
    {pid, monitor_ref} =
      GearProcess.spawn_monitor(__MODULE__, :do_run, [module, decoded_payload, metadata, context])

    timer_ref = Process.send_after(self(), :running_too_long, max_duration)
    {pid, monitor_ref, timer_ref}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, _pid, reason}, %{timer: timer_ref} = state) do
    Process.cancel_timer(timer_ref)

    case reason do
      :normal ->
        job_succeeded(state)

      {:shutdown, {reason2, stacktrace}} ->
        job_failed(state, reason2, stacktrace)

      :killed ->
        %{gear_name: gear_name, context_id: context_id} = state.context
        L.error("Process killed: gear_name=#{gear_name}, context_id=#{context_id}")
        job_failed(state, :killed, [])
    end

    {:stop, :normal, state}
  end

  def handle_info(:running_too_long, %{monitor: monitor_ref} = state) do
    Process.demonitor(monitor_ref)
    Process.exit(state[:worker], :kill)
    job_failed(state, :timeout, [])
    {:stop, :normal, state}
  end

  def handle_info(:timeout, %{executor_pool_id: epool_id} = state) do
    # `@idle_timeout` elapsed after `init/1` with no incoming message => probably the broker has somehow died.
    # Stop this process to prevent from process leak.
    JobLogWriter.info(
      "epool_id=#{inspect(epool_id)} #{@idle_timeout}ms elapsed after `init/1` with no incoming message"
    )

    {:stop, :normal, state}
  end

  defp job_succeeded(%{queue_name: queue_name, job_key: job_key} = state) do
    report_on_finish(state, Time.now(), "success")
    if queue_name, do: Queue.remove_locked_job(queue_name, job_key)
  end

  defp job_failed(
         %{
           queue_name: queue_name,
           job_key: job_key,
           job: %AsyncJob{remaining_attempts: remaining_attempts}
         } = state,
         reason,
         stacktrace
       ) do
    end_time = Time.now()
    write_failed_log(state, end_time, ErrorReason.format(reason, stacktrace))

    case remaining_attempts do
      1 ->
        report_on_finish(state, end_time, "failure_abandon")
        if queue_name, do: Queue.remove_locked_job(queue_name, job_key)
        execute_abandon_callback(state)

      _ ->
        report_on_finish(state, end_time, "failure_retry")
        if queue_name, do: Queue.unlock_job_for_retry(queue_name, job_key)
    end
  end

  defp write_failed_log(
         %{
           context: %Context{context_id: context_id},
           logger_name: logger_name,
           log_prefix: log_prefix
         },
         end_time,
         error_reason
       ) do
    Writer.error(logger_name, end_time, context_id, log_prefix <> error_reason)
    JobLogWriter.info("context=" <> context_id <> " " <> log_prefix <> "FAILED")
  end

  defp report_on_finish(
         %{
           context: %Context{context_id: context_id},
           logger_name: logger_name,
           log_prefix: log_prefix,
           start_time: start_time
         } = state,
         end_time,
         job_result
       ) do
    diff = Time.diff_milliseconds(end_time, start_time)

    Writer.info(
      logger_name,
      end_time,
      context_id,
      log_prefix <> "END status=#{job_result} time=#{diff}ms"
    )

    JobLogWriter.info(
      "context=" <> context_id <> " " <> log_prefix <> "END status=#{job_result} time=#{diff}ms"
    )

    submit_metrics(state, end_time, diff, job_result)
  end

  defp submit_metrics(
         %{epool_id: epool_id, job: %AsyncJob{gear_name: gear_name}},
         now,
         diff,
         job_result
       ) do
    uploader_name = GearModule.metrics_uploader(gear_name)

    metrics_data_list = [
      {"async_job_#{job_result}", :sum, 1},
      {"async_job_execution_time_ms", :time_distribution, diff}
    ]

    MetricsUploader.submit_with_time(uploader_name, now, metrics_data_list, epool_id)
  end

  defp execute_abandon_callback(%{
         job: %AsyncJob{module: module, payload: payload},
         metadata: metadata,
         context: %Context{context_id: context_id} = context,
         logger_name: logger_name,
         log_prefix: log_prefix
       }) do
    # Since timeout is not too long, we simply use `GearTask`.
    GearTask.exec_wait(
      {__MODULE__, :do_abandon, [module, payload, metadata, context]},
      @abandon_callback_max_duration,
      fn _ -> :ok end,
      fn reason, stacktrace ->
        Writer.error(
          logger_name,
          Time.now(),
          context_id,
          log_prefix <> "error during abandon/3: #{ErrorReason.format(reason, stacktrace)}"
        )
      end
    )
  end

  defp decode_payload(payload) when is_binary(payload), do: :erlang.binary_to_term(payload)
  defp decode_payload(payload), do: payload

  #
  # Public functions to run within a separate process
  #
  defun do_run(
          module :: v[module],
          payload :: v[map],
          metadata :: v[Metadata.t()],
          context :: v[Context.t()]
        ) :: any do
    ContextHelper.set(context)

    try do
      module.run(payload, metadata, context)
      # if no error occurs the process exits with `:normal`
    catch
      :error, error -> exit({:shutdown, {{:error, error}, __STACKTRACE__}})
      :throw, value -> exit({:shutdown, {{:throw, value}, __STACKTRACE__}})
      :exit, reason -> exit({:shutdown, {{:exit, reason}, __STACKTRACE__}})
    end
  end

  defun do_abandon(
          module :: v[module],
          payload :: v[map | binary],
          metadata :: v[Metadata.t()],
          context :: v[Context.t()]
        ) :: any do
    ContextHelper.set(context)
    module.abandon(decode_payload(payload), metadata, context)
  end

  #
  # Public API
  #
  defun run(
          pid :: v[pid],
          queue_name :: v[atom | nil],
          job_key :: v[JobKey.t()],
          job :: v[AsyncJob.t()]
        ) :: :ok do
    GenServer.cast(pid, {:run, queue_name, job_key, job})
  end
end
