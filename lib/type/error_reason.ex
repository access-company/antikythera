# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ErrorReason do
  @moduledoc """
  Type module for error that describes what went wrong during a process execution.

  Possible values for `t:t/0` are:

  - `{:error, Exception.t}` : An exception was thrown and was not handled.
  - `:timeout`              : Execution timed out.
  - `:killed`               : Process was brutally killed, typically due to heap limit violation.
  - `{:throw, any}`         : A value was thrown but not caught.
  - `{:exit, any}`          : Process exited before completing the execution.
  """

  @type t :: {:error, Exception.t()} | {:throw, any} | {:exit, any} | :timeout | :killed

  defun valid?(t :: term) :: boolean do
    {:error, %{__exception__: _}} -> true
    {:throw, _} -> true
    {:exit, _} -> true
    :timeout -> true
    :killed -> true
    _ -> false
  end

  @type gear_action_error_reason :: t | :timeout_in_epool_checkout

  @type stack_item :: {module, atom, arity | [any], [{:file, charlist} | {:line, pos_integer}]}
  @type stacktrace :: [stack_item]

  defun format(reason :: gear_action_error_reason, stacktrace :: stacktrace) :: String.t() do
    {kind, value}, stacktrace -> Exception.format(kind, value, stacktrace)
    reason_atom, _ -> "** #{reason_atom}"
  end
end
