# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearModule do
  alias SolomonLib.GearName
  alias AntikytheraCore.Handler.HelperModules

  defun template_module_from_context(%SolomonLib.Context{gear_entry_point: {mod, _}}) :: module do
    Module.split(mod) |> hd() |> Module.safe_concat("Template")
  end

  defun error_handler(gear_name :: v[GearName.t]) :: nil | module do
    gear_app_module = camelize_gear_name(gear_name) |> List.wrap() |> Module.safe_concat()
    # workaround dialyzer warning "Guard test is_map(_@1::atom()) can never succeed" by using `apply`
    apply(gear_app_module, :error_handler_module, [])
  end
  defun error_handler_unsafe(gear_name :: v[GearName.t]) :: module do
    camelize_gear_name(gear_name) |> Module.concat("Controller.Error")
  end

  [
    :logger,
    :router,
    :metrics_uploader,
    :alert_manager,
  ] |> Enum.each(fn name ->
    module_basename = Atom.to_string(name) |> Macro.camelize()

    defun unquote(name)(gear_name :: v[GearName.t]) :: module do
      camelize_gear_name(gear_name) |> Module.safe_concat(unquote(module_basename))
    end

    defun unquote(:"#{name}_unsafe")(gear_name :: v[GearName.t]) :: module do
      camelize_gear_name(gear_name) |> Module.concat(unquote(module_basename))
    end
  end)

  defun root_supervisor_unsafe(gear_name :: v[GearName.t]) :: module do
    camelize_gear_name(gear_name) |> Module.concat("Supervisor")
  end

  defun top(gear_name :: v[GearName.t]) :: module do
    Module.safe_concat([camelize_gear_name(gear_name)])
  end

  defunp camelize_gear_name(gear_name :: v[GearName.t]) :: String.t do
    gear_name |> Atom.to_string() |> Macro.camelize()
  end

  defun request_helper_modules(gear_name :: v[GearName.t]) :: HelperModules.t do
    camelized = camelize_gear_name(gear_name)
    %HelperModules{
      top:              Module.safe_concat([camelized]),
      router:           Module.safe_concat([camelized, "Router"]),
      logger:           Module.safe_concat([camelized, "Logger"]),
      metrics_uploader: Module.safe_concat([camelized, "MetricsUploader"]),
    }
  end
end
