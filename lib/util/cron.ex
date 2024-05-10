# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Cron do
  @moduledoc """
  Calculate time schedules based on cron format strings.

  `parse/1` recognizes the [POSIX specifications of crontab format](http://www.unix.com/man-page/posix/1posix/crontab)
  with the extension of "step values" (explained below).
  The parsed object can be used to compute next matching time in `next/2`.

  Note that all times are in UTC, as is the case with `Antikythera.Time`.

  ## Schedule format

  - The cron schedule is specified by 5 fields separated by whitespaces.
  - Allowed values for each field are:
      - minutes      : 0-59
      - hours        : 0-23
      - day of month : 1-31
      - month        : 1-12
      - day of week  : 0-6 (0=Sunday)
  - Multiple elements can be used within a field by separating each by `,`.
  - An element shall be either a number or two numbers separated by a `-` (meaning an inclusive range).
  - A field may contain `*` which stands for "first-last".
  - Step values as in "/<skip>" can be used in conjunction with ranges.
    For example,
      - "0-18/4" is identical to "0,4,8,12,16", and
      - "*/10" in minutes field is identical to "0,10,20,30,40,50".
  - If both 'day of month' and 'day of week' are not "*", then the dates are the ones matching **either** of the fields.
    For example, "30 4 1,15 * 5" indicates both of the followings:
      - 4:30 on the 1st and 15th of each month
      - 4:30 on every Friday
  - Schedules that actually don't represent valid date are not allowed.
    For example, "0 0 31 4 *" is rejected as 31st of April does not exist.
  """

  alias Croma.Result, as: R
  alias Antikythera.{Time, MilliSecondsSinceEpoch}

  [
    {Minute, 0, 59},
    {Hour, 0, 23},
    {DayOfMonth, 1, 31},
    {Month, 1, 12},
    {DayOfWeek, 0, 6}
  ]
  |> Enum.each(fn {mod, min, max} ->
    m = Module.safe_concat(__MODULE__, mod)

    defmodule m do
      defmodule Int do
        use Croma.SubtypeOfInt, min: min, max: max
      end

      defun min() :: Int.t(), do: Int.min()
      defun max() :: Int.t(), do: Int.max()

      @typedoc "Wildcard `:*` or sorted list of values."
      @type t :: :* | [Int.t()]

      defun valid?(v :: term) :: boolean do
        :* -> true
        l when is_list(l) -> Enum.all?(l, &Int.valid?/1)
      end
    end
  end)

  # defmodule using variable name does not automatically make alias
  alias Antikythera.Cron.{Minute, Hour, DayOfMonth, Month, DayOfWeek}

  use Croma.Struct,
    fields: [
      minute: Minute,
      hour: Hour,
      day_of_month: DayOfMonth,
      month: Month,
      day_of_week: DayOfWeek,
      source: Croma.String
    ]

  defun parse!(s :: v[String.t()]) :: t do
    parse(s) |> R.get!()
  end

  defun parse(s :: v[String.t()]) :: R.t(t) do
    case String.split(s, " ", trim: true) do
      [minute, hour, day_of_month, month, day_of_week] ->
        R.m do
          l1 <- parse_field(minute, Minute)
          l2 <- parse_field(hour, Hour)
          l3 <- parse_field(day_of_month, DayOfMonth)
          l4 <- parse_field(month, Month)
          l5 <- parse_field(day_of_week, DayOfWeek)

          if matching_dates_exist?(l3, l4) do
            {:ok,
             %__MODULE__{
               minute: l1,
               hour: l2,
               day_of_month: l3,
               month: l4,
               day_of_week: l5,
               source: s
             }}
          else
            {:error, {:invalid_value, [__MODULE__]}}
          end
        end

      _ ->
        {:error, {:invalid_value, [__MODULE__]}}
    end
  end

  defp matching_dates_exist?(day_of_month, month) do
    # The following combinations of month/day do not exist: 2/30, 2/31, 4/31, 6/31, 9/31, 11/31
    # Cron patterns that only specify those dates are prohibited in order to prevent infinite loops in `next/2`.
    case {day_of_month, month} do
      {[30 | _], [2]} -> false
      {[31], ms} when is_list(ms) -> !Enum.all?(ms, &(&1 in [2, 4, 6, 9, 11]))
      _ -> true
    end
  end

  defp parse_field(s, mod) do
    case s do
      "*" ->
        {:ok, :*}

      _ ->
        String.split(s, ",")
        |> Enum.map(&parse_element(&1, mod))
        |> R.sequence()
        |> R.map(&(List.flatten(&1) |> Enum.sort() |> Enum.uniq()))
    end
  rescue
    _ in [MatchError, ArgumentError, FunctionClauseError] ->
      {:error, {:invalid_value, [__MODULE__, mod]}}
  end

  defp parse_element(str, mod) do
    case str do
      "*/" <> step ->
        {:ok, Enum.take_every(mod.min()..mod.max(), String.to_integer(step))}

      _ ->
        {range, step} = parse_range_and_step(str)
        {first, last} = parse_first_and_last(range)

        cond do
          first < mod.min() -> {:error, {:invalid_value, [__MODULE__, mod]}}
          last > mod.max() -> {:error, {:invalid_value, [__MODULE__, mod]}}
          true -> {:ok, Enum.take_every(first..last, step)}
        end
    end
  end

  defp parse_range_and_step(str) do
    case String.split(str, "/") do
      [r, s] -> {r, String.to_integer(s)}
      [_] -> {str, 1}
    end
  end

  defp parse_first_and_last(range) do
    case String.split(range, "-") do
      [f, l] ->
        {String.to_integer(f), String.to_integer(l)}

      [_] ->
        i = String.to_integer(range)
        {i, i}
    end
  end

  defun next(cron :: v[t], t :: v[Time.t()]) :: v[Time.t()] do
    # ensure that returned time is larger than the given time `t` by making "1 minute after `t`" as the starting point
    next_impl(cron, beginning_of_next_minute(t))
  end

  defp next_impl(cron, {_, ymd1, {h1, m1, _}, _} = t) do
    ymd2 = find_matching_date(cron, ymd1)

    if ymd2 == ymd1 do
      # no reset, `h1` and `m1` are still valid
      case find_matching_hour_and_minute(cron, h1, m1) do
        {h2, m2} ->
          {Time, ymd2, {h2, m2, 0}, 0}

        nil ->
          # can't find matching hour and minute in this day; search again from the beginning of the next day
          next_impl(cron, beginning_of_next_day(t))
      end
    else
      # hour and minute are reset to 0, we don't have to worry about carries
      {h2, m2} = find_matching_hour_and_minute(cron, 0, 0)
      {Time, ymd2, {h2, m2, 0}, 0}
    end
  end

  defp beginning_of_next_minute(t), do: Time.truncate_to_minute(t) |> Time.shift_minutes(1)
  defp beginning_of_next_day(t), do: Time.truncate_to_day(t) |> Time.shift_days(1)

  defp find_matching_date(%__MODULE__{day_of_month: :*, day_of_week: :*, month: :*}, ymd), do: ymd

  defp find_matching_date(%__MODULE__{day_of_month: :*, day_of_week: :*} = cron, ymd),
    do: find_matching_month(cron, ymd)

  defp find_matching_date(%__MODULE__{day_of_week: :*} = cron, ymd),
    do: find_matching_date_by_day_of_month(cron, ymd)

  defp find_matching_date(%__MODULE__{day_of_month: :*} = cron, ymd),
    do: find_matching_date_by_day_of_week(cron, ymd)

  defp find_matching_date(%__MODULE__{} = cron, ymd) do
    min(
      find_matching_date_by_day_of_month(cron, ymd),
      find_matching_date_by_day_of_week(cron, ymd)
    )
  end

  defp find_matching_date_by_day_of_month(%__MODULE__{day_of_month: day_of_month} = cron, ymd) do
    {y, m, d1} = find_matching_month(cron, ymd)
    last_day_of_month = :calendar.last_day_of_the_month(y, m)

    case Enum.find(day_of_month, &(&1 >= d1)) do
      d2 when d2 <= last_day_of_month ->
        {y, m, d2}

      _ ->
        # can't find matching date in this month; search again from the 1st day of the next month
        find_matching_date_by_day_of_month(cron, next_month_1st(y, m))
    end
  end

  defp find_matching_date_by_day_of_week(%__MODULE__{day_of_week: day_of_week} = cron, ymd1) do
    {y, m, d1} = ymd2 = find_matching_month(cron, ymd1)
    dow1 = day_of_the_week(ymd2)
    d2 = d1 + num_days_to_day_of_week(day_of_week, dow1)

    if d2 <= :calendar.last_day_of_the_month(y, m) do
      {y, m, d2}
    else
      # can't find matching date in this month; search again from the 1st day of the next month
      find_matching_date_by_day_of_week(cron, next_month_1st(y, m))
    end
  end

  defp num_days_to_day_of_week(day_of_week, dow_offset) do
    case Enum.find(day_of_week, &(&1 >= dow_offset)) do
      nil -> hd(day_of_week) + 7 - dow_offset
      dow2 -> dow2 - dow_offset
    end
  end

  defp find_matching_month(%__MODULE__{month: month} = cron, {y, m1, d}) do
    case find_matching_value(month, m1) do
      nil -> find_matching_month(cron, {y + 1, 1, 1})
      ^m1 -> {y, m1, d}
      m2 -> {y, m2, 1}
    end
  end

  defpt day_of_the_week(ymd) do
    case :calendar.day_of_the_week(ymd) do
      # `:calendar.daynum` type is defined as `1..7`; we need to convert 7 to 0 (which represents sunday)
      7 -> 0
      dow -> dow
    end
  end

  defp next_month_1st(y, 12), do: {y + 1, 1, 1}
  defp next_month_1st(y, m), do: {y, m + 1, 1}

  defp find_matching_hour_and_minute(%__MODULE__{hour: hour, minute: minute} = cron, h1, m1) do
    case find_matching_value(hour, h1) do
      # can't find matching hour in this day
      nil ->
        nil

      ^h1 ->
        # no reset, `m1` is still valid
        case find_matching_value(minute, m1) do
          nil when h1 == 23 -> nil
          nil -> find_matching_hour_and_minute(cron, h1 + 1, 0)
          m2 -> {h1, m2}
        end

      h2 ->
        {h2, find_matching_value(minute, 0)}
    end
  end

  defp find_matching_value(:*, v), do: v
  defp find_matching_value(l, v), do: Enum.find(l, &(&1 >= v))

  defun next_in_epoch_milliseconds(cron :: v[t], t :: v[MilliSecondsSinceEpoch.t()]) ::
          v[MilliSecondsSinceEpoch.t()] do
    next(cron, Time.from_epoch_milliseconds(t)) |> Time.to_epoch_milliseconds()
  end
end
