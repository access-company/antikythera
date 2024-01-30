# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.TermUtil do
  @moduledoc """
  Utils for calculating the actual size of terms.

  These utils traverse terms and accumulate the size of terms including the actual size of binary.
  """

  @doc """
  Returns the actual size of `term` in bytes.
  """
  defun size(term :: term) :: non_neg_integer do
    :erts_debug.flat_size(term) * :erlang.system_info(:wordsize) + total_binary_size(term)
  end

  defunp total_binary_size(term :: term) :: non_neg_integer do
    b when is_bitstring(b) -> byte_size(b)
    t when is_tuple(t) -> total_binary_size_in_list(Tuple.to_list(t))
    l when is_list(l) -> total_binary_size_in_list(l)
    # including non-enumerable structs
    m when is_map(m) -> total_binary_size_in_list(Map.to_list(m))
    _ -> 0
  end

  defunp total_binary_size_in_list(list :: v[[term]]) :: non_neg_integer do
    Enum.reduce(list, 0, fn e, acc -> total_binary_size(e) + acc end)
  end

  @doc """
  Returns whether actual size of `term` exceeds `limit` bytes.

  This is more efficient than deciding by using `size/1` because this function returns immediately after exceeding `limit`, not traverses the entire term.
  """
  defun size_smaller_or_equal?(term :: term, limit :: v[non_neg_integer]) :: boolean do
    case limit - :erts_debug.flat_size(term) * :erlang.system_info(:wordsize) do
      new_limit when new_limit >= 0 -> limit_minus_total_binary_size(term, new_limit) >= 0
      _ -> false
    end
  end

  defunp limit_minus_total_binary_size(term :: term, limit :: v[non_neg_integer]) :: integer do
    case term do
      b when is_bitstring(b) -> limit - byte_size(b)
      t when is_tuple(t) -> reduce_while_positive(Tuple.to_list(t), limit)
      l when is_list(l) -> reduce_while_positive(l, limit)
      # including non-enumerable structs
      m when is_map(m) -> reduce_while_positive(Map.to_list(m), limit)
      _ -> limit
    end
  end

  defunp reduce_while_positive(list :: v[[term]], limit :: v[non_neg_integer]) :: integer do
    Enum.reduce_while(list, limit, fn e, l1 ->
      l2 = limit_minus_total_binary_size(e, l1)
      if l2 < 0, do: {:halt, l2}, else: {:cont, l2}
    end)
  end
end
