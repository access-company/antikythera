# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.NestedMap do
  @moduledoc """
  Utility functions to work with nested maps.
  """

  alias Antikythera.MapUtil

  defun deep_merge(m1 :: v[map], m2 :: v[map]) :: map do
    Map.merge(m1, m2, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> deep_merge(v1, v2)
      _k, _v1, v2 -> v2
    end)
  end

  defun force_update(m :: v[map], keys :: [any], fun :: (any -> any)) :: map do
    case keys do
      [key] ->
        new_value = Map.get(m, key) |> fun.()
        Map.put(m, key, new_value)

      [k | ks] ->
        child_map =
          case Map.fetch(m, k) do
            {:ok, v} when is_map(v) -> v
            _ -> %{}
          end

        new_map = force_update(child_map, ks, fun)
        Map.put(m, k, new_map)
    end
  end

  @doc """
  Updates a key in a nested map. Recursively traversing the map according to the given `keys`
  to the last member. If the last member exists, update it with the given function.
  Unlike `Kernel.update_in/3`, returns `:error` if any of the `keys` cannot be found.
  """
  defun update_existing_in(m :: v[map], keys :: [any], fun :: (any -> any)) :: {:ok, map} | :error do
    case keys do
      [key] ->
        MapUtil.update_existing(m, key, fun)

      [k | ks] ->
        case Map.fetch(m, k) do
          {:ok, v} when is_map(v) ->
            case update_existing_in(v, ks, fun) do
              {:ok, new_map} -> {:ok, Map.put(m, k, new_map)}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end
end
