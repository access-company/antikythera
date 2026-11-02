# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Metrics.AggregateStrategy.RequestCountTest do
  use Croma.TestCase

  defp aggregate([first | rest]) do
    Enum.reduce(rest, RequestCount.init(first), &RequestCount.merge(&2, &1))
    |> RequestCount.results()
  end

  test "results should count total, 4XX, 401 and 5XX responses" do
    assert aggregate([200]) == [total: 1, "4XX": 0, "401": 0, "5XX": 0]
    assert aggregate([401]) == [total: 1, "4XX": 1, "401": 1, "5XX": 0]
    assert aggregate([404]) == [total: 1, "4XX": 1, "401": 0, "5XX": 0]
    assert aggregate([500]) == [total: 1, "4XX": 0, "401": 0, "5XX": 1]

    assert aggregate([200, 302, 400, 401, 401, 403, 500, 503]) ==
             [total: 8, "4XX": 4, "401": 2, "5XX": 2]
  end

  test "merge and results should accept data without the 401 count" do
    assert RequestCount.results({3, 1, 1}) == [total: 3, "4XX": 1, "401": 0, "5XX": 1]
    assert RequestCount.merge({3, 1, 1}, 401) == {4, 2, 1, 1}
    assert RequestCount.merge({3, 1, 1}, 200) == {4, 1, 0, 1}
  end
end
