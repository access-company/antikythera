# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Test.GearConfigHelper do
  @moduledoc """
  Helper functions to set gear configs from within gears' test code.
  """

  alias Antikythera.GearName
  alias AntikytheraCore.Config.Gear, as: GearConfig
  alias AntikytheraCore.Ets.ConfigCache

  defun set_config(
          gear_name :: v[GearName.t()] \\ Mix.Project.config()[:app],
          kv :: v[%{String.t() => any}]
        ) :: :ok do
    Antikythera.GearApplication.ConfigGetter.cleanup_configs_in_process_dictionary()
    old_config = GearConfig.read(gear_name)
    new_config = %GearConfig{old_config | kv: kv}
    GearConfig.write(gear_name, new_config)
    ConfigCache.Gear.write(gear_name, new_config)
  end
end
