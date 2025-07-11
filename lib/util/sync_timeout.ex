# Copyright(c) 2015-2025 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.SyncTimeout do
  @moduledoc """
  Utility for running a function with timeout enforcement.

  This module provides a utility to execute a given function in a separate process with a timeout.
  If the function completes within the specified time, `{:ok, result}` is returned.
  If the function times out, the process exits, or if an exception or throw occurs within the function, `{:error, ...}` is returned.

  ## Arguments

  - `f` - The function to execute.
  - `timeout_ms` - Timeout in milliseconds.
  - `tag` - A tag to identify the error in case of timeout or exit.

  ## Return value

  - `{:ok, result}` - When the function finishes successfully within the timeout.
  - `{:error, tag}` - When the function times out or the process exits.
  - `{:error, {:exception, exception, stacktrace}}` - When the function raises an exception.
  - `{:error, {kind, reason}}` - When the function throws or exits with a reason.

  ## Example

      Antikythera.SyncTimeout.run(fn -> :timer.sleep(1000); :ok end, 500, :timeout)
      #=> {:error, :timeout}

      Antikythera.SyncTimeout.run(fn -> raise "fail" end, 1000)
      #=> {:error, {:exception, %RuntimeError{message: "fail"}, ...}}
  """

  defmodule TimeoutRunner do
    use GenServer

    # Starts the GenServer with given logger context (or empty map if undefined)
    defun start_link(context :: map | :undefined) :: {:ok, pid} | {:error, any} do
      GenServer.start_link(__MODULE__, context)
    end

    @impl GenServer
    def init(context) do
      {:ok, context}
    end

    @impl GenServer
    def handle_call({:run, f}, _from, context) do
      :logger.set_process_metadata(sanitize_context(context))

      try do
        {:reply, {:ok, f.()}, context}
      rescue
        e ->
          {:reply, {:error, {:exception, e, __STACKTRACE__}}, context}
      catch
        kind, reason ->
          {:reply, {:error, {kind, reason}}, context}
      end
    end

    @impl GenServer
    def handle_cast(:stop, state) do
      {:stop, :normal, state}
    end

    defp sanitize_context(:undefined), do: %{}
    defp sanitize_context(map), do: map
  end

  defun run(f :: (-> a), timeout_ms :: v[non_neg_integer], tag :: atom \\ :timeout) ::
          {:ok, a} | {:error, any}
        when a: any do
    if Process.get(:antikythera_sync_timeout_running) do
      {:error, :nested_sync_timeout}
    else
      Process.put(:antikythera_sync_timeout_running, true)

      try do
        context =
          case :logger.get_process_metadata() do
            :undefined -> %{}
            map -> map
          end

        {:ok, pid} = TimeoutRunner.start_link(context)

        result =
          try do
            case GenServer.call(pid, {:run, f}, timeout_ms) do
              {:ok, result} -> {:ok, result}
              {:error, err} -> {:error, err}
            end
          catch
            :exit, _ -> {:error, tag}
          end

        GenServer.cast(pid, :stop)
        result
      after
        Process.delete(:antikythera_sync_timeout_running)
      end
    end
  end
end
