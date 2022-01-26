# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearExecutorPoolsManager do
  @moduledoc """
  Periodically polls gears' executor pool settings and apply changes.

  Settings of gear executor pools are embedded in antikythera core config.
  Loading core config file and caching into ETS is done by `CoreConfigPoller`; this `GenServer` watches for the cache.
  """

  use GenServer
  alias Antikythera.{MapUtil, GearName}
  alias AntikytheraCore.ExecutorPool
  alias ExecutorPool.Setting, as: EPoolSetting

  @interval 300_000

  @typep settings :: %{GearName.t() => EPoolSetting.t()}
  @typep state :: %{gear_epool_settings: settings}

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    settings = EPoolSetting.all()
    {:ok, %{gear_epool_settings: settings}, @interval}
  end

  @impl true
  def handle_info(:timeout, state) do
    new_state = handle_changes(state)
    {:noreply, new_state, @interval}
  end

  defunp handle_changes(%{gear_epool_settings: old_settings} = s :: state) :: state do
    new_settings = EPoolSetting.all()
    {old_only, common_key_diff, new_only} = MapUtil.difference(old_settings, new_settings)
    revert_to_default_settings(old_only)
    update_existing_epool_settings(common_key_diff)
    set_newly_added_epool_settings(new_only)
    %{s | gear_epool_settings: new_settings}
  end

  defunp revert_to_default_settings(old_only :: settings) :: :ok do
    default_setting = EPoolSetting.default()

    Enum.each(old_only, fn {gear_name, _} ->
      ExecutorPool.apply_setting({:gear, gear_name}, default_setting)
    end)
  end

  defunp update_existing_epool_settings(
           common_key_diff :: %{GearName.t() => {EPoolSetting.t(), EPoolSetting.t()}}
         ) :: :ok do
    Enum.each(common_key_diff, fn {gear_name, {_old_setting, new_setting}} ->
      ExecutorPool.apply_setting({:gear, gear_name}, new_setting)
    end)
  end

  defunp set_newly_added_epool_settings(new_only :: settings) :: :ok do
    Enum.each(new_only, fn {gear_name, new_setting} ->
      ExecutorPool.apply_setting({:gear, gear_name}, new_setting)
    end)
  end
end
