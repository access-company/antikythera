# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.TenantExecutorPoolsManager do
  @moduledoc """
  A `GenServer` that caches tenant settings and apply changes to tenant executor pools.

  Original information of tenant settings is (typically) stored in a slow file storage.
  As reading many files may take long, such kind of file operations are done by one-off processes.

  Note that `init/1` callback fetches all tenant settings and applies them in a blocking manner.

  Note also that there are two sources of tenant setting information that this GenServer receives:

  1. periodic scanning of files
  2. notification by `GenServer.call(server, {:apply, tenant_id, tenant_setting})` (may be called using `multi_call`)

  Information given by the two sources may have conflicts, i.e. results from (1) may not include the latest info given by (2).
  In order not to kill working tenant executor pools, we don't immediately remove/disassociate executor pool
  that is not included in (1); those operations are delayed to the next `:check`.
  """

  use GenServer
  alias SolomonLib.{MapUtil, GearName, TenantId, SecondsSinceEpoch}
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.Ets.TenantToGearsMapping
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.ExecutorPool.TenantSetting
  require AntikytheraCore.Logger, as: L

  defmodule OneOffFetcher do
    def run(last_checked_at) do
      checked_at = System.system_time(:seconds)
      result = TenantSetting.fetch_all_modified(last_checked_at)
      exit({:ok, checked_at, result})
    end
  end

  @interval 300_000
  defun polling_interval() :: pos_integer, do: @interval

  @typep settings :: %{TenantId.t => TenantSetting.t}
  @typep state    :: %{
    last_checked_at: SecondsSinceEpoch.t,
    settings:        settings,
    fetcher:         nil | {pid, reference},
    to_remove:       [TenantId.t],
    to_disassociate: %{TenantId.t => [GearName.t]},
  }
  @typep triplet :: {settings, [TenantId.t], %{TenantId.t => [GearName.t]}}

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    arrange_next_check()
    {:ok, fetch_and_apply_on_init()}
  end

  defunp fetch_and_apply_on_init() :: state do
    checked_at = System.system_time(:seconds)
    {:all, all_settings} = TenantSetting.fetch_all_modified(0)
    {settings, _, _} = apply_modifications(%{}, :all, all_settings)
    %{last_checked_at: checked_at, settings: settings, fetcher: nil, to_remove: [], to_disassociate: %{}}
  end

  # To be used by `TenantSetting.broadcast_new_tenant_setting/2` (in the form of multi_call)
  @impl true
  def handle_call({:apply, tenant_id, tsetting}, _from, %{settings: old_settings} = s) do
    {new_settings, _, _} = apply_modifications(old_settings, :partial, %{tenant_id => tsetting})
    {:reply, :ok, %{s | settings: new_settings}}
  end

  @impl true
  def handle_info(:check, %{last_checked_at: last_checked_at, fetcher: fetcher} = s) do
    arrange_next_check()
    case fetcher do
      nil          -> {:noreply, %{s | fetcher: spawn_monitor(OneOffFetcher, :run, [last_checked_at])}}
      {_pid, _ref} -> {:noreply, s} # don't run more than one temporary process
    end
  end
  def handle_info({:DOWN, _monitor_ref, :process, _pid, reason}, s0) do
    s1 = %{s0 | fetcher: nil}
    s2 =
      case reason do
        {:ok, checked_at, result} -> result_received(s1, checked_at, result)
        _otherwise                ->
          L.error("One-off fetcher process died unexpectedly! reason: #{inspect(reason)}")
          s1
      end
    {:noreply, s2}
  end

  defp result_received(%{settings: old_settings, to_remove: to_remove, to_disassociate: to_disassociate} = s,
                       checked_at,
                       {result_set_type, modified_settings}) do
    new_settings1 = apply_pending_operations(old_settings, to_remove, to_disassociate, Map.keys(modified_settings))
    {new_settings2, new_to_remove, new_to_disassociate} = apply_modifications(new_settings1, result_set_type, modified_settings)
    %{s | last_checked_at: checked_at, settings: new_settings2, to_remove: new_to_remove, to_disassociate: new_to_disassociate}
  end

  defp arrange_next_check() do
    Process.send_after(self(), :check, @interval)
  end

  defunp apply_pending_operations(old_settings     :: settings,
                                  to_remove0       :: [TenantId.t],
                                  to_disassociate0 :: %{TenantId.t => [GearName.t]},
                                  modified_tenants :: [TenantId.t]) :: settings do
    # Cancel operations on tenants that are recently modified
    to_remove       = to_remove0 -- modified_tenants
    to_disassociate = Map.drop(to_disassociate0, modified_tenants)

    Enum.each(to_remove, fn tenant_id ->
      if !Enum.empty?(old_settings[tenant_id].gears) do
        kill_executor_pool(tenant_id)
      end
    end)

    disassociated_settings = MapUtil.map_values(to_disassociate, fn {tenant_id, target_gears} ->
      tsetting = old_settings[tenant_id]
      gears_after_disassociate = tsetting.gears -- target_gears
      if Enum.empty?(gears_after_disassociate) do
        kill_executor_pool(tenant_id)
      end
      %TenantSetting{tsetting | gears: gears_after_disassociate}
    end)

    old_settings |> Map.drop(to_remove) |> Map.merge(disassociated_settings)
  end

  defunp apply_modifications(old_settings      :: settings,
                             result_set_type   :: :all | :partial,
                             modified_settings :: settings) :: triplet do
    {only_old, modified, only_new} = MapUtil.difference(old_settings, modified_settings)
    handle_added_tenant_settings(only_new)
    {updated_settings, to_disassociate} = handle_updated_tenant_settings(modified)
    to_remove = if result_set_type == :all, do: Map.keys(only_old), else: []
    new_settings = old_settings |> Map.merge(only_new) |> Map.merge(updated_settings)
    {new_settings, to_remove, to_disassociate}
  end

  defunp handle_updated_tenant_settings(modified :: %{TenantId.t => {TenantSetting.t, TenantSetting.t}}) :: {settings, %{TenantId.t => [GearName.t]}} do
    m = MapUtil.map_values(modified, fn {tenant_id, {old, new}} ->
      case {old.gears, new.gears} do
        {[]    , []    } -> {new, []}
        {[]    , _     } -> start_executor_pool(tenant_id, new); {new, []}
        {gears1, gears2} ->
          gears_union = Enum.uniq(gears1 ++ gears2) |> Enum.sort()
          new_union = %TenantSetting{new | gears: gears_union}
          update_existing_executor_pool(tenant_id, old, new_union)
          {new_union, gears1 -- gears2}
      end
    end)
    settings        = MapUtil.map_values(m, fn {_, {tsetting, _    }} -> tsetting end)
    to_disassociate = MapUtil.map_values(m, fn {_, {_       , gears}} -> gears    end)
    {settings, to_disassociate}
  end

  defunp handle_added_tenant_settings(only_new :: settings) :: :ok do
    Enum.each(only_new, fn {tenant_id, %TenantSetting{gears: gears} = tsetting} ->
      if !Enum.empty?(gears) do
        start_executor_pool(tenant_id, tsetting)
      end
    end)
  end

  defunp start_executor_pool(tenant_id :: v[TenantId.t], tsetting :: v[TenantSetting.t]) :: :ok do
    ExecutorPool.start_executor_pool({:tenant, tenant_id}, EPoolSetting.new!(tsetting))
    TenantToGearsMapping.set(tenant_id, tsetting.gears)
  end

  defunp kill_executor_pool(tenant_id :: v[TenantId.t]) :: :ok do
    TenantToGearsMapping.unset(tenant_id)
    ExecutorPool.kill_executor_pool({:tenant, tenant_id})
  end

  defunp update_existing_executor_pool(tenant_id :: v[TenantId.t], old_tsetting :: v[TenantSetting.t], new_tsetting :: v[TenantSetting.t]) :: :ok do
    old_setting = EPoolSetting.new!(old_tsetting)
    new_setting = EPoolSetting.new!(new_tsetting)
    if old_setting != new_setting do
      ExecutorPool.apply_setting({:tenant, tenant_id}, new_setting)
    end
    new_gears = new_tsetting.gears
    if old_tsetting.gears != new_gears do
      TenantToGearsMapping.set(tenant_id, new_gears)
    end
  end

  # To be used by ac_console (and tests)
  defun all() :: settings do
    %{settings: settings} = :sys.get_state(__MODULE__) # simply use `:sys.get_state/1` and skip defining internal message
    settings
  end
end
