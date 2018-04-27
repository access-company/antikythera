# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.AsyncJob do
  alias Croma.Result, as: R
  alias Antikythera.{Time, Cron, GearName, Context, MilliSecondsSinceEpoch}
  alias Antikythera.AsyncJob.{Id, Schedule, MaxDuration, Attempts, RetryInterval}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.ExecutorPool.Id, as: CoreEPoolId
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.AsyncJob.Queue

  @max_start_time_from_now 50 * 24 * 60 * 60_000
  def max_start_time_from_now(), do: @max_start_time_from_now # just for documentation

  use Croma.Struct, recursive_new?: true, fields: [
    gear_name:          GearName,
    module:             Croma.Atom,
    schedule:           Schedule,
    max_duration:       MaxDuration,
    attempts:           Attempts,
    remaining_attempts: Attempts,
    retry_interval:     RetryInterval,
    payload:            Croma.Map, # opaque data given and used by gear
  ]

  @typep option :: Antikythera.AsyncJob.option

  defun register(gear_name           :: v[GearName.t],
                 module              :: v[module],
                 payload             :: v[map],
                 context_or_epool_id :: v[EPoolId.t | Context.t],
                 options             :: v[[option]]) :: R.t(Id.t) do
    now_millis = System.system_time(:milliseconds)
    R.m do
      epool_id                      <- find_executor_pool(gear_name, context_or_epool_id)
      job_id                        <- extract_job_id(options)
      {schedule, start_time_millis} <- validate_schedule(now_millis, options)
      job                           <- make_job(gear_name, module, payload, schedule, options)
      do_register(epool_id, job_id, job, start_time_millis, now_millis)
    end
  end

  defunp find_executor_pool(gear_name :: v[GearName.t], context_or_epool_id :: v[EPoolId.t | Context.t]) :: R.t(EPoolId.t) do
    case context_or_epool_id do
      %Context{executor_pool_id: id} -> {:ok, id}
      epool_id                       -> CoreEPoolId.validate_association(epool_id, gear_name)
    end
  end

  defunp extract_job_id(options :: v[[option]]) :: R.t(Id.t) do
    case options[:id] do
      nil -> {:ok, Id.generate()}
      id  -> R.wrap_if_valid(id, Id)
    end
  end

  defunp validate_schedule(now_millis :: v[MilliSecondsSinceEpoch.t], options :: v[[option]]) :: R.t({Schedule.t, MilliSecondsSinceEpoch.t}) do
    case options[:schedule] do
      nil        -> {:ok, {{:once, Time.from_epoch_milliseconds(now_millis)}, now_millis}}
      {:once, t} -> validate_schedule_once(t, now_millis)
      {:cron, c} -> {:ok, {{:cron, c}, Cron.next_in_epoch_milliseconds(c, now_millis)}}
      _otherwise -> {:error, {:invalid_value, :schedule}}
    end
  end

  defunp validate_schedule_once(time :: v[Time.t], now_millis :: v[MilliSecondsSinceEpoch.t]) :: R.t({Schedule.t, MilliSecondsSinceEpoch.t}) do
    time_millis = Time.to_epoch_milliseconds(time)
    diff = time_millis - now_millis
    if 0 <= diff and diff <= @max_start_time_from_now do
      {:ok, {{:once, time}, time_millis}}
    else
      {:error, {:invalid_value, :schedule}}
    end
  end

  defunpt make_job(gear_name :: v[GearName.t],
                   module    :: v[module],
                   payload   :: v[map],
                   schedule  :: v[Schedule.t],
                   options   :: v[[option]]) :: R.t(t) do
    attempts = Keyword.get(options, :attempts, Attempts.default())
    new([
      gear_name:          gear_name,
      module:             module,
      schedule:           schedule,
      max_duration:       Keyword.get(options, :max_duration, MaxDuration.default()),
      attempts:           attempts,
      remaining_attempts: attempts,
      retry_interval:     Keyword.get(options, :retry_interval, RetryInterval.default()),
      payload:            payload,
    ])
  end

  defunp do_register(epool_id          :: v[EPoolId.t],
                     job_id            :: v[Id.t],
                     job               :: v[t],
                     start_time_millis :: v[MilliSecondsSinceEpoch.t],
                     now_millis        :: v[MilliSecondsSinceEpoch.t]) :: R.t(Id.t) do
    queue_name = RegName.async_job_queue(epool_id)
    case Queue.add_job(queue_name, job_id, job, start_time_millis, now_millis) do
      :ok   -> {:ok, job_id}
      error -> error
    end
  end

  defun compute_retry_interval(%__MODULE__{retry_interval: retry_interval, attempts: attempts, remaining_attempts: remaining_attempts}) :: non_neg_integer do
    RetryInterval.interval(retry_interval, attempts - remaining_attempts)
  end
end
