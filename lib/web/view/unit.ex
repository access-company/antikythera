# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.View.Unit do
  @moduledoc """
  Functions to convert numeric values into human-readable strings.
  """

  defun bytes(n :: v[integer]) :: String.t do
    cond do
      n <             1_000 -> "#{n} B"
      n <         1_000_000 -> "#{round_to_significant_digits(n /             1_000)} KB"
      n <     1_000_000_000 -> "#{round_to_significant_digits(n /         1_000_000)} MB"
      n < 1_000_000_000_000 -> "#{round_to_significant_digits(n /     1_000_000_000)} GB"
      true                  -> "#{round_to_significant_digits(n / 1_000_000_000_000)} TB"
    end
  end

  defp round_to_significant_digits(f) do
    if f < 10 do
      Float.round(f, 1)
    else
      Float.round(f, 0) |> trunc()
    end
  end
end
