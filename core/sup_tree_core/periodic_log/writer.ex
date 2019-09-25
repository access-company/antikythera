# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.PeriodicLog.Writer do
  @moduledoc """
  A `GenServer` that logs periodically
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
      build_mod:   Croma.Atom,
      build_state: Croma.Any,
    ]
  end

  def start_link([mod | _] = args) do
    GenServer.start_link(__MODULE__, args, [name: mod])
  end

  @impl true
  def init([build_mod, file_name | opts]) do
    write_to_terminal? = Keyword.get(opts, :write_to_terminal, false)
    handle = FileHandle.open(AntikytheraCore.Path.core_log_file_path(file_name), write_to_terminal: write_to_terminal?)
    timer = arrange_next_rotation(nil)
    build_state = build_mod.init()
    {:ok, %State{file_handle: handle, empty?: true, timer: timer, build_mod: build_mod, build_state: build_state}, @interval}
  end

  @impl true
  def handle_info(:timeout, %State{file_handle: handle, timer: timer, build_mod: build_mod, build_state: build_state} = state) do
    {message, next_state} = build_mod.build_log(build_state)
    if message != nil do
      msg = {Time.now(), :info, ContextId.system_context(), message}
      case FileHandle.write(handle, msg) do
        {:kept_open, new_handle} -> {:noreply, %State{state | file_handle: new_handle, empty?: false, build_state: next_state}, @interval}
        {:rotated  , new_handle} ->
          # Log file is just rotated as its size has exceeded the upper limit.
          # Note that the current message is written to the newly-opened log file and thus it's not empty.
          new_timer = arrange_next_rotation(timer)
          {:noreply, %State{state | file_handle: new_handle, empty?: false, timer: new_timer, build_state: next_state}, @interval}
      end
    else
      {:noreply, %State{state | build_state: next_state}, @interval}
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
end

