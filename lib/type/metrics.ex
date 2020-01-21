# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Metrics.Data do
  alias AntikytheraCore.Metrics.Buffer
  alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy

  @type t :: {String.t, Strategy.Name.t, Buffer.metrics_value}

  defun valid?(v :: term) :: boolean do
    {n, s, v} when is_binary(n) and is_number(v) -> Strategy.Name.valid?(s)
    _                                            -> false
  end
end

defmodule Antikythera.Metrics.DataList do
  use Croma.SubtypeOfList, elem_module: Antikythera.Metrics.Data, min_length: 1
end
