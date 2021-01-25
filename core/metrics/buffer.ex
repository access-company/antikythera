# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Metrics.Buffer do
  @moduledoc """
  A bin-like data structure to hold per-minute, per-epool metrics data.

      %{
        {time_minute, epool_id} => %{
          {metrics_type, strategy} => data_in_processing,
          {metrics_type, strategy} => data_in_processing,
          ...
        },
        ...
      }
  """

  alias Antikythera.Time
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

  @type minute :: Time.t()
  @type metrics_type :: {String.t(), Strategy.t()}
  @type metrics_value :: Strategy.data_t()
  @type epool_id :: EPoolId.nopool_t() | EPoolId.t()
  @type metrics_data_map :: %{metrics_type => metrics_value}
  @type metrics_unit :: {minute, epool_id}
  @type t :: %{metrics_unit => metrics_data_map}

  defun new() :: t, do: %{}

  defun add(
          buffer :: t,
          now :: v[Time.t()],
          list :: [{String.t(), Strategy.t(), number}],
          epool_id :: epool_id
        ) :: t do
    unit = {Time.truncate_to_minute(now), epool_id}

    new_data_map =
      Enum.reduce(list, buffer[unit] || %{}, fn {type, strategy, value}, map ->
        key = {type, strategy}
        Map.update(map, key, strategy.init(value), &strategy.merge(&1, value))
      end)

    Map.put(buffer, unit, new_data_map)
  end

  defun partition_ongoing_and_past(buffer :: t, now :: v[Time.t()]) ::
          {t, [{metrics_unit, metrics_data_map}]} do
    now_minute = Time.truncate_to_minute(now)

    {ongoing, past} =
      Enum.split_with(buffer, fn {{minute, _epool_id}, _data_map} ->
        Time.diff_milliseconds(minute, now_minute) >= 0
      end)

    {Map.new(ongoing), past}
  end
end
