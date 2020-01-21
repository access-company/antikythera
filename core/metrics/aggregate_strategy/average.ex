# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma
alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

defmodule Strategy.Average do
  @moduledoc """
  Aggregate strategy that calculates the average value of incoming raw metrics data.
  """

  @behaviour Strategy.Behaviour

  @typep data_t :: {pos_integer, number}

  @impl true
  defun init(value :: v[number]) :: data_t, do: {1, value}

  @impl true
  defun merge({count, total} :: data_t, value :: v[number]) :: data_t, do: {count + 1, total + value}

  @impl true
  defun results({count, total} :: data_t) :: Strategy.results_t, do: [avg: total / count]
end
