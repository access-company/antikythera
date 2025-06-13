# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.TimeTest do
  use Croma.TestCase

  test "to_iso_timestamp/1 should return valid ISO8601 extended format string" do
    t = {Time, {2016, 2, 25}, {1, 23, 3}, 123, 45}
    expected = "2016-02-25T01:23:03.123045+00:00"

    assert Time.to_iso_timestamp(t) == expected
  end

  test "to_antikythera_time/1 should return Antikythera.Time at the same time" do
    t = {Time, {2016, 2, 25}, {1, 23, 3}, 123, 45}
    expected = {Antikythera.Time, {2016, 2, 25}, {1, 23, 3}, 123}

    assert Time.to_antikythera_time(t) == expected
  end

  test "from_epoch_microseconds/1 should return the correct Time" do
    microseconds = 1_749_800_155_992_667
    expected = {Time, {2025, 6, 13}, {7, 35, 55}, 992, 667}

    assert Time.from_epoch_microseconds(microseconds) == expected
  end
end
