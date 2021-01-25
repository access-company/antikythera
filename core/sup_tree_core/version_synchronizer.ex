# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.VersionSynchronizer do
  @moduledoc """
  A `GenServer` which periodically polls deployable versions of antikythera instance and gears.

  On startup of antikythera, this `GenServer` waits for completion of `AntikytheraCore.start/2`,
  installs all available gears, notifies to `StartupManager`, and then starts periodic polling.
  Depends on `StartupManager` and `VersionUpgradeTaskQueue`.
  """

  use GenServer
  alias Antikythera.Env
  alias AntikytheraCore.{Version, FileSetup, VersionUpgradeTaskQueue, StartupManager}
  alias AntikytheraCore.Version.History

  @start_wait_interval 500
  @version_monitor_interval if Antikythera.Env.compile_env() == :local, do: 3_000, else: 120_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    {:ok, %{instance_started?: false, last_checked_at: 0}, @start_wait_interval}
  end

  @impl true
  def handle_info(:timeout, state1) do
    state2 = check_updates(state1)

    timeout =
      if state2.instance_started?, do: @version_monitor_interval, else: @start_wait_interval

    {:noreply, state2, timeout}
  end

  defp check_updates(%{instance_started?: started?, last_checked_at: last_checked_at} = state) do
    if started? do
      checked_at = System.system_time(:second)
      check_and_notify_code_update(last_checked_at)
      %{state | last_checked_at: checked_at}
    else
      case Application.started_applications()
           |> List.keyfind(Env.antikythera_instance_name(), 0) do
        nil ->
          state

        {_name, _desc, version_charlist} ->
          FileSetup.write_initial_antikythera_instance_version_to_history_if_non_cloud(
            version_charlist
          )

          install_gears()
          %{state | instance_started?: true}
      end
    end
  end

  defp install_gears() do
    :ok = Version.Gear.install_gears_at_startup(History.all_deployable_gear_names())
    StartupManager.all_gears_installed()
  end

  defp check_and_notify_code_update(last_checked_at) do
    {instance_history_changed?, gear_names} =
      History.find_all_modified_history_files(last_checked_at)

    if instance_history_changed? do
      VersionUpgradeTaskQueue.core_updated()
    end

    Enum.each(gear_names, &VersionUpgradeTaskQueue.gear_updated/1)
  end
end
