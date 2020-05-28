# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearConfigPoller do
  @moduledoc """
  Periodically polls changes in gear configs.

  Gear configs are persisted in a shared data storage (e.g. NFS) and are cached in ETS in each erlang node.
  Note that gear configs are loaded (cached into ETS) at each step of

  - `AntikytheraCore.start/2`: all existing gear configs are loaded
  - each gear's `start/2`: the gear's gear config is loaded

  Thus this GenServer's responsibility is just to keep up with changes in the shared data storage.

  Depends on `AntikytheraCore.GearManager` (when applying changes in gear configs results in update of cowboy routing).
  """

  use GenServer
  alias AntikytheraCore.Config.Gear, as: GearConfig

  @interval 120_000

  @typep state_t :: %{last_checked_at: pos_integer}

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:ok, %{last_checked_at: 0}, @interval}
  end

  @impl true
  def handle_cast(:reload, state) do
    handle_gear_config_loading(state)
  end

  @impl true
  def handle_info(:timeout, state) do
    handle_gear_config_loading(state)
  end

  defunp handle_gear_config_loading(state :: state_t) :: {:noreply, state_t, timeout} do
    checked_at = System.system_time(:second)
    GearConfig.load_all(state[:last_checked_at])
    {:noreply, %{state | last_checked_at: checked_at}, @interval}
  end
end
