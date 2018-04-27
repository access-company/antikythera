# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.ConfigGetter do
  @moduledoc """
  Helper module to define getter functions of gear configs.
  """

  defmacro __using__(_) do
    quote do
      # Assuming that module attribute `@gear_name` is defined in the __CALLER__'s context

      defun get_all_env() :: %{String.t => any} do
        Antikythera.GearApplication.ConfigGetter.get_all_env(@gear_name)
      end

      defun get_env(key :: v[String.t], default :: any \\ nil) :: any do
        Antikythera.GearApplication.ConfigGetter.get_env(@gear_name, key, default)
      end
    end
  end

  @doc false
  def get_all_env(gear_name) do
    case AntikytheraCore.Ets.ConfigCache.Gear.read(gear_name) do
      nil                              -> %{}
      %AntikytheraCore.Config.Gear{kv: kv} -> kv
    end
  end

  @doc false
  def get_env(gear_name, key, default) do
    get_all_env(gear_name)
    |> Map.get(key, default)
  end
end
