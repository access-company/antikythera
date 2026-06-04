# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.ExecutorPoolTest do
  use Croma.TestCase
  alias ExecutorPool.Setting, as: EPoolSetting
  alias ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.Ets.GearActionRunnerPools

  defp child_pids(pid) do
    Supervisor.which_children(pid) |> Enum.map(fn {_, p, _, _} -> p end)
  end

  test "should correctly setup processes within the supervision tree structure" do
    epool_root = Process.whereis(ExecutorPool.Sup)
    assert child_pids(epool_root) == []
    assert RaftFleet.consensus_groups() == %{}

    # spawn an ExecutorPool
    epool_id = {:gear, :testgear}

    setting = %EPoolSetting{
      n_pools_a: 2,
      pool_size_a: 1,
      n_pools_s: 1,
      pool_size_s: 1,
      pool_size_j: 1,
      ws_max_connections: 100
    }

    ExecutorPool.start_executor_pool(epool_id, setting)
    [{_, epool_pid, _, _}] = Supervisor.which_children(epool_root)
    assert Process.whereis(RegName.supervisor(epool_id)) == epool_pid
    action_pool_multi = Process.whereis(RegName.action_runner_pool_multi(epool_id))

    http_streaming_pool_multi =
      Process.whereis(RegName.http_streaming_runner_pool_multi(epool_id))

    job_pool_sup = Process.whereis(RegName.async_job_runner_pool(epool_id))
    child_pids = child_pids(epool_pid)
    assert length(child_pids) == 8
    assert action_pool_multi in child_pids
    assert http_streaming_pool_multi in child_pids
    assert job_pool_sup in child_pids
    ExecutorPoolHelper.wait_until_async_job_queue_added(epool_id)

    # should be able to checkout worker pid from the 2 types of process pools
    assert PoolSup.Multi.transaction(GearActionRunnerPools.table_name(), epool_id, &is_pid/1)
    assert PoolSup.transaction(job_pool_sup, &is_pid/1)

    # a dedicated hackney connection pool should be created and sized for this executor pool
    pool_name = AntikytheraCore.Httpc.connection_pool_name(epool_id)
    assert is_pid(:hackney_pool.find_pool(pool_name))

    assert :hackney_pool.max_connections(pool_name) ==
             AntikytheraCore.Httpc.connection_pool_size(setting)

    # changing the executor pool's setting should resize its connection pool too
    new_setting = %EPoolSetting{setting | pool_size_a: 3}
    assert ExecutorPool.apply_setting(epool_id, new_setting) == :ok

    assert :hackney_pool.max_connections(pool_name) ==
             AntikytheraCore.Httpc.connection_pool_size(new_setting)

    ExecutorPoolHelper.kill_and_wait(epool_id)
    refute Process.alive?(epool_pid)
    assert Process.whereis(RegName.supervisor(epool_id)) == nil
    # the connection pool should be stopped together with the executor pool
    assert :hackney_pool.find_pool(pool_name) == :undefined
    # should be idempotent
    assert ExecutorPool.kill_executor_pool(epool_id) == :ok
  end
end
