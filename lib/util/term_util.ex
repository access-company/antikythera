# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

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
    b when is_bitstring(b)         -> byte_size(b)
    t when is_tuple(t)             -> Tuple.to_list(t) |> Enum.reduce(0, fn(e, acc) -> total_binary_size(e) + acc end)
    l when is_list(l) or is_map(l) -> Enum.reduce(l, 0, fn(e, acc) -> total_binary_size(e) + acc end)
    _                              -> 0
  end

  @doc """
  Returns whether actual size of `term` exceeds `limit` bytes.

  This is more efficient than deciding by using `size/1` because this function returns immediately after exceeding `limit`, not traverses the entire term.
  """
  defun size_smaller_or_equal?(term :: term, limit :: non_neg_integer) :: boolean do
    case limit - :erts_debug.flat_size(term) * :erlang.system_info(:wordsize) do
      new_limit when new_limit >= 0 -> limit_minus_total_binary_size(term, new_limit) >= 0
      _                             -> false
    end
  end

  defunp limit_minus_total_binary_size(term :: term, limit :: non_neg_integer) :: integer do
    case term do
      b when is_bitstring(b)         -> limit - byte_size(b)
      t when is_tuple(t)             -> Tuple.to_list(t) |> reduce_while_positive(limit)
      l when is_list(l) or is_map(l) -> reduce_while_positive(l, limit)
      _                              -> limit
    end
  end

  defp reduce_while_positive(enum, limit) do
    Enum.reduce_while(enum, limit, fn(e, l1) ->
      l2 = limit_minus_total_binary_size(e, l1)
      if l2 < 0, do: {:halt, l2}, else: {:cont, l2}
    end)
  end
end
