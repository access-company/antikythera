# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.TenantExecutorPoolsManagerTest do
  use Croma.TestCase
  alias Antikythera.Test.ProcessHelper
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.ExecutorPool.{TenantSetting, WsConnectionsCapping}
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.Ets.TenantToGearsMapping
  alias AntikytheraCore.Path, as: CorePath

  @tenant_id "g_12345678"
  @epool_id {:tenant, @tenant_id}
  @sup_name RegName.supervisor_unsafe(@epool_id)
  @tenant_setting_path CorePath.tenant_setting_file_path(@tenant_id)

  defp wait_until_one_off_fetcher_finishes() do
    case :sys.get_state(TenantExecutorPoolsManager)[:fetcher] do
      nil ->
        :ok

      {pid, _ref} ->
        ProcessHelper.monitor_wait(pid)
        :timer.sleep(10)
        assert :sys.get_state(TenantExecutorPoolsManager)[:fetcher] == nil
    end
  end

  defp send_check_and_wait() do
    send(TenantExecutorPoolsManager, :check)
    wait_until_one_off_fetcher_finishes()
  end

  defp put_tenant_setting(setting) do
    TenantSetting.put(@tenant_id, setting)
    send_check_and_wait()
  end

  defp assert_record_exists(gears) do
    assert :ets.lookup(TenantToGearsMapping.table_name(), @tenant_id) == [{@tenant_id, gears}]
  end

  defp assert_record_not_exists() do
    assert :ets.lookup(TenantToGearsMapping.table_name(), @tenant_id) == []
  end

  defp make_setting(na, sa, sj, ws, gears) do
    %TenantSetting{
      n_pools_a: na,
      pool_size_a: sa,
      pool_size_j: sj,
      ws_max_connections: ws,
      gears: gears
    }
  end

  setup do
    File.write!(CorePath.tenant_ids_file_path(), :zlib.gzip(@tenant_id))

    on_exit(fn ->
      # Remove setting => stop and remove ETS record
      ExecutorPoolHelper.kill_and_wait(@epool_id, fn ->
        settings_before = :sys.get_state(TenantExecutorPoolsManager)[:settings]
        File.write!(CorePath.tenant_ids_file_path(), :zlib.gzip(""))
        File.rm(@tenant_setting_path)
        send_check_and_wait()
        assert :sys.get_state(TenantExecutorPoolsManager)[:settings] == settings_before
        send_check_and_wait()
        assert :sys.get_state(TenantExecutorPoolsManager)[:settings] == %{}
      end)
    end)
  end

  test "should properly start/stop/update ExecutorPool for tenant" do
    # Setting with no gears => don't write it as a file
    put_tenant_setting(make_setting(1, 5, 1, 100, []))
    refute File.exists?(@tenant_setting_path)
    assert is_nil(Process.whereis(@sup_name))
    assert_record_not_exists()

    # Add setting with a gear => start and set ETS record
    put_tenant_setting(make_setting(1, 5, 1, 100, [:gear1]))
    assert File.exists?(@tenant_setting_path)
    assert is_pid(Process.whereis(@sup_name))
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 1, 100)
    assert_record_exists([:gear1])
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)

    # Next :check without doing anything => nothing changed
    send_check_and_wait()
    assert is_pid(Process.whereis(@sup_name))
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 1, 100)
    assert_record_exists([:gear1])

    # Update setting to remove the gear => remove at the next :check
    ExecutorPoolHelper.kill_and_wait(@epool_id, fn ->
      put_tenant_setting(make_setting(1, 5, 1, 100, []))
      refute File.exists?(@tenant_setting_path)
      assert is_pid(Process.whereis(@sup_name))
      assert_record_exists([:gear1])
      # wait until file modification becomes stale
      :timer.sleep(1_000)
      # receive the disassociated tenant setting; still associated
      send_check_and_wait()
      # actually disassociate
      send_check_and_wait()
      assert_record_not_exists()
      assert is_nil(Process.whereis(@sup_name))
    end)

    # Update to associate gear again => start and set ETS record
    put_tenant_setting(make_setting(2, 4, 1, 200, [:gear1]))
    assert File.exists?(@tenant_setting_path)
    assert is_pid(Process.whereis(@sup_name))
    ExecutorPoolHelper.assert_current_setting(@epool_id, 2, 4, 1, 200)
    assert_record_exists([:gear1])
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)

    # Update capacity => apply new capacity setting
    put_tenant_setting(make_setting(1, 3, 1, 100, [:gear1]))
    assert File.exists?(@tenant_setting_path)
    assert is_pid(Process.whereis(@sup_name))
    ExecutorPoolHelper.hurry_action_pool_multi(@epool_id)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 3, 1, 100)
    assert_record_exists([:gear1])

    # Update to associate one more gear => update ETS record
    put_tenant_setting(make_setting(1, 3, 1, 100, [:gear1, :gear2]))
    assert File.exists?(@tenant_setting_path)
    assert is_pid(Process.whereis(@sup_name))
    ExecutorPoolHelper.hurry_action_pool_multi(@epool_id)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 3, 1, 100)
    :timer.sleep(10)
    assert_record_exists([:gear1, :gear2])
  end

  test "should tolerate already running executor pools" do
    # spawned by someone (previous TenantExecutorpoolsManager) other than the current one
    setting = make_setting(1, 5, 1, 100, [:gear1])
    TenantSetting.put(@tenant_id, setting)
    ExecutorPool.start_executor_pool(@epool_id, EPoolSetting.new!(setting))
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 1, 100)
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)

    refute Map.has_key?(TenantExecutorPoolsManager.all(), @tenant_id)
    send_check_and_wait()
    assert Map.has_key?(TenantExecutorPoolsManager.all(), @tenant_id)
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 5, 1, 100)
  end

  test "should cap ws_max_connections based on available amount of memory" do
    limit = WsConnectionsCapping.upper_limit()
    put_tenant_setting(make_setting(1, 3, 1, limit + 1, [:gear1]))
    ExecutorPoolHelper.assert_current_setting(@epool_id, 1, 3, 1, limit)
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)
  end
end
