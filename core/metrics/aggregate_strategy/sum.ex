# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma
alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

defmodule Strategy.Sum do
  @moduledoc """
  Aggregate strategy that computes the sum of all values generated within each time window.
  """

  @behaviour Strategy.Behaviour

  @typep data_t :: number

  @impl true
  defun init(value :: v[number]) :: data_t, do: value

  @impl true
  defun merge(old_value :: data_t, value :: v[number]) :: data_t, do: old_value + value

  @impl true
  defun results(value :: data_t) :: Strategy.results_t, do: [sum: value]
end
