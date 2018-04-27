# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.HandlerConfig do
  @moduledoc """
  Type module for map of configurations for a single alert handler.

  Fields are treated as opaque at this layer; details are defined by each handler implementation.
  """

  alias Antikythera.GearName
  alias AntikytheraCore.Alert.HandlerConfigsMap

  use Croma.SubtypeOfMap, key_module: Croma.String, value_module: Croma.Any

  defun get(handler :: v[module], otp_app_name :: v[:antikythera | GearName.t]) :: t do
    HandlerConfigsMap.get(otp_app_name)
    |> Map.get(key(handler), %{})
  end

  defunp key(handler :: v[module]) :: String.t do
    handler
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end

defmodule AntikytheraCore.Alert.HandlerConfigsMap do
  @moduledoc """
  Type module for map of all alert configurations for a single OTP application (antikythera or a gear).

  Keys must be snake-cased handler names and values must be maps of each alert handler's configurations.
  These maps are stored in core/gear configs.
  """

  alias Antikythera.GearName
  alias AntikytheraCore.Ets.ConfigCache

  use Croma.SubtypeOfMap, key_module: Croma.String, value_module: AntikytheraCore.Alert.HandlerConfig

  defun get(otp_app_name :: v[:antikythera | GearName.t]) :: t do
    case otp_app_name do
      :antikythera  -> ConfigCache.Core.read() |> Map.get(:alerts, %{})
      gear_name -> ConfigCache.Gear.read(gear_name).alerts
    end
  end
end
