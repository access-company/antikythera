# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule SolomonLib.CronTest do
  use Croma.TestCase
  alias SolomonLib.Time

  test "parse/1 should reject invalid cron format" do
    [
      "",
      "* * * *",
      "* * * * * *",
      "a b c d e",
      "60 * * * *",
      "* 24 * * *",
      "* * 32 * *",
      "* * * 13 *",
      "* * * * 7",
      "-1 * * * *",
      "* -1 * * *",
      "* * 0 * *",
      "* * * 0 *",
      "* * * * -1",
      "0, * * * *",
      "-2 * * * *",
      "*,0 * * * *", # `*` (without step) must be used as a single element
      "0,* * * * *",
    ] |> Enum.each(fn(s) ->
      assert {:error, _} = Cron.parse(s)
    end)
  end

  test "parse/1 should reject syntactically correct but void schedule" do
    [
      "* * 30 2 *",
      "* * 30,31 2 *",
      "* * 30-31 2 *",
      "* * 31 2 *",
      "* * 31 4 *",
      "* * 31 6 *",
      "* * 31 9 *",
      "* * 31 11 *",
      "* * 31 2,4,6,9,11 *",
    ] |> Enum.each(fn(s) ->
      assert {:error, _} = Cron.parse(s)
    end)
  end

  test "next/2 should compute Time.t next to the given one" do
    [
      {"* * * * *", {2017, 12, 31, 23, 58}, [
          {2017, 12, 31, 23, 59},
          {2018,  1,  1,  0,  0},
          {2018,  1,  1,  0,  1},
        ]},
      {"*/10,42,32-47/5 * * * *", {2017, 1, 25, 0, 15}, [
          {2017, 1, 25, 0, 20},
          {2017, 1, 25, 0, 30},
          {2017, 1, 25, 0, 32},
          {2017, 1, 25, 0, 37},
          {2017, 1, 25, 0, 40},
          {2017, 1, 25, 0, 42},
          {2017, 1, 25, 0, 47},
          {2017, 1, 25, 0, 50},
        ]},
      {"10,50 */10 * * *", {2017, 1, 1, 5, 30}, [
          {2017, 1, 1, 10, 10},
          {2017, 1, 1, 10, 50},
          {2017, 1, 1, 20, 10},
          {2017, 1, 1, 20, 50},
        ]},
      {"0 10,20 1 * *", {2017, 1, 2, 15, 0}, [
          {2017, 2, 1, 10, 0},
          {2017, 2, 1, 20, 0},
          {2017, 3, 1, 10, 0},
          {2017, 3, 1, 20, 0},
        ]},
      {"10 20 1 2-5 *", {2017, 1, 25, 0, 0}, [
          {2017, 2, 1, 20, 10},
          {2017, 3, 1, 20, 10},
          {2017, 4, 1, 20, 10},
          {2017, 5, 1, 20, 10},
          {2018, 2, 1, 20, 10},
        ]},
      {"0 0 29 2 *", {2017, 1, 25, 0, 0}, [
          {2020, 2, 29, 0, 0},
          {2024, 2, 29, 0, 0},
          {2028, 2, 29, 0, 0},
          {2032, 2, 29, 0, 0},
          {2036, 2, 29, 0, 0},
        ]},
      {"0 0 29 1-2,12 *", {2017, 1, 1, 0, 0}, [
          {2017,  1, 29, 0, 0},
          {2017, 12, 29, 0, 0},
          {2018,  1, 29, 0, 0},
          {2018, 12, 29, 0, 0},
          {2019,  1, 29, 0, 0},
          {2019, 12, 29, 0, 0},
          {2020,  1, 29, 0, 0},
          {2020,  2, 29, 0, 0},
          {2020, 12, 29, 0, 0},
          {2021,  1, 29, 0, 0},
        ]},
      {"10 20 * 12 0,6", {2017, 1, 1, 0, 0}, [
          {2017, 12,  2, 20, 10},
          {2017, 12,  3, 20, 10},
          {2017, 12,  9, 20, 10},
          {2017, 12, 10, 20, 10},
          {2017, 12, 16, 20, 10},
          {2017, 12, 17, 20, 10},
          {2017, 12, 23, 20, 10},
          {2017, 12, 24, 20, 10},
          {2017, 12, 30, 20, 10},
          {2017, 12, 31, 20, 10},
          {2018, 12,  1, 20, 10},
          {2018, 12,  2, 20, 10},
        ]},
      {"0 0 * 1 1-5", {2017, 1, 30, 0, 0}, [ # 2017/1/30 is Monday (`1`)
          {2017, 1, 31, 0, 0},
          {2018, 1,  1, 0, 0}, # Monday
          {2018, 1,  2, 0, 0},
          {2018, 1,  3, 0, 0},
          {2018, 1,  4, 0, 0},
          {2018, 1,  5, 0, 0},
          {2018, 1,  8, 0, 0},
        ]},
      {"0 0 1,15 * 4", {2017, 1, 30, 0, 0}, [ # 2017/1/30 is Monday (`1`),
          {2017, 2,  1, 0, 0},
          {2017, 2,  2, 0, 0},
          {2017, 2,  9, 0, 0},
          {2017, 2, 15, 0, 0},
          {2017, 2, 16, 0, 0},
          {2017, 2, 23, 0, 0},
          {2017, 3,  1, 0, 0},
          {2017, 3,  2, 0, 0},
        ]},
    ] |> Enum.each(fn({pattern, time, next_times}) ->
      {:ok, cron} = Cron.parse(pattern)
      Enum.reduce(next_times, time, fn(next_time, prev_time) ->
        assert Cron.next(cron, tuple5_to_time(prev_time)) == tuple5_to_time(next_time)
        assert_cron_includes(cron, next_time)
        next_time
      end)
    end)
  end

  defp tuple5_to_time({y, mon, d, h, min}) do
    {Time, {y, mon, d}, {h, min, 0}, 0}
  end

  defp assert_cron_includes(cron, {y, mon, d, h, min}) do
    assert_field_includes(cron.minute      , min)
    assert_field_includes(cron.hour        , h  )
    assert_field_includes(cron.month       , mon)
    assert_included_day(cron.day_of_month, cron.day_of_week, y, mon, d)
  end

  defp assert_field_includes(:*, _), do: :ok
  defp assert_field_includes(l , v), do: assert v in l

  defp assert_included_day(:*          , :*         , _, _, _), do: :ok
  defp assert_included_day(day_of_month, :*         , _, _, d), do: assert d in day_of_month
  defp assert_included_day(:*          , day_of_week, y, m, d), do: assert Cron.day_of_the_week({y, m, d}) in day_of_week
  defp assert_included_day(day_of_month, day_of_week, y, m, d), do: assert (d in day_of_month) or (Cron.day_of_the_week({y, m, d}) in day_of_week)
end
