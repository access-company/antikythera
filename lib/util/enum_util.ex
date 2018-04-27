# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.EnumUtil do
  @moduledoc """
  Utility functions to work with enumerables.
  """

  @type context :: any
  @type item :: any

  @doc """
  Updates items of an enumerable with the given function, depending on context.
  Context can be `any`.

  The function `fun` takes item and context as arguments, and must achieve 2 purposes:

  1. Update an item according to current context
  2. Produces new context for next item

  then, return both as tuple `{new_item, new_context}`.
  """
  defun map_with_context(e :: Enum.t, c :: context, fun :: (item, context -> {item, context})) :: [item] do
    Enum.map_reduce(e, c, fun) |> elem(0)
  end
end
