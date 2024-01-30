# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearExecutorPoolsManagerTest do
  use Croma.TestCase
  alias Antikythera.NestedMap
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.ExecutorPool
  alias ExecutorPool.Setting, as: EPoolSetting
  alias ExecutorPoolHelper

  @gear_name :testgear
  @epool_id {:gear, @gear_name}

  defp put_setting_to_core_config_cache(setting) do
    m1 = ConfigCache.Core.read()

    m2 =
      NestedMap.deep_merge(m1, %{
        gears: %{@gear_name => %{executor_pool: Map.from_struct(setting)}}
      })

    ConfigCache.Core.write(m2)
    GenServerHelper.send_message_and_wait(GearExecutorPoolsManager, :timeout)
  end

  defp delete_setting_in_core_config_cache() do
    m1 = ConfigCache.Core.read()
    m2 = Map.put(m1, :gears, %{})
    ConfigCache.Core.write(m2)
    GenServerHelper.send_message_and_wait(GearExecutorPoolsManager, :timeout)
    ExecutorPoolHelper.hurry_action_pool_multi(@epool_id)
  end

  test "should properly set capacity of GearExecutorPool" do
    default = EPoolSetting.default()
    ExecutorPool.start_executor_pool(@epool_id, default)
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 2, 100)

    setting1 = %EPoolSetting{
      n_pools_a: 2,
      pool_size_a: 1,
      pool_size_j: 1,
      ws_max_connections: 200
    }

    put_setting_to_core_config_cache(setting1)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 2, 1, 1, 200)

    setting2 = %EPoolSetting{
      n_pools_a: 3,
      pool_size_a: 2,
      pool_size_j: 2,
      ws_max_connections: 100
    }

    put_setting_to_core_config_cache(setting2)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 3, 2, 2, 100)

    delete_setting_in_core_config_cache()
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 2, 100)

    # manually kill executor pool (for subsequent tests) as gear's executor pool is not automatically killed by the manager
    ExecutorPoolHelper.kill_and_wait(@epool_id)
  end
end
