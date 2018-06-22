# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

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

  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    {:ok, %{queue: :queue.new(), task_pid: nil}}
  end

  @impl true
  def handle_cast(message, state) do
    new_state = enqueue_message(state, message) |> run_task_if_possible()
    {:noreply, new_state}
  end

  defp enqueue_message(%{queue: q} = state, message) do
    %{state | queue: :queue.in(message, q)}
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, _reason}, %{task_pid: pid} = state) do
    new_state = Map.put(state, :task_pid, nil) |> run_task_if_possible()
    {:noreply, new_state}
  end

  defp run_task_if_possible(%{queue: q, task_pid: pid} = state) do
    if pid == nil do
      case :queue.out(q) do
        {{:value, message}, new_queue} -> %{queue: new_queue, task_pid: run_task(message)}
        {:empty           , _        } -> state
      end
    else
      state
    end
  end

  defp run_task({:gear_updated, gear_name}) do
    {pid, _ref} = spawn_monitor(Version.Gear, :install_or_upgrade_to_next_version, [gear_name])
    pid
  end
  defp run_task(:core_updated) do
    {pid, _ref} = spawn_monitor(Version.Core, :upgrade_to_next_version, [])
    pid
  end

  #
  # Public API
  #
  defun gear_updated(gear_name :: v[GearName.t]) :: :ok do
    :ok = GenServer.cast(__MODULE__, {:gear_updated, gear_name})
  end

  defun core_updated() :: :ok do
    :ok = GenServer.cast(__MODULE__, :core_updated)
  end
end
