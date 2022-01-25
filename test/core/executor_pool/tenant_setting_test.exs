# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.ExecutorPool.TenantSettingTest do
  use Croma.TestCase
  alias Antikythera.Test.ProcessHelper
  alias AntikytheraCore.TenantExecutorPoolsManager
  alias AntikytheraCore.Path, as: CorePath

  @tenant_id "dummy_tenant"
  @tenant_setting TenantSetting.default()

  defp assert_associated_gears(gears) do
    tsetting = TenantSetting.fetch_or_default(@tenant_id)
    assert tsetting == Map.put(@tenant_setting, :gears, gears)
  end

  defp send_check_and_wait() do
    send(TenantExecutorPoolsManager, :check)

    case :sys.get_state(TenantExecutorPoolsManager)[:fetcher] do
      nil -> :ok
      {pid, _ref} -> ProcessHelper.monitor_wait(pid)
    end

    assert :sys.get_state(TenantExecutorPoolsManager)[:fetcher] == nil
  end

  setup do
    File.write!(CorePath.tenant_ids_file_path(), :zlib.gzip(@tenant_id))

    on_exit(fn ->
      ExecutorPoolHelper.kill_and_wait({:tenant, @tenant_id}, fn ->
        settings_before = :sys.get_state(TenantExecutorPoolsManager)[:settings]
        File.write!(CorePath.tenant_ids_file_path(), :zlib.gzip(""))
        File.rm(CorePath.tenant_setting_file_path(@tenant_id))
        send_check_and_wait()
        assert :sys.get_state(TenantExecutorPoolsManager)[:settings] == settings_before
        send_check_and_wait()
        assert :sys.get_state(TenantExecutorPoolsManager)[:settings] == %{}
        :timer.sleep(100)
      end)
    end)
  end

  test "associate/2 and disassociate/2" do
    assert_associated_gears([])
    TenantSetting.associate_with_gear(:gear1, @tenant_id)
    assert_associated_gears([:gear1])
    ExecutorPoolHelper.wait_until_async_job_queue_added({:tenant, @tenant_id})
    TenantSetting.associate_with_gear(:gear1, @tenant_id)
    assert_associated_gears([:gear1])
    TenantSetting.associate_with_gear(:gear2, @tenant_id)
    assert_associated_gears([:gear1, :gear2])
    TenantSetting.associate_with_gear(:gear0, @tenant_id)
    assert_associated_gears([:gear0, :gear1, :gear2])
    TenantSetting.disassociate_from_gear(:gear1, @tenant_id)
    assert_associated_gears([:gear0, :gear2])
    TenantSetting.disassociate_from_gear(:gear2, @tenant_id)
    assert_associated_gears([:gear0])
    TenantSetting.disassociate_from_gear(:gear0, @tenant_id)
    assert_associated_gears([])
  end

  test "persist_new_tenant_and_broadcast/2 should save tenant setting JSON and apply the setting immediately" do
    assert Supervisor.which_children(AntikytheraCore.ExecutorPool.Sup) == []

    gears = [:gear1, :gear2]
    refute Map.has_key?(TenantExecutorPoolsManager.all(), @tenant_id)
    TenantSetting.persist_new_tenant_and_broadcast(@tenant_id, gears)
    assert_associated_gears(gears)
    assert TenantExecutorPoolsManager.all()[@tenant_id] == Map.put(@tenant_setting, :gears, gears)
    ExecutorPoolHelper.wait_until_async_job_queue_added({:tenant, @tenant_id})
    assert length(Supervisor.which_children(AntikytheraCore.ExecutorPool.Sup)) == 1

    # disassociating using `persist_new_tenant_and_broadcast` should be delayed
    TenantSetting.persist_new_tenant_and_broadcast(@tenant_id, [])
    assert_associated_gears([])
    assert TenantExecutorPoolsManager.all()[@tenant_id] == Map.put(@tenant_setting, :gears, gears)
    # wait until file modification becomes stale
    :timer.sleep(1_000)
    # receive the disassociated tenant setting; still associated
    send_check_and_wait()
    assert TenantExecutorPoolsManager.all()[@tenant_id] == Map.put(@tenant_setting, :gears, gears)
    assert length(Supervisor.which_children(AntikytheraCore.ExecutorPool.Sup)) == 1
    # actually disassociate
    send_check_and_wait()
    assert TenantExecutorPoolsManager.all()[@tenant_id] == @tenant_setting
    assert Supervisor.which_children(AntikytheraCore.ExecutorPool.Sup) == []
  end
end
