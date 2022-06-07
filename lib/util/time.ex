# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Time do
  @moduledoc """
  Data structure to represent date and time in milli-seconds resolution.

  Note that all values of `Antikythera.Time.t` are in UTC.

  `Poison.Encoder` protocol is implemented for `Antikythera.Time.t`,
  so that values of this type can be directly converted to `Antikythera.IsoTimestamp.t` on `Poison.encode/1`.

      iex> Poison.encode(%{time: {Antikythera.Time, {2017, 1, 1}, {0, 0, 0}, 0}})
      {:ok, "{\\"time\\":\\"2017-01-01T00:00:00.000+00:00\\"}"}

  See also `new/1`.
  """

  alias Croma.Result, as: R
  alias Antikythera.{IsoTimestamp, ImfFixdate}
  alias Antikythera.IsoTimestamp.Basic, as: IsoBasic
  alias Antikythera.MilliSecondsInGregorian

  @typep milliseconds :: 0..999
  @type t :: {__MODULE__, :calendar.date(), :calendar.time(), milliseconds}

  defun valid?(v :: term) :: boolean do
    {__MODULE__, date, {h, m, s}, ms} ->
      :calendar.valid_date(date) and h in 0..23 and m in 0..59 and s in 0..59 and ms in 0..999

    _ ->
      false
  end

  @doc """
  Convert timestamps into `Antikythera.Time.t` or wrap valid `Antikythera.Time.t`,
  leveraging `recursive_new?` option of `Croma.Struct`.

  Only `Antikythera.IsoTimestamp.t` can be converted.

      iex> {:ok, time} = #{__MODULE__}.new("2015-01-23T23:50:07Z")
      {:ok, {#{__MODULE__}, {2015, 1, 23}, {23, 50, 7}, 0}}
      iex> #{__MODULE__}.new(time)
      {:ok, {#{__MODULE__}, {2015, 1, 23}, {23, 50, 7}, 0}}
      iex> #{__MODULE__}.new("2015-01-23T23:50:07") |> Croma.Result.error?()
      true
      iex> #{__MODULE__}.new(nil) |> Croma.Result.error?()
      true
  """
  defun new(t | IsoTimestamp.t()) :: R.t(t) do
    s when is_binary(s) -> from_iso_timestamp(s)
    t -> R.wrap_if_valid(t, __MODULE__)
  end

  defun truncate_to_day({__MODULE__, date, {_, _, _}, _} :: t) :: t,
    do: {__MODULE__, date, {0, 0, 0}, 0}

  defun truncate_to_hour({__MODULE__, date, {hour, _, _}, _} :: t) :: t,
    do: {__MODULE__, date, {hour, 0, 0}, 0}

  defun truncate_to_minute({__MODULE__, date, {hour, minute, _}, _} :: t) :: t,
    do: {__MODULE__, date, {hour, minute, 0}, 0}

  defun truncate_to_second({__MODULE__, date, {hour, minute, second}, _} :: t) :: t,
    do: {__MODULE__, date, {hour, minute, second}, 0}

  defun now() :: t do
    from_epoch_milliseconds(System.system_time(:millisecond))
  end

  defun to_iso_timestamp({__MODULE__, {y, mon, d}, {h, min, s}, millis} :: t) :: IsoTimestamp.t() do
    import Antikythera.StringFormat

    <<Integer.to_string(y)::binary-size(4), "-", pad2(mon)::binary-size(2), "-",
      pad2(d)::binary-size(2), "T", pad2(h)::binary-size(2), ":", pad2(min)::binary-size(2), ":",
      pad2(s)::binary-size(2), ".", pad3(millis)::binary-size(3), "+00:00">>
  end

  defun to_iso_basic({__MODULE__, {y, mon, d}, {h, min, s}, _} :: t) :: IsoBasic.t() do
    import Antikythera.StringFormat

    <<Integer.to_string(y)::binary-size(4), pad2(mon)::binary-size(2), pad2(d)::binary-size(2),
      "T", pad2(h)::binary-size(2), pad2(min)::binary-size(2), pad2(s)::binary-size(2), "Z">>
  end

  defun from_iso_timestamp(s :: v[String.t()]) :: R.t(t) do
    R.try(fn ->
      <<year::binary-size(4), "-", month::binary-size(2), "-", day::binary-size(2), "T",
        hour::binary-size(2), ":", minute::binary-size(2), ":", second::binary-size(2),
        rest1::binary>> = s

      {millis, rest2} = extract_millis(rest1)

      time = {
        __MODULE__,
        {String.to_integer(year), String.to_integer(month), String.to_integer(day)},
        {String.to_integer(hour), String.to_integer(minute), String.to_integer(second)},
        millis
      }

      adjust_by_timezone_offset(time, rest2)
    end)
    |> R.bind(&R.wrap_if_valid(&1, __MODULE__))
  end

  R.define_bang_version_of(from_iso_timestamp: 1)

  defun from_iso_basic(s :: v[String.t()]) :: R.t(t) do
    R.try(fn ->
      <<year::binary-size(4), month::binary-size(2), day::binary-size(2), "T",
        hour::binary-size(2), minute::binary-size(2), second::binary-size(2), rest::binary>> = s

      time = {
        __MODULE__,
        {String.to_integer(year), String.to_integer(month), String.to_integer(day)},
        {String.to_integer(hour), String.to_integer(minute), String.to_integer(second)},
        0
      }

      adjust_by_timezone_offset(time, rest)
    end)
    |> R.bind(&R.wrap_if_valid(&1, __MODULE__))
  end

  R.define_bang_version_of(from_iso_basic: 1)

  defp extract_millis(str) do
    case str do
      <<".", millis::binary-size(3), rest::binary>> -> {String.to_integer(millis), rest}
      _ -> {0, str}
    end
  end

  defp adjust_by_timezone_offset(t, str) do
    case extract_timezone_offset_minutes(str) do
      0 -> t
      offset_minutes -> shift_minutes(t, -offset_minutes)
    end
  end

  defp extract_timezone_offset_minutes(str) do
    case str do
      <<"+", h::binary-size(2), ":", m::binary-size(2)>> -> convert_to_minutes(h, m)
      <<"+", h::binary-size(2), m::binary-size(2)>> -> convert_to_minutes(h, m)
      <<"-", h::binary-size(2), ":", m::binary-size(2)>> -> -convert_to_minutes(h, m)
      <<"-", h::binary-size(2), m::binary-size(2)>> -> -convert_to_minutes(h, m)
      "Z" -> 0
    end
  end

  defp convert_to_minutes(hour, minute) do
    String.to_integer(hour) * 60 + String.to_integer(minute)
  end

  defun shift_milliseconds(t :: v[t], milliseconds :: v[integer]) :: t do
    from_gregorian_milliseconds(to_gregorian_milliseconds(t) + milliseconds)
  end

  defun shift_seconds(t :: v[t], seconds :: v[integer]) :: t,
    do: shift_milliseconds(t, seconds * 1_000)

  defun shift_minutes(t :: v[t], minutes :: v[integer]) :: t,
    do: shift_milliseconds(t, minutes * 60 * 1_000)

  defun shift_hours(t :: v[t], hours :: v[integer]) :: t,
    do: shift_milliseconds(t, hours * 60 * 60 * 1_000)

  defun shift_days(t :: v[t], days :: v[integer]) :: t,
    do: shift_milliseconds(t, days * 24 * 60 * 60 * 1_000)

  defun diff_milliseconds(t1 :: v[t], t2 :: v[t]) :: integer do
    to_gregorian_milliseconds(t1) - to_gregorian_milliseconds(t2)
  end

  defun to_gregorian_milliseconds({__MODULE__, d, t, ms} :: t) :: integer do
    seconds = :calendar.datetime_to_gregorian_seconds({d, t})
    seconds * 1000 + ms
  end

  defun from_gregorian_milliseconds(milliseconds :: v[integer]) :: t do
    m = rem(milliseconds, 1000)
    s = div(milliseconds, 1000)
    {date, time} = :calendar.gregorian_seconds_to_datetime(s)
    {__MODULE__, date, time, m}
  end

  defun to_epoch_milliseconds(t :: v[t]) :: integer do
    to_gregorian_milliseconds(t) - MilliSecondsInGregorian.time_epoch_offset_milliseconds()
  end

  defun from_epoch_milliseconds(milliseconds :: v[MilliSecondsInGregorian.t()]) :: t do
    from_gregorian_milliseconds(
      milliseconds + MilliSecondsInGregorian.time_epoch_offset_milliseconds()
    )
  end

  @doc """
  Returns date/time in IMF-fixdate format.

  The format is subset of Internet Message Format (RFC5322, formarly RFC822, RFC1123).
  Defined as 'preferred' format in RFC7231 and modern web servers or clients should send in this format.

  https://tools.ietf.org/html/rfc7231#section-7.1.1.1
  """
  defun to_http_date({__MODULE__, {y, mon, d} = date, {h, min, s}, _} :: t) :: ImfFixdate.t() do
    # Not using `:httpd_util.rfc1123_date/2` since it reads inputs as localtime and forcibly perform UTC conversion
    import Antikythera.StringFormat
    day_str = :httpd_util.day(:calendar.day_of_the_week(date))
    mon_str = :httpd_util.month(mon)
    "#{day_str}, #{pad2(d)} #{mon_str} #{y} #{pad2(h)}:#{pad2(min)}:#{pad2(s)} GMT"
  end

  @doc """
  Parses HTTP-date formats into Antikythera.Time.t.

  Supports IMF-fixdate format, RFC 850 format and ANSI C's `asctime()` format for compatibility.

  Note: An HTTP-date value must represents time in UTC(GMT). Thus timezone string in the end must always be 'GMT'.
  Any other timezone string (such as 'JST') will actually be ignored and parsed as GMT.

  https://tools.ietf.org/html/rfc7231#section-7.1.1.1
  """
  defun from_http_date(s :: v[String.t()]) :: R.t(t) do
    # safe to use since it always read input as UTC
    case :httpd_util.convert_request_date(String.to_charlist(s)) do
      {date, time} -> R.wrap_if_valid({__MODULE__, date, time, 0}, __MODULE__)
      :bad_date -> {:error, {:bad_date, s}}
    end
  end

  R.define_bang_version_of(from_http_date: 1)
end
