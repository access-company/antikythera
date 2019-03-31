# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma
alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

defmodule Strategy.TimeDistribution do
  @moduledoc """
  Aggregate strategy for time distribution (such as response times).
  This calculates the following values from time durations generated within a time window:

  - average
  - maximum
  - 95-percentile
  """

  @behaviour Strategy.Behaviour

  @typep data_t :: {pos_integer, number, number, [number]}

  @impl true
  defun init(value :: v[number]) :: data_t do
    {1, value, value, [value]}
  end

  @impl true
  defun merge({count, total, max_so_far, values_so_far} :: data_t, value :: v[number]) :: data_t do
    {count + 1, total + value, max(max_so_far, value), [value | values_so_far]}
  end

  @impl true
  defun results({count, total, max, values} :: data_t) :: Strategy.results_t do
    [
      avg:   Float.round(total / count, 2), # truncate long floating number
      max:   max,
      "95%": find_95_percentile(count, values),
    ]
  end

  defunpt find_95_percentile(count :: v[non_neg_integer], values :: [number]) :: number do
    find_nth_largest(div(count, 20), values)
  end

  defp find_nth_largest(index, [pivot | values]) do
    {larger, smaller, larger_count} = Enum.reduce(values, {[], [], 0}, fn(v, {larger, smaller, count}) ->
      if v > pivot, do: {[v | larger], smaller, count + 1}, else: {larger, [v | smaller], count}
    end)
    cond do
      index <  larger_count -> find_nth_largest(index, larger)
      index == larger_count -> pivot
      true                  -> find_nth_largest(index - larger_count - 1, smaller)
    end
  end
end
