# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.Manager do
  @moduledoc """
  An event manager hosting multiple `AntikytheraCore.Alert.Handler`s.

  Managers are spawned per OTP application (antikythera and each gear).
  Each handler has its own buffer to store messages before sending them as an alert.
  """

  alias Antikythera.{GearName, Time}
  require AntikytheraCore.Logger, as: L
  alias AntikytheraCore.GearModule
  alias AntikytheraCore.Alert.Handler, as: AHandler
  alias AntikytheraCore.Alert.{HandlerConfigsMap, ErrorCountReporter}

  @handler_module_prefix "AntikytheraCore.Alert.Handler."

  def child_spec(args) do
    %{
      id:    __MODULE__,
      start: {__MODULE__, :start_link, [args]},
    }
  end

  def start_link([otp_app_name, name_to_register]) do
    {:ok, pid} = :gen_event.start_link({:local, name_to_register})
    update_handler_installations(otp_app_name, HandlerConfigsMap.get(otp_app_name))
    {:ok, pid}
  end

  @doc """
  Update handler installations according to alert config of an OTP application (antikythera or gear).
  Handlers will be installed/uninstalled depending on contents of the config.
  If the config has sufficient information for a handler, it will be installed (noop if already installed).
  Otherwise, it will not be installed and will be uninstalled if it is already installed.

  Any errors will be logged but this function always returns `:ok`.
  """
  defun update_handler_installations(otp_app_name :: v[:antikythera | GearName.t], configs_map :: v[HandlerConfigsMap.t]) :: :ok do
    case manager(otp_app_name) do
      nil -> L.info("Alert manager process for '#{otp_app_name}' is not running!") # log as info since this will always happen on initial loading of gear configs (before gear installations)
      pid -> update_handler_installations_impl(pid, otp_app_name, configs_map)
    end
  end

  defp update_handler_installations_impl(manager, otp_app_name, configs_map) do
    installed_handlers  = :gen_event.which_handlers(manager)
    handlers_to_install = handlers_to_install(configs_map)
    to_remove = installed_handlers  -- handlers_to_install
    to_add    = handlers_to_install -- installed_handlers
    remove_results = Enum.map(to_remove, fn handler -> :gen_event.delete_handler(manager, handler, :remove_handler) end)
    add_results    = Enum.map(to_add   , fn handler -> :gen_event.add_handler(manager, handler, handler_init_arg(otp_app_name, handler)) end)
    case Enum.reject(remove_results ++ add_results, &(&1 == :ok)) do
      []     -> :ok
      errors ->
        reasons = Enum.map(errors, fn {:error, reason} -> reason end)
        L.error("Failed to install some alert handler(s) for '#{otp_app_name}':\n#{inspect(reasons)}")
        :ok
    end
  end

  defunp handlers_to_install(configs_map :: v[HandlerConfigsMap.t]) :: [:gen_event.handler] do
    handler_pairs =
      configs_map
      |> Enum.map(fn {k, conf} -> {key_to_handler(k), conf} end)
      |> Enum.filter(fn {h, conf} -> h.validate_config(conf) end)
      |> Enum.map(fn {h, _} -> {AHandler, h} end)
    [ErrorCountReporter | handler_pairs]
  end

  defp handler_init_arg(otp_app_name, ErrorCountReporter ), do: otp_app_name
  defp handler_init_arg(otp_app_name, {AHandler, handler}), do: {otp_app_name, handler}

  defp key_to_handler(key) do
    temporary_module_name_str = @handler_module_prefix <> Macro.camelize(key)
    Module.safe_concat([temporary_module_name_str]) # handlers must be chosen from list of existing handlers (in console UI), so this should never raise
  end

  defunp manager(otp_app_name :: v[:antikythera | GearName.t]) :: nil | pid do
    try do
      case otp_app_name do
        :antikythera  -> AntikytheraCore.Alert.Manager
        gear_name -> GearModule.alert_manager(gear_name)
      end
      |> Process.whereis()
    rescue
      ArgumentError -> nil
    end
  end

  #
  # API for handlers
  #
  @doc """
  Schedule next flushing from handlers. Assuming the `interval` is in seconds.
  Note that handlers are kept as state in gen_event manager process,
  thus calling `self/0` always refers to the manager process which the handler is installed in.
  """
  defun schedule_handler_timeout(handler :: v[module], interval :: v[pos_integer]) :: :ok do
    Process.send_after(self(), {:handler_timeout, handler}, interval * 1_000)
    :ok
  end

  #
  # Public API
  #
  @doc """
  Notify a `manager` process of a message `body` with optional `time`.
  """
  defun notify(manager :: v[atom],
               body    :: v[String.t],
               time    :: v[Time.t] \\ Time.now()) :: :ok do
    :gen_event.notify(manager, {time, body})
  end
end
