# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearManager do
  @moduledoc """
  A `GenServer` to keep track of names of currently running gears.
  """

  use GenServer
  alias Antikythera.GearName
  require AntikytheraCore.Logger, as: L

  @typep state_t :: %{GearName.t => nil}

  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:all_gear_names, _from, state) do
    {:reply, Map.keys(state), state}
  end

  @impl true
  def handle_cast({:gear_started, gear_name}, state) do
    L.info("gear started: #{gear_name}")
    new_state = Map.put(state, gear_name, nil)
    update_routing(new_state)
    {:noreply, new_state}
  end
  def handle_cast({:gear_stopped, gear_name}, state) do
    L.info("gear stopped: #{gear_name}")
    new_state = Map.delete(state, gear_name)
    update_routing(new_state)
    {:noreply, new_state}
  end

  defunp update_routing(state :: state_t) :: :ok do
    # delegate the task to StartupManager to avoid deadlock
    AntikytheraCore.StartupManager.update_routing(Map.keys(state))
  end

  #
  # Public API
  #
  defun running_gear_names() :: [GearName.t] do
    GenServer.call(__MODULE__, :all_gear_names)
  end

  defun gear_started(gear_name :: v[GearName.t]) :: :ok do
    GenServer.cast(__MODULE__, {:gear_started, gear_name})
  end

  defun gear_stopped(gear_name :: v[GearName.t]) :: :ok do
    GenServer.cast(__MODULE__, {:gear_stopped, gear_name})
  end
end
