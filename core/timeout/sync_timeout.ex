defmodule Acs.SyncTimeout do
  use Croma

  @type tag_t :: any
  @type timeout_ms_t :: non_neg_integer
  @type f_t :: (... -> any)
  defun run(f :: f_t, timeout_ms :: timeout_ms_t, tag :: tag_t) :: {:ok, any} | {:error, tag_t} do
    context =
      case :logger.get_process_metadata() do
        :undefined -> %{}
        map -> map
      end

    {:ok, pid} = Acs.TimeoutRunner.start_link(context)

    ret =
      try do
        {:ok, GenServer.call(pid, {:run, f}, timeout_ms)}
      catch
        :exit, _ -> {:error, tag}
      end

    GenServer.cast(pid, :stop)
    ret
  end
end
