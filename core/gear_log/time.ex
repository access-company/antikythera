# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.Time do
  @moduledoc """
  Data structure to represent date and time in micro-seconds resolution.

  This module is used by gear logger related code.
  If you write code that call `AntikytheraCore.GearLog.Writer` functions, use this module.
  Use `Antikythera.Time` for other cases. i.e. calculating used time in a request.

  Note that all values of `AntikytheraCore.GearLog.Time.t` are in UTC.

  See also `new/1`.
  """

  alias Antikythera.IsoTimestamp
  alias Antikythera.MicroSecondsInGregorian

  @typep milliseconds :: 0..999
  @typep microseconds :: 0..999
  @type t :: {__MODULE__, :calendar.date(), :calendar.time(), milliseconds, microseconds}

  defun valid?(v :: term) :: boolean do
    {__MODULE__, date, {h, m, s}, ms, us} ->
      :calendar.valid_date(date) and h in 0..23 and m in 0..59 and s in 0..59 and ms in 0..999 and
        us in 0..999

    _ ->
      false
  end

  defun now() :: t do
    from_epoch_microseconds(System.system_time(:microsecond))
  end

  defun to_iso_timestamp({__MODULE__, {y, mon, d}, {h, min, s}, ms, us} :: t) :: IsoTimestamp.t() do
    import Antikythera.StringFormat

    <<Integer.to_string(y)::binary-size(4), "-", pad2(mon)::binary-size(2), "-",
      pad2(d)::binary-size(2), "T", pad2(h)::binary-size(2), ":", pad2(min)::binary-size(2), ":",
      pad2(s)::binary-size(2), ".", pad3(ms)::binary-size(3), pad3(us)::binary-size(3), "+00:00">>
  end

  defun to_antikythera_time({__MODULE__, date, time, ms, _} :: t) :: Antikythera.Time.t() do
    Antikythera.Time.new({Antikythera.Time, date, time, ms}) |> Croma.Result.get!()
  end

  defunp from_gregorian_microseconds(microseconds :: v[integer]) :: t do
    s = div(microseconds, 1000 * 1000)
    {date, time} = :calendar.gregorian_seconds_to_datetime(s)
    m = rem(microseconds, 1000 * 1000)
    ms = div(m, 1000)
    us = rem(m, 1000)
    {__MODULE__, date, time, ms, us}
  end

  defunpt from_epoch_microseconds(microseconds :: v[MicroSecondsInGregorian.t()]) :: t do
    from_gregorian_microseconds(
      microseconds + MicroSecondsInGregorian.time_epoch_offset_microseconds()
    )
  end
end
