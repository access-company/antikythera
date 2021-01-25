# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma
alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

defmodule Strategy.Gauge do
  @moduledoc """
  Aggregate strategy that simply takes the last value within each time window.
  """

  @behaviour Strategy.Behaviour

  @typep data_t :: number

  @impl true
  defun init(value :: v[number]) :: data_t, do: value

  @impl true
  defun merge(_old_value :: data_t, value :: v[number]) :: data_t, do: value

  @impl true
  defun results(value :: data_t) :: Strategy.results_t(), do: [value: value]
end
