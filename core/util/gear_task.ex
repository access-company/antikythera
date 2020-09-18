# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearTask do
  @moduledoc """
  A much simplified version of `Task` module defined in the elixir standard library.

  While the standard `Task` requires the invoker to trap exit in order to handle errors (as it uses `spawn_link`),
  this module doesn't link the invoker with the worker (uses `spawn_monitor` instead).
  Also this version does not send stacktrace to error_logger (since it doesn't use :proc_lib functions to start child process).
  """

  alias Antikythera.ErrorReason
  alias AntikytheraCore.GearProcess

  @type mod_fun_args :: {module, atom, [any]}

  defun exec_wait(
          mfa :: mod_fun_args,
          timeout :: v[non_neg_integer],
          success_fun :: (a -> r),
          failure_fun :: (ErrorReason.t(), ErrorReason.stacktrace() -> r)
        ) :: r
        when a: any, r: any do
    {pid, monitor_ref} = GearProcess.spawn_monitor(__MODULE__, :worker_run, [mfa])

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        case reason do
          {:shutdown, {:ok, a}} -> success_fun.(a)
          {:shutdown, {:error, e, stacktrace}} -> failure_fun.(e, stacktrace)
          _otherwise -> failure_fun.({:exit, reason}, [])
        end
    after
      timeout ->
        Process.demonitor(monitor_ref, [:flush])
        Process.exit(pid, :kill)
        failure_fun.(:timeout, [])
    end
  end

  @doc false
  def worker_run({m, f, as}) do
    result =
      try do
        {:ok, apply(m, f, as)}
      catch
        :error, e -> {:error, {:error, e}, System.stacktrace()}
        :throw, value -> {:error, {:throw, value}, System.stacktrace()}
        :exit, reason -> {:error, {:exit, reason}, System.stacktrace()}
      end

    exit({:shutdown, result})
  end
end
