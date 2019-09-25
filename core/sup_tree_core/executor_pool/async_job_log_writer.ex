# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.AsyncJobLogWriter do
  @moduledoc """
  A `GenServer` for logging, which is used in `AntikytheraCore.ExecutorPool.AsyncJobRunner`.
  """

  use AntikytheraCore.LogWriter, [rotate_interval: 24 * 3_600_000]
  alias Antikythera.{Time, ContextId}

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
  def handle_cast(message, state) do
    log = {Time.now(), :info, ContextId.system_context(), message}
    new_state = write_log(state, log)
    {:noreply, new_state}
  end

  def info(message) do
    GenServer.cast(__MODULE__, message)
  end
end
