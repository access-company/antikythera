# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets.GearActionRunnerPools do
  defun init() :: :ok do
    AntikytheraCore.Ets.create_read_optimized_table(table_name())
  end

  defun table_name() :: atom do
    :antikythera_gear_action_runner_pools
  end
end
