# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication do
  @moduledoc """
  Template for gear application module.

  Invoking `use Antikythera.GearApplication` generates bunch of code, including (but not limited to)

  - `Application` callbacks
  - `Logger` module for the gear
  - accessors to gear config

  All gear implementations must have exactly one module that `use`s this module.

  For antikythera maintainers:
  Note that, when modifying the macros defined in `GearApplication` and `GearApplication.*`,
  we need to re-compile all gears in order to deploy the changes.
  """

  alias Supervisor.Spec
  alias Antikythera.{GearName, Conn}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.{MetricsUploader, ExecutorPool}
  alias AntikytheraCore.Alert.Manager, as: AlertManager
  alias AntikytheraCore.{GearManager, GearModule}
  alias AntikytheraCore.Config.Gear, as: GearConfig
  alias AntikytheraCore.GearLog.Writer

  @doc false
  defun start(gear_name :: v[GearName.t], children :: [Spec.spec]) :: {:ok, pid} do
    GearConfig.ensure_loaded(gear_name)
    all_children = predefined_children(gear_name) ++ children
    opts = [
      strategy: :one_for_one,
      name:     GearModule.root_supervisor_unsafe(gear_name),
    ]
    {:ok, pid} = Supervisor.start_link(all_children, opts)
    ExecutorPool.start_per_gear_executor_pool(gear_name)
    GearManager.gear_started(gear_name)
    {:ok, pid}
  end

  defunp predefined_children(gear_name :: v[GearName.t]) :: [Spec.spec] do
    # In many cases the process name atoms below are already generated (as module names) at compile-time in `__using__/1` macro.
    # However we don't assume that all these atoms actually exist and thus use unsafe functions,
    # in order to handle gears' beam files compiled with an older version of antikythera
    # where `__using__/1` didn't have all of the module generations.
    # Dynamic atom generations here are acceptable since the number of processes is limited.
    # Note: Required gear config should be read within `start_link/n` callbacks of each modules,
    # so that latest gear config is always used on restart.
    [
      Spec.worker(Writer         , [gear_name, GearModule.logger_unsafe(          gear_name)]),
      Spec.worker(MetricsUploader, [gear_name, GearModule.metrics_uploader_unsafe(gear_name)]),
      Spec.worker(AlertManager   , [gear_name, GearModule.alert_manager_unsafe(   gear_name)]),
    ]
  end

  @doc false
  defun stop(gear_name :: v[GearName.t]) :: :ok do
    GearManager.gear_stopped(gear_name)
    ExecutorPool.kill_executor_pool({:gear, gear_name})
  end

  @callback children()                            :: [Supervisor.Spec.spec]
  @callback executor_pool_for_web_request(Conn.t) :: EPoolId.t

  defmacro __using__(_) do
    quote do
      use Application
      @behaviour Antikythera.GearApplication

      @gear_name Mix.Project.config()[:app]

      def start(_type, _args) do
        Antikythera.GearApplication.start(@gear_name, children())
      end

      def stop(_state) do
        Antikythera.GearApplication.stop(@gear_name)
      end

      use Antikythera.GearApplication.ConfigGetter
      use Antikythera.GearApplication.ErrorHandler
      use Antikythera.GearApplication.Logger
      use Antikythera.GearApplication.G2g
      use Antikythera.GearApplication.MetricsUploader
      use Antikythera.GearApplication.AlertManager
    end
  end
end
