# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.LogWriter do
  @moduledoc """
  Module to be `use`d by modules that writes log messages using `AntikytheraCore.GearLog.FileHandle`.

  `__using__/1` of this module receives the following key in its argument.

  - (required) `:rotate_interval`         : Interval of log rotation in milliseconds
  - (optional) `:additional_state_fields` : Additional fields of `GenServer`'s state
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @rotate_interval Keyword.fetch!(opts, :rotate_interval)

      use GenServer
      alias AntikytheraCore.GearLog.{FileHandle, Message}

      defmodule State do
        use Croma.Struct, recursive_new?: true, fields: [
          file_handle: Croma.Tuple, # FileHandle.t
          empty?:      Croma.Boolean,
          timer:       Croma.Reference,
        ] ++ Keyword.get(opts, :additional_state_fields, [])
      end

      @impl true
      def handle_info(:rotate, state) do
        {:noreply, rotate(state)}
      end

      @impl true
      def terminate(_reason, %State{file_handle: handle}) do
        FileHandle.close(handle)
      end

      defunp write_log(%State{file_handle: handle, timer: timer} = state, log :: Message.t) :: State.t do
        case FileHandle.write(handle, log) do
          {:kept_open, new_handle} -> %State{state | file_handle: new_handle, empty?: false}
          {:rotated  , new_handle} ->
            # Log file is just rotated as its size has exceeded the upper limit.
            # Note that the current message is written to the newly-opened log file and thus it's not empty.
            new_timer = arrange_next_rotation(timer)
            %State{state | file_handle: new_handle, empty?: false, timer: new_timer}
        end
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

      defp arrange_next_rotation(timer) do
        if timer do
          Process.cancel_timer(timer)
        end
        Process.send_after(self(), :rotate, @rotate_interval)
      end
    end
  end
end
