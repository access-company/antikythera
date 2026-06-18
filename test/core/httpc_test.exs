# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.HttpcTest do
  use Croma.TestCase
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting

  test "connection_pool_name/1 should derive a name from the executor pool ID" do
    assert Httpc.connection_pool_name({:gear, :testgear}) == "gear-testgear"

    assert Httpc.connection_pool_name({:tenant, "abcdefghij0123456789"}) ==
             "tenant-abcdefghij0123456789"
  end

  test "connection_pool_size/1 should be (action + http-streaming + async-job concurrency) * 2" do
    # defaults: n_pools_a=1, pool_size_a=5, n_pools_s=1, pool_size_s=1, pool_size_j=2 -> (5 + 1 + 2) * 2
    assert Httpc.connection_pool_size(EPoolSetting.default()) == 16

    setting = %EPoolSetting{
      n_pools_a: 4,
      pool_size_a: 5,
      n_pools_s: 2,
      pool_size_s: 3,
      pool_size_j: 6,
      ws_max_connections: 100
    }

    assert Httpc.connection_pool_size(setting) == (4 * 5 + 2 * 3 + 6) * 2
  end

  test "connection_pool_size/1 should be at least 1 even when all worker pool sizes are 0" do
    setting = %EPoolSetting{
      n_pools_a: 0,
      pool_size_a: 0,
      n_pools_s: 0,
      pool_size_s: 0,
      pool_size_j: 0,
      ws_max_connections: 0
    }

    assert Httpc.connection_pool_size(setting) == 1
  end

  test "connection_pool_stats/1 should return nil when the pool does not exist" do
    assert Httpc.connection_pool_stats({:gear, :nonexistent_gear}) == nil
  end

  test "connection_pool_stats/1 should report connection counts of an existing pool" do
    epool_id = {:gear, :testgear_for_stats}
    name = Httpc.connection_pool_name(epool_id)
    :ok = :hackney_pool.start_pool(name, max_connections: 7)

    try do
      assert %{max: 7, in_use: 0, free: 0} = Httpc.connection_pool_stats(epool_id)
    after
      :hackney_pool.stop_pool(name)
    end
  end

  test "default_connection_pool_stats/0 should report connection counts of hackney's default pool" do
    # The default pool is created lazily and shared, so only start/stop it if it isn't already running.
    pool_started_by_test = :hackney_pool.find_pool(:default) == :undefined
    if pool_started_by_test, do: :ok = :hackney_pool.start_pool(:default, max_connections: 9)

    try do
      stats = :hackney_pool.get_stats(:default)

      assert Httpc.default_connection_pool_stats() == %{
               max: Keyword.fetch!(stats, :max),
               in_use: Keyword.fetch!(stats, :in_use_count),
               free: Keyword.fetch!(stats, :free_count)
             }
    after
      if pool_started_by_test, do: :hackney_pool.stop_pool(:default)
    end
  end
end
