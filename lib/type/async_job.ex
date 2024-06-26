# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.AsyncJob.Id do
  use Croma.SubtypeOfString, pattern: ~R/\A[0-9A-Za-z_-]{1,32}\z/

  defun generate() :: t do
    Enum.map(1..20, fn _ -> gen_base64url_char() end) |> List.to_string()
  end

  defunp gen_base64url_char() :: char do
    case :rand.uniform(64) do
      # 0-9
      i when i <= 10 -> i + 47
      # A-Z
      i when i <= 36 -> i + 54
      # a-z
      i when i <= 62 -> i + 60
      # -
      63 -> 45
      # _
      64 -> 95
    end
  end
end

defmodule Antikythera.AsyncJob.Schedule do
  alias Antikythera.{Time, Cron}

  @type t :: {:once, Time.t()} | {:cron, Cron.t()}

  defun valid?(t :: term) :: boolean do
    {:once, t} -> Time.valid?(t)
    {:cron, c} -> Cron.valid?(c)
    _otherwise -> false
  end
end

defmodule Antikythera.AsyncJob.Attempts do
  use Croma.SubtypeOfInt, min: 1, max: 10, default: 3
end

defmodule Antikythera.AsyncJob.MaxDuration do
  use Croma.SubtypeOfInt, min: 1, max: 30 * 60_000, default: 5 * 60_000
end

defmodule Antikythera.AsyncJob.RetryInterval do
  defmodule Factor do
    use Croma.SubtypeOfInt, min: 0, max: 5 * 60_000, default: 5_000
  end

  defmodule Base do
    use Croma.SubtypeOfFloat, min: 1.0, max: 5.0, default: 2.0
  end

  use Croma.SubtypeOfTuple,
    elem_modules: [Factor, Base],
    default: {Factor.default(), Base.default()}

  defun interval(t :: v[t], n_retries_done_so_far :: v[non_neg_integer]) :: non_neg_integer do
    {factor, base} = t
    factor * round(:math.pow(base, n_retries_done_so_far))
  end
end

defmodule Antikythera.AsyncJob.Metadata do
  alias Antikythera.Time
  alias Antikythera.AsyncJob.{Id, Attempts, MaxDuration, RetryInterval}

  use Croma.Struct,
    fields: [
      id: Id,
      run_at: Time,
      max_duration: MaxDuration,
      attempts: Attempts,
      remaining_attempts: Attempts,
      retry_interval: RetryInterval
    ]
end

defmodule Antikythera.AsyncJob.StateLabel do
  use Croma.SubtypeOfAtom, values: [:waiting, :runnable, :running]
end

defmodule Antikythera.AsyncJob.Status do
  alias Antikythera.{Time, GearName}
  alias Antikythera.AsyncJob.{Id, Schedule, Attempts, MaxDuration, RetryInterval, StateLabel}

  use Croma.Struct,
    fields: [
      id: Id,
      gear_name: GearName,
      module: Croma.Atom,
      payload: Croma.Map,
      schedule: Schedule,
      start_time: Time,
      state: StateLabel,
      max_duration: MaxDuration,
      attempts: Attempts,
      remaining_attempts: Attempts,
      retry_interval: RetryInterval
    ]
end
