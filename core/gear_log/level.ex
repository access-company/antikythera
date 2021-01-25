# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.Level do
  alias Croma.Result, as: R
  use Croma.SubtypeOfAtom, values: [:debug, :info, :error]

  defun default() :: t do
    level_str = System.get_env("LOG_LEVEL") || "info"
    from_string(level_str)
  end

  defun from_string(level_str :: String.t()) :: t do
    new(level_str) |> R.get!()
  end

  defun write_to_log?(min_level :: t, message_level :: t) :: boolean do
    :info, :debug -> false
    :error, :debug -> false
    :error, :info -> false
    _, _ -> true
  end
end
