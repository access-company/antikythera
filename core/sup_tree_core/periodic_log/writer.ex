# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.PeriodicLog.Writer do
  @moduledoc """
  A `GenServer` that logs periodically
  """

  use GenServer
  alias Antikythera.ContextId
  alias AntikytheraCore.GearLog
  alias AntikytheraCore.GearLog.LogRotation

  @interval 1000
  @rotate_interval 2 * 60 * 60 * 1000

  defmodule State do
    use Croma.Struct,
      fields: [
        log_state: LogRotation.State,
        build_mod: Croma.Atom,
        build_state: Croma.Any
      ]
  end

  def start_link([mod | _] = args) do
    GenServer.start_link(__MODULE__, args, name: mod)
  end

  @impl true
  def init([build_mod, file_name | opts]) do
    write_to_terminal? = Keyword.get(opts, :write_to_terminal, false)
    log_file_path = AntikytheraCore.Path.core_log_file_path(file_name)

    log_state =
      LogRotation.init(@rotate_interval, log_file_path, write_to_terminal: write_to_terminal?)

    build_state = build_mod.init()
    {:ok, %State{log_state: log_state, build_mod: build_mod, build_state: build_state}, @interval}
  end

  @impl true
  def handle_info(
        :timeout,
        %State{log_state: log_state, build_mod: build_mod, build_state: build_state} = state
      ) do
    {message, next_build_state} = build_mod.build_log(build_state)

    next_state =
      if is_nil(message) do
        %State{state | build_state: next_build_state}
      else
        log = {GearLog.Time.now(), :info, ContextId.system_context(), message}
        next_log_state = LogRotation.write_log(log_state, log)
        %State{state | log_state: next_log_state, build_state: next_build_state}
      end

    {:noreply, next_state, @interval}
  end

  def handle_info(:rotate, %State{log_state: log_state} = state) do
    next_log_state = LogRotation.rotate(log_state)
    {:noreply, %State{state | log_state: next_log_state}, @interval}
  end

  @impl true
  def terminate(_reason, %State{log_state: log_state}) do
    LogRotation.terminate(log_state)
  end
end
