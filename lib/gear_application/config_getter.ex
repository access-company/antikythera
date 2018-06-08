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

      defun get_env!(key :: v[String.t]) :: any do
        Antikythera.GearApplication.ConfigGetter.get_env!(@gear_name, key)
      end
    end
  end

  @doc false
  def get_all_env(gear_name) do
    case load_config_from_process_dictionary(gear_name) do
      {:ok   , config              } -> config
      {:error, current_gear_configs} ->
        config = load_config_from_ets(gear_name)
        store_config_to_process_dictionary(gear_name, current_gear_configs, config)
        config
    end
  end

  defp load_config_from_process_dictionary(gear_name) do
    case Process.get(:gear_configs) do
      nil     -> {:error, %{}}
      configs ->
        case Map.get(configs, gear_name) do
          nil    -> {:error, configs}
          config -> {:ok   , config }
        end
    end
  end

  defp store_config_to_process_dictionary(gear_name, current_gear_configs, config) do
    new_gear_configs = Map.put(current_gear_configs, gear_name, config)
    Process.put(:gear_configs, new_gear_configs)
  end

  defp load_config_from_ets(gear_name) do
    case AntikytheraCore.Ets.ConfigCache.Gear.read(gear_name) do
      nil                                  -> %{}
      %AntikytheraCore.Config.Gear{kv: kv} -> kv
    end
  end

  @doc false
  def get_env(gear_name, key, default) do
    get_all_env(gear_name) |> Map.get(key, default)
  end

  @doc false
  def get_env!(gear_name, key) do
    get_all_env(gear_name) |> Map.fetch!(key)
  end

  defun cleanup_configs_in_process_dictionary() :: :ok do
    Process.delete(:gear_configs)
    :ok
  end
end
