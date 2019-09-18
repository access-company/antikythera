# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.MessageLogWriter do
  @moduledoc """
  A `GenServer` that logs processes with many messages in mailbox.
  """

  use GenServer
  alias AntikytheraCore.GearLog.FileHandle
  alias Antikythera.{Time, ContextId}

  @interval        1000
  @rotate_interval 7_200_000

  defmodule State do
    use Croma.Struct, recursive_new?: true, fields: [
      file_handle: Croma.Tuple, # FileHandle.t
      empty?:      Croma.Boolean,
      timer:       Croma.Reference,
    ]
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  @impl true
  def init([]) do
    handle = FileHandle.open(AntikytheraCore.Path.core_log_file_path("messages"), write_to_terminal: false)
    timer = arrange_next_rotation(nil)
    {:ok, %State{file_handle: handle, empty?: true, timer: timer}, @interval}
  end

  @impl true
  def handle_info(:timeout, %State{file_handle: handle, timer: timer} = state) do
    message = build_log()
    if message != nil do
      msg = {Time.now(), :info, ContextId.system_context(), message}
      case FileHandle.write(handle, msg) do
        {:kept_open, new_handle} -> {:noreply, %State{state | file_handle: new_handle, empty?: false}, @interval}
        {:rotated  , new_handle} ->
          # Log file is just rotated as its size has exceeded the upper limit.
          # Note that the current message is written to the newly-opened log file and thus it's not empty.
          new_timer = arrange_next_rotation(timer)
          {:noreply, %State{state | file_handle: new_handle, empty?: false, timer: new_timer}, @interval}
      end
    else
      {:noreply, state, @interval}
    end
  end
  def handle_info(:rotate, state) do
    {:noreply, rotate(state), @interval}
  end

  defp rotate(%State{file_handle: handle, empty?: empty?, timer: timer} = state0) do
    new_timer = arrange_next_rotation(timer)
    state1 = %State{state0 | timer: new_timer}
    if empty? do
      state1
    else
      %State{state1 | file_handle: FileHandle.rotate(handle), empty?: true}
    end
  end

  @impl true
  def terminate(_reason, %State{file_handle: handle}) do
    FileHandle.close(handle)
  end

  defp arrange_next_rotation(timer) do
    if timer != nil do
      Process.cancel_timer(timer)
    end
    Process.send_after(self(), :rotate, @rotate_interval)
  end

  defp build_log() do
    procs =
      :recon.proc_count(:message_queue_len, 5)
      |> Enum.filter(fn({_pid, qlen, _info}) -> qlen >= 100 end)
    if procs != [] do
      log_time = Antikythera.Time.to_iso_timestamp(Antikythera.Time.now())
      procs
      |> Enum.reduce(log_time, fn({pid, qlen, info}, acc) ->
        acc2 = acc <> "\n" <> Integer.to_string(qlen) <> " " <> inspect(info)
        Process.info(pid)
        |> Keyword.get(:messages)
        |> Enum.take(10)
        |> Enum.reduce(acc2, fn(msg, acc) -> acc <> "\n\t" <> inspect(msg) end)
      end)
    else
      nil
    end
  end
end
