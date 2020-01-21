# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Metrics.AggregateStrategy.TimeDistributionTest do
  use Croma.TestCase
  use ExUnitProperties

  defp find_95_percentile_naive(count, values) do
    Enum.sort(values) |> Enum.reverse() |> Enum.at(div(count, 20))
  end

  property "find_95_percentile returns the same result as naive implementation" do
    check all l <- list_of(integer()), !Enum.empty?(l) do
      count = length(l)
      assert TimeDistribution.find_95_percentile(count, l) == find_95_percentile_naive(count, l)
    end
  end
end
