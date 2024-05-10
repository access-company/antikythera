# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.Setting do
  alias Antikythera.{MapUtil, GearName}
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.ExecutorPool.WsConnectionsCapping

  use Croma.Struct,
    fields: [
      n_pools_a: Croma.NonNegInteger,
      pool_size_a: Croma.NonNegInteger,
      pool_size_j: Croma.NonNegInteger,
      ws_max_connections: Croma.NonNegInteger
    ]

  @default %{
    # Ugly hack to define instance of struct within the same compilation unit of `defstruct`
    __struct__: __MODULE__,
    n_pools_a: 1,
    pool_size_a: 5,
    pool_size_j: 2,
    ws_max_connections: 100
  }
  defun default() :: t, do: @default

  defun of_gear(gear_name :: v[GearName.t()]) :: t do
    Map.get(all(), gear_name, @default)
  end

  defun all() :: %{GearName.t() => t} do
    ConfigCache.Core.read()
    |> Map.get(:gears, %{})
    |> MapUtil.map_values(fn {_, map} ->
      Map.merge(@default, Map.get(map, :executor_pool, %{}))
      |> WsConnectionsCapping.cap_based_on_available_memory()
    end)
  end
end
