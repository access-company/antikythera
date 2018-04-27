# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.AsyncJob do
  alias Croma.Result, as: R
  alias Antikythera.{Time, Context, GearName}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias Antikythera.AsyncJob.{Id, Schedule, MaxDuration, Attempts, RetryInterval, Metadata, Status, StateLabel}
  alias AntikytheraCore.AsyncJob.Queue
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.ExecutorPool.Id, as: CoreEPoolId

  @abandon_callback_max_duration 10_000
  def abandon_callback_max_duration(), do: @abandon_callback_max_duration

  @moduledoc """
  Antikythera's "async job" functionality allows gears to run their code in background.

  This module is the interface for gear implementations to define and register their own async jobs.

  ## Usage

  ### Preparing your async job module

  Each gear can define multiple async job modules.
  Those modules must `use` this module as in the following example:

      defmodule YourGear.SomeAsyncJob do
        use Antikythera.AsyncJob

        # run/3 is required
        def run(_payload, _metadata, _context) do
          # do something here
        end

        # abandon/3 callback is optional; you can omit it
        def abandon(_payload, _metadata, _context) do
          # cleanup code when all retries failed
        end

        # inspect_payload/1 is optional; you can omit it
        def inspect_payload(payload) do
          # convert a payload to a short string that can be used to identify a job in logs
        end
      end

  Implementations of `run/3` can return any value; it is simply ignored.
  If execution of `run/3` terminated abnormally (exception, timeout, etc.) the job is regarded as failed.
  Failed jobs are automatically retried up to a specified number of attempts (see below).

  `abandon/3` optional callback is called when a job is abandoned after all attempts failed.
  You can put your cleanup logic in this callback when e.g. you use external storage system to store job information.
  Note that `abandon/3` must finish within `#{div(@abandon_callback_max_duration, 1_000)}` seconds;
  when it takes longer, antikythera stops the execution of `abandon/3` in the middle.

  `inspect_payload/1` optional callback is solely for logging purpose.
  By providing concrete implementation you can additionally include summary of each jobs's payload into logs.
  As an example, suppose your `payload` contains "id" field; then it's natural to define the following `inspect_payload/1`:

      def inspect_payload(%{"id" => id}) do
        id
      end

  Your gear can have multiple modules that `use Antikythera.AsyncJob`.

  ### Registering jobs

  With the above module defined, you can call `register/3` to invoke a new job:

      YourGear.SomeAsyncJob.register(%{"arbitrary" => "map"}, context, options)

  Here first argument is an arbitrary map that is passed to `run/3` callback implementation.
  (note that structs are maps and thus usable as payloads).
  `context` is a value of `Antikythera.Context.t/0` and is used to obtain to which executor pool to register the job.
  When you need to register a job to an executor pool that is not the current one,
  you can pass a `Antikythera.ExecutorPool.Id.t/0` instead of `Antikythera.Context.t/0`.
  `options` must be a `Keyword.t/0` which can include the following values:

  - `id`: An ID of the job.
    If given it must match the regex pattern `~r/#{Id.pattern().source}/` and must be unique in the job queue specified by the second argument.
    If not given antikythera automatically generates one for you.
  - `schedule`: When to run the job as a 2-tuple.
    If not given it defaults to `{:once, Antikythera.Time.now()}`, i.e.,
    the job will be executed as soon as an available worker process is found in the specified executor pool.
    Allowed value format is:
      - `{:once, Antikythera.Time.t}`
          - The job is executed at the given time.
            After the job is either successfully completed or abandoned by failure(s), the job is removed from the job queue.
            The time must be a future time and within #{div(AntikytheraCore.AsyncJob.max_start_time_from_now(), 24 * 60 * 60_000)} days from now.
      - `{:cron, Antikythera.Cron.t}`
          - The job is repeatedly executed at the given cron schedule.
            After the job is either successfully completed or abandoned by failure(s), the job is requeued to the job queue.
            Note that next start time is computed from the time of requeuing.
            For example, if a job is scheduled on every 10 minutes ("*/10 * * * *") and its execution takes 15 minutes to complete,
            then the job will in effect run on every 20 minutes.
            The schedule will repeat indefinitely; when you have done with the job you can remove it by `cancel/3`.
  - `max_duration`: Maximum execution time (in milliseconds) of the job.
    A job which has been running for more than `max_duration` is brutally killed and if it has remaining attempts it will be retried.
    Defaults to `#{MaxDuration.default()}` (`#{div(MaxDuration.default(), 60_000)}` minutes).
    If explicitly given it cannot exceed `#{MaxDuration.max()}` (`#{div(MaxDuration.max(), 60_000)}` minutes).
  - `attempts`: A positive integer within `#{Attempts.min()}..#{Attempts.max()}`), up to which antikythera tries to run the job.
    Defaults to `#{Attempts.default()}`.
  - `retry_interval`: A 2-tuple of integer and float to calculate time interval between retries.
    Defaults to `#{inspect(RetryInterval.default())}`.
    First element is a time interval (in milliseconds) between 1st and 2nd attempts
    and must be within `#{RetryInterval.Factor.min()}..#{RetryInterval.Factor.max()}`.
    Second element is a multiplying factor for exponential backoff
    and must be within `#{RetryInterval.Base.min()}..#{RetryInterval.Base.max()}`.
    For example:
      - When `retry_interval: {10_000, 2.0}` is given,
          - 2nd attempt (1st retry) after failure of 1st attempt is started in `10`s,
          - 3rd attempt (2nd retry) after failure of 2nd attempt is started in `20`s,
          - 4th attempt (3rd retry) after failure of 3rd attempt is started in `40`s,
          - and so on.
      - If you want to set constant interval, specify `1.0` to second element.

  `register/3` returns a tuple of `{:ok, Antikythera.AsyncJob.Id.t}` on success.
  You can register jobs up to #{Queue.max_jobs()}.
  When #{Queue.max_jobs()} jobs remain unfinished in the job queue, trying to register a new job results in `{:error, :full}`.

  The example call to `register/3` above will eventually invoke `YourGear.SomeAsyncJob.run/3`
  with the given payload and options.
  """

  @callback run(map, Metadata.t, Context.t) :: any
  @callback abandon(map, Metadata.t, Context.t) :: any
  @callback inspect_payload(map) :: String.t

  @type option :: {:id            , Id.t           }
                | {:schedule      , Schedule.t     }
                | {:max_duration  , MaxDuration.t  }
                | {:attempts      , Attempts.t     }
                | {:retry_interval, RetryInterval.t}

  defmacro __using__(_) do
    gear_name = Mix.Project.config()[:app]
    quote bind_quoted: [gear_name: gear_name] do
      @gear_name gear_name

      @behaviour Antikythera.AsyncJob

      @impl true
      defun abandon(_payload  :: map,
                    _metadata :: Antikythera.AsyncJob.Metadata.t,
                    _context  :: Antikythera.Context.t) :: any do
        :ok
      end

      @impl true
      defun inspect_payload(_payload :: map) :: String.t do
        ""
      end

      defoverridable [abandon: 3, inspect_payload: 1]

      defun register(payload             :: v[map],
                     context_or_epool_id :: v[Antikythera.Context.t | Antikythera.ExecutorPool.Id.t],
                     options             :: v[[Antikythera.AsyncJob.option]] \\ []) :: R.t(Id.t) do
        AntikytheraCore.AsyncJob.register(@gear_name, __MODULE__, payload, context_or_epool_id, options)
      end
    end
  end

  @doc """
  Cancels an async job registered with the job queue specified by `context_or_epool_id`.

  Note that currently-running job executions cannot be cancelled.
  However, calling `cancel/2` with currently running job's `job_id` prevents retries of the job when it fails.
  """
  defun cancel(gear_name           :: v[GearName.t],
               context_or_epool_id :: v[Context.t | EPoolId.t],
               job_id              :: v[Id.t]) :: :ok | {:error, :not_found | CoreEPoolId.reason} do
    epool_id1 = exec_pool_id(context_or_epool_id)
    case CoreEPoolId.validate_association(epool_id1, gear_name) do
      {:ok, epool_id2} -> Queue.cancel(RegName.async_job_queue(epool_id2), job_id)
      error            -> error
    end
  end

  @doc """
  Retrieves detailed information of an async job registered with the job queue specified by `context_or_epool_id`.
  """
  defun status(context_or_epool_id :: v[Context.t | EPoolId.t], job_id :: v[Id.t]) :: R.t(Status.t) do
    Queue.status(queue_name(context_or_epool_id), job_id)
  end

  @doc """
  Retrieves list of async jobs registered with the job queue specified by `context_or_epool_id`.

  Each element of returned list is a 3-tuple: scheduled execution time, job ID and current status.
  The returned list is already sorted.
  """
  defun list(context_or_epool_id :: v[Context.t | EPoolId.t]) :: [{Time.t, Id.t, StateLabel.t}] do
    Queue.list(queue_name(context_or_epool_id))
  end

  defunp exec_pool_id(context_or_epool_id :: v[Context.t | EPoolId.t]) :: EPoolId.t do
    case context_or_epool_id do
      %Context{executor_pool_id: id} -> id
      epool_id                       -> epool_id
    end
  end

  defunp queue_name(context_or_epool_id :: v[Context.t | EPoolId.t]) :: atom do
    exec_pool_id(context_or_epool_id) |> RegName.async_job_queue()
  end
end
