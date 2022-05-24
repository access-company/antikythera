# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.TimeTest do
  use Croma.TestCase
  alias Croma.Result, as: R
  alias Antikythera.{IsoTimestamp, ImfFixdate}
  alias Antikythera.IsoTimestamp.Basic, as: IsoBasic

  doctest Antikythera.Time

  test "to_iso_timestamp should return valid ISO8601 extended format string" do
    [
      Time.now(),
      {Time, {2016, 2, 25}, {0, 0, 0}, 0}
    ]
    |> Enum.each(fn t ->
      assert Time.to_iso_timestamp(t) |> IsoTimestamp.valid?()
    end)
  end

  test "to_iso_basic should return valid ISO8601 basic format string" do
    [
      Time.now(),
      {Time, {2016, 2, 25}, {0, 0, 0}, 0}
    ]
    |> Enum.each(fn t ->
      basic = Time.to_iso_basic(t)
      assert IsoBasic.valid?(basic)
      assert Time.from_iso_basic(basic) |> R.get!() == Time.truncate_to_second(t)
    end)
  end

  test "from_iso_timestamp should try to convert string to time" do
    t = Time.now()
    assert Time.to_iso_timestamp(t) |> Time.from_iso_timestamp() |> R.get!() == t

    assert Time.from_iso_timestamp("2016-02-24T19:55:23.974+09:00") ==
             Time.from_iso_timestamp("2016-02-24T10:55:23.974+00:00")

    assert Time.from_iso_timestamp("2016-02-24T19:55:23.974+09:00") ==
             Time.from_iso_timestamp("2016-02-24T10:55:23.974Z")

    assert Time.from_iso_timestamp("2016-02-24T19:55:23.000+09:00") ==
             Time.from_iso_timestamp("2016-02-24T10:55:23+00:00")

    assert Time.from_iso_timestamp("2016-02-24T19:55:23.000+0900") ==
             Time.from_iso_timestamp("2016-02-24T10:55:23+00:00")

    assert Time.from_iso_timestamp("2016-02-24T19:55:23.000+09:00") ==
             Time.from_iso_timestamp("2016-02-24T10:55:23Z")

    assert R.error?(Time.from_iso_timestamp(" 2016-02-24T10:55:23.974+00:00"))
    assert R.error?(Time.from_iso_timestamp("2016-02-24T10:55:23.974Y"))
    assert R.error?(Time.from_iso_timestamp("2016-02-24T10:55:23.974"))
    assert R.error?(Time.from_iso_timestamp("2016-99-99T10:55:23.974+00:00"))
    assert R.error?(Time.from_iso_timestamp("2016-02-24T99:99:99.974+00:00"))
    assert R.error?(Time.from_iso_timestamp("2016-02-24T99:99:99+00:00"))
  end

  test "from_iso_basic should try to convert string to time" do
    assert Time.from_iso_basic("20160224T195523+09:00") == Time.from_iso_basic("20160224T105523Z")
    assert Time.from_iso_basic("20160224T195523+0900") == Time.from_iso_basic("20160224T105523Z")
  end

  @t1 {Time, {2016, 2, 24}, {9, 19, 32}, 0}
  @t2 {Time, {2016, 2, 24}, {9, 19, 34}, 200}

  test "shift_milliseconds should add/subtract milliseconds from time" do
    assert Time.shift_milliseconds(@t1, 0) == @t1
    assert Time.shift_milliseconds(@t2, 0) == @t2
    assert Time.shift_milliseconds(@t1, 2200) == @t2
    assert Time.shift_milliseconds(@t2, -2200) == @t1
  end

  test "diff_milliseconds should return time diff in milliseconds" do
    assert Time.diff_milliseconds(@t1, @t1) == 0
    assert Time.diff_milliseconds(@t2, @t2) == 0
    assert Time.diff_milliseconds(@t1, @t2) == -2200
    assert Time.diff_milliseconds(@t2, @t1) == 2200
  end

  test "to_http_date should return valid IMF-fixdate format string" do
    [
      Time.now(),
      {Time, {2016, 2, 25}, {0, 0, 0}, 0}
    ]
    |> Enum.each(fn t ->
      assert Time.to_http_date(t) |> ImfFixdate.valid?()
    end)
  end

  test "from_http_date should try to convert HTTP date string to time" do
    t1 = Time.now() |> Time.truncate_to_second()
    assert Time.to_http_date(t1) |> Time.from_http_date() |> R.get!() == t1
    t2 = {Time, {2016, 2, 25}, {0, 0, 0}, 0}
    # RFC850 format
    assert Time.from_http_date("Thursday, 25-Feb-16 00:00:00 GMT") |> R.get!() == t2
    # ANSI C's asctime() format
    assert Time.from_http_date("Thu Feb 25 00:00:00 2016") |> R.get!() == t2
    # Timezone string just ignored
    assert Time.from_http_date("Thu, 25 Feb 2016 00:00:00 JST") |> R.get!() == t2
    assert R.error?(Time.from_http_date("Inv, 25 Inv 2016 00:00:00 GMT"))
    assert R.error?(Time.from_http_date("Thu, 99 Feb 2016 99:99:99 GMT"))
  end

  defmodule S do
    use Croma.Struct, recursive_new?: true, fields: [time: Time]
  end

  test "should be deserialized directly to Antikythera.Time.t, when used as field type of Croma.Struct" do
    assert S.new(%{"time" => "2017-01-01T00:00:00.000+00:00"}) ==
             {:ok, %S{time: {Time, {2017, 1, 1}, {0, 0, 0}, 0}}}

    assert S.new(%{"time" => "2017-01-00T00:00:00.000+00:00"}) ==
             {:error, {:invalid_value, [S, {Time, :time}]}}
  end

  test "should be converted to JSON using Poison.encode/1" do
    assert Poison.encode({Time, {2017, 1, 1}, {0, 0, 0}, 0}) ==
             {:ok, ~S("2017-01-01T00:00:00.000+00:00")}

    assert Poison.encode({Time, {2017, 1, 0}, {0, 0, 0}, 0}) ==
             {:error, {:invalid, {Time, {2017, 1, 0}, {0, 0, 0}, 0}}}

    map_with_time = %{"time" => {Time, {2017, 1, 1}, {0, 0, 0}, 0}}
    assert Poison.encode(map_with_time) == {:ok, ~S({"time":"2017-01-01T00:00:00.000+00:00"})}

    assert Poison.encode!(map_with_time) |> Poison.decode!() |> S.new!() |> Poison.encode() ==
             {:ok, ~S({"time":"2017-01-01T00:00:00.000+00:00"})}
  end
end
