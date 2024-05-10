# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.LogRotation do
  @moduledoc """
  A Module to write and rotate a log file using `AntikytheraCore.GearLog.FileHandle`.
  """

  alias AntikytheraCore.GearLog.{FileHandle, Message}

  defmodule State do
    use Croma.Struct,
      fields: [
        # FileHandle.t
        file_handle: Croma.Tuple,
        empty?: Croma.Boolean,
        timer: Croma.Reference,
        interval: Croma.NonNegInteger
      ]
  end

  defun init(interval :: v[non_neg_integer], file_path :: Path.t(), opts :: Keyword.t() \\ []) ::
          State.t() do
    handle = FileHandle.open(file_path, opts)
    timer = arrange_next_rotation(nil, interval)
    %State{file_handle: handle, empty?: true, timer: timer, interval: interval}
  end

  defun write_log(
          %State{file_handle: handle, timer: timer, interval: interval} = state,
          log :: Message.t()
        ) :: State.t() do
    case FileHandle.write(handle, log) do
      {:kept_open, new_handle} ->
        %State{state | file_handle: new_handle, empty?: false}

      {:rotated, new_handle} ->
        # Log file is just rotated as its size has exceeded the upper limit.
        # Note that the current message is written to the newly-opened log file and thus it's not empty.
        new_timer = arrange_next_rotation(timer, interval)
        %State{state | file_handle: new_handle, empty?: false, timer: new_timer}
    end
  end

  defun set_write_to_terminal(%State{file_handle: handle} = state, new_val :: boolean) ::
          State.t() do
    %State{state | file_handle: FileHandle.set_write_to_terminal(handle, new_val)}
  end

  defun restore_write_to_terminal(%State{file_handle: handle} = state) :: State.t() do
    %State{state | file_handle: FileHandle.restore_write_to_terminal(handle)}
  end

  defun rotate(
          %State{file_handle: handle, empty?: empty?, timer: timer, interval: interval} = state
        ) :: State.t() do
    new_timer = arrange_next_rotation(timer, interval)
    next_state = %State{state | timer: new_timer}

    if empty? do
      next_state
    else
      %State{next_state | file_handle: FileHandle.rotate(handle), empty?: true}
    end
  end

  defun terminate(%State{file_handle: handle}) :: :ok do
    FileHandle.close(handle)
  end

  defp arrange_next_rotation(timer, interval) do
    if timer do
      Process.cancel_timer(timer)
    end

    Process.send_after(self(), :rotate, interval)
  end
end
