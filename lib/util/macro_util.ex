# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.MacroUtil do
  @moduledoc """
  Utilities to manipulate Elixir AST.
  """

  defun prewalk_accumulate(q :: Macro.t(), acc :: any, f :: (Macro.t(), any -> any)) :: any do
    Macro.prewalk(q, acc, fn t, acc -> {t, f.(t, acc)} end)
    |> elem(1)
  end
end
