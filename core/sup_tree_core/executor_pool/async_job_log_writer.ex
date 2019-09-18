# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.AsyncJobLogWriter do
  @moduledoc """
  A `GenServer` for logging, which is used in `AntikytheraCore.ExecutorPool.AsyncJobRunner`.
  """

  use GenServer
  alias AntikytheraCore.GearLog.FileHandle
  alias Antikythera.{Time, ContextId}

  @rotate_interval 24 * 3_600_000

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
    handle = FileHandle.open(AntikytheraCore.Path.core_log_file_path("async_job"), write_to_terminal: false)
    timer = arrange_next_rotation(nil)
    {:ok, %State{file_handle: handle, empty?: true, timer: timer}}
  end

  @impl true
  def handle_cast(message, %State{file_handle: handle, timer: timer} = state) do
    log = {Time.now(), :info, ContextId.system_context(), message}
    case FileHandle.write(handle, log) do
      {:kept_open, new_handle} -> {:noreply, %State{state | file_handle: new_handle, empty?: false}}
      {:rotated  , new_handle} ->
        # Log file is just rotated as its size has exceeded the upper limit.
        # Note that the current message is written to the newly-opened log file and thus it's not empty.
        new_timer = arrange_next_rotation(timer)
        {:noreply, %State{state | file_handle: new_handle, empty?: false, timer: new_timer}}
    end
  end

  @impl true
  def handle_info(:rotate, state) do
    {:noreply, rotate(state)}
  end

  defp rotate(%State{file_handle: handle, empty?: empty?, timer: timer} = state) do
    new_timer = arrange_next_rotation(timer)
    new_state = %State{state | timer: new_timer}
    if empty? do
      new_state
    else
      %State{new_state | file_handle: FileHandle.rotate(handle), empty?: true}
    end
  end

  @impl true
  def terminate(_reason, %State{file_handle: handle}) do
    FileHandle.close(handle)
  end

  defp arrange_next_rotation(timer) do
    unless is_nil(timer) do
      Process.cancel_timer(timer)
    end
    Process.send_after(self(), :rotate, @rotate_interval)
  end

  def info(message) do
    GenServer.cast(__MODULE__, message)
  end
end
