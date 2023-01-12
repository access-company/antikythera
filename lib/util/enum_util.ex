# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.EnumUtil do
  @moduledoc """
  Utility functions to work with enumerables.
  """

  @type context :: any
  @type element :: Enum.element()

  @not_found_error_msg "no matching element found"

  @doc """
  Updates items of an enumerable with the given function, depending on context.
  Context can be `any`.

  The function `fun` takes item and context as arguments, and must achieve 2 purposes:

  1. Update an item according to current context
  2. Produces new context for next item

  then, return both as tuple `{new_item, new_context}`.
  """
  defun map_with_context(
          e :: Enum.t(),
          c :: context,
          fun :: (element, context -> {element, context})
        ) :: [element] do
    Enum.map_reduce(e, c, fun) |> elem(0)
  end

  @doc """
  A variant of `Enum.find/2` that raises an exception when no matching element is found.
  """
  defun find!(e :: Enum.t(), fun :: (element -> any)) :: element do
    Enum.find(e, fun) || raise @not_found_error_msg
  end

  @doc """
  A variant of `Enum.find_value/2` that raises an exception when no matching element is found.
  """
  defun find_value!(e :: Enum.t(), fun :: (element -> any)) :: any do
    Enum.find_value(e, fun) || raise @not_found_error_msg
  end
end
