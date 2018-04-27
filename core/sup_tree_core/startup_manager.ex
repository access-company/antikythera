# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.StartupManager do
  @moduledoc """
  Manages progress of startup procedure of antikythera.

  Most of initialization steps are done within `AntikytheraCore.start/2`.
  However, the following step is not done in `AntikytheraCore.start/2` and delayed:

  - Installing gears:
    Starting a gear requires that the antikythera instance (as an OTP application) has started;
    this step is delegated to `VersionSynchronizer`.

  This `GenServer` waits for the above procedures to complete and then changes the cowboy routing rules
  so that the current node can receive web requests from its upstream load balancer.
  """

  use GenServer
  alias Antikythera.GearName
  alias AntikytheraCore.GearManager
  alias AntikytheraCore.Handler.CowboyRouting
  require AntikytheraCore.Logger, as: L

  @typep step  :: :all_gears_installed
  @typep state :: %{step => boolean}

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    {:ok, %{all_gears_installed: false}}
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, all_initialization_steps_finished?(state), state}
  end

  @impl true
  def handle_cast({:update_routing, gear_names}, state) do
    CowboyRouting.update_routing(gear_names, all_initialization_steps_finished?(state))
    {:noreply, state}
  end
  def handle_cast(:all_gears_installed, state) do
    handle_completion_notice(:all_gears_installed, state)
  end

  defunp handle_completion_notice(completed_step :: v[atom], old_state :: state) :: {:noreply, state} do
    L.info("received #{completed_step}")
    new_state = Map.put(old_state, completed_step, true)
    if !all_initialization_steps_finished?(old_state) and all_initialization_steps_finished?(new_state) do
      CowboyRouting.update_routing(GearManager.running_gear_names(), true)
    end
    {:noreply, new_state}
  end

  defunp all_initialization_steps_finished?(state :: state) :: boolean do
    Enum.all?(Map.values(state))
  end

  #
  # Public API
  #
  defun initialized?() :: boolean do
    GenServer.call(__MODULE__, :initialized?)
  end

  defun update_routing(gear_names :: [GearName.t]) :: :ok do
    GenServer.cast(__MODULE__, {:update_routing, gear_names})
  end

  defun all_gears_installed() :: :ok do
    GenServer.cast(__MODULE__, :all_gears_installed)
  end
end
