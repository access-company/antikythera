# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.MapUtil do
  @moduledoc """
  Utility functions to work with maps.
  """

  defun map_values(m :: v[%{k => v1}], f :: ({k, v1} -> v2)) :: %{k => v2}
        when k: any, v1: any, v2: any do
    Map.new(m, fn {k, v} -> {k, f.({k, v})} end)
  end

  defun difference(m1 :: v[%{k => v}], m2 :: v[%{k => v}]) ::
          {%{k => v}, %{k => {v, v}}, %{k => v}}
        when k: any, v: any do
    keys1 = Map.keys(m1) |> MapSet.new()
    keys2 = Map.keys(m2) |> MapSet.new()
    keys_only_in_m1 = MapSet.difference(keys1, keys2)
    keys_only_in_m2 = MapSet.difference(keys2, keys1)
    keys_common = MapSet.difference(keys1, keys_only_in_m1)

    diffs_with_common_keys =
      Enum.map(keys_common, fn k ->
        v1 = m1[k]
        v2 = m2[k]
        if v1 == v2, do: nil, else: {k, {v1, v2}}
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    {
      Map.take(m1, MapSet.to_list(keys_only_in_m1)),
      diffs_with_common_keys,
      Map.take(m2, MapSet.to_list(keys_only_in_m2))
    }
  end

  @doc """
  Update the `key` in `map` with the given function, only when the `key` exists.
  Unlike `Map.update!/3`, it returns `:error` if the `key` does not exist.
  """
  defun update_existing(map :: v[map], key :: any, fun :: (any -> any)) :: {:ok, map} | :error do
    case Map.fetch(map, key) do
      {:ok, v} -> {:ok, Map.put(map, key, fun.(v))}
      _ -> :error
    end
  end
end
