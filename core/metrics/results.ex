# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Metrics.Results do
  @moduledoc """
  Data structure to represent metrics results computed from raw metrics data.
  Results are map of metrics data by minute-epool.

      %{
        {time_minute, epool_id} => %{
          metrics_label => metrics_value,
          metrics_label => metrics_value,
          ...
        },
        ...
      }
  """

  alias Antikythera.NestedMap
  alias AntikytheraCore.Metrics.Buffer

  @type metrics_label        :: String.t
  @type per_unit_results_map :: %{metrics_label => Buffer.metrics_value}
  @type t                    :: %{Buffer.metrics_unit => per_unit_results_map}

  defun new() :: t, do: %{}

  defun merge(r1 :: t, r2 :: t) :: t do
    NestedMap.deep_merge(r1, r2)
  end

  defun compute_results(list :: [{Buffer.metrics_unit, Buffer.metrics_data_map}]) :: t do
    Map.new(list, fn {unit, data_per_unit} ->
      {unit, make_per_unit_results_map(data_per_unit)}
    end)
  end

  defunp make_per_unit_results_map(data_per_unit :: %{Buffer.metrics_type => Buffer.metrics_value}) :: per_unit_results_map do
    Enum.flat_map(data_per_unit, fn {{type, strategy}, data} ->
      strategy.results(data) |> Enum.map(fn {name, value} -> {"#{type}_#{name}", value} end)
    end)
    |> Map.new()
  end
end
