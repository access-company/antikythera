# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.AsyncJobLog.Writer do
  @moduledoc """
  A `GenServer` for logging, which is used in `AntikytheraCore.ExecutorPool.AsyncJobRunner`.
  """

  use GenServer
  alias Antikythera.{Time, ContextId}
  alias AntikytheraCore.GearLog.LogRotation

  @rotate_interval 24 * 60 * 60 * 1000

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  @impl true
  def init([]) do
    log_file_path = AntikytheraCore.Path.core_log_file_path("async_job")
    state = LogRotation.init(@rotate_interval, log_file_path, write_to_terminal: false)
    {:ok, state}
  end

  @impl true
  def handle_cast(message, state) do
    log = {Time.now(), :info, ContextId.system_context(), message}
    {:noreply, LogRotation.write_log(state, log)}
  end

  @impl true
  def handle_info(:rotate, state) do
    {:noreply, LogRotation.rotate(state)}
  end

  @impl true
  def terminate(_reason, state) do
    LogRotation.terminate(state)
  end

  def info(message) do
    GenServer.cast(__MODULE__, message)
  end
end
