# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.VersionUpgradeTaskQueue do
  @moduledoc """
  A `GenServer` to serialize tasks to "upgrade of antikythera instance" and "installation or upgrade of gears".

  This is implemented as a `GenServer` for the purpose of preventing multiple install/upgrade from running concurrently.
  As each installation/upgrade can take much longer than 5-seconds timeout of system messages,
  the actual task is delegated to one-off processes.
  """

  use GenServer
  alias Antikythera.GearName
  alias AntikytheraCore.Version
  require AntikytheraCore.Logger, as: L

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:ok, %{queue: :queue.new(), task_pid: nil, enabled?: true}}
  end

  @impl true
  def handle_cast(message, state) do
    new_state =
      case message do
        {:upgrade, instruction} ->
          enqueue_instruction(state, instruction) |> run_task_if_possible()

        {:set_enabled, enabled?} ->
          set_enabled(state, enabled?)
      end

    {:noreply, new_state}
  end

  defp enqueue_instruction(%{queue: q} = state, instruction) do
    %{state | queue: :queue.in(instruction, q)}
  end

  defp set_enabled(state, enabled?) do
    case {state.enabled?, enabled?} do
      {true, false} -> L.info("upgrade processing is turned off")
      {false, true} -> L.info("upgrade processing is turned on")
      _ -> :ok
    end

    %{state | enabled?: enabled?}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, %{task_pid: pid} = state) do
    new_state = Map.put(state, :task_pid, nil) |> run_task_if_possible()
    {:noreply, new_state}
  end

  defp run_task_if_possible(%{queue: q, task_pid: pid, enabled?: enabled?} = state) do
    if pid == nil and enabled? do
      case :queue.out(q) do
        {{:value, instruction}, new_queue} ->
          %{state | queue: new_queue, task_pid: run_task(instruction)}

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp run_task({:gear, gear_name}) do
    {pid, _ref} = spawn_monitor(Version.Gear, :install_or_upgrade_to_next_version, [gear_name])
    pid
  end

  defp run_task(:core) do
    {pid, _ref} = spawn_monitor(Version.Core, :upgrade_to_next_version, [])
    pid
  end

  #
  # Public API
  #
  defun gear_updated(gear_name :: v[GearName.t()]) :: :ok do
    GenServer.cast(__MODULE__, {:upgrade, {:gear, gear_name}})
  end

  defun core_updated() :: :ok do
    GenServer.cast(__MODULE__, {:upgrade, :core})
  end

  defun enable() :: :ok do
    GenServer.cast(__MODULE__, {:set_enabled, true})
  end

  defun disable() :: :ok do
    GenServer.cast(__MODULE__, {:set_enabled, false})
  end
end
