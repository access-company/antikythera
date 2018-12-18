# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.MemcacheTest do
  use Croma.TestCase
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias Antikythera.Memcache.{Key, Value}
  alias AntikytheraCore.ExecutorPool.MemcacheWriter
  alias Antikythera.TermUtil

  @epool_id        {:gear, :testgear}
  @lifetime        100
  @max_records_num MemcacheWriter.max_records()
  @max_key_size    Key.max_size()
  @max_value_size  Value.max_size()

  setup do
    ExecutorPool.start_executor_pool(@epool_id, EPoolSetting.default())
    # Without waiting for async job queue added, killing the epool fails.
    ExecutorPoolHelper.wait_until_async_job_queue_added(@epool_id)
    on_exit(fn ->
      :ets.delete_all_objects(AntikytheraCore.Ets.Memcache.table_name())
      ExecutorPoolHelper.kill_and_wait(@epool_id)
    end)
  end

  test "should read cached values" do
    assert Memcache.write("foo" , "bar", @epool_id, @lifetime) == :ok
    assert Memcache.write("hoge", 1    , @epool_id, @lifetime) == :ok
    assert Memcache.read( "foo" , @epool_id)                   == {:ok, "bar"}
    assert Memcache.read( "hoge", @epool_id)                   == {:ok, 1}
  end

  test "should update cached values" do
    assert Memcache.write("foo", "bar", @epool_id, @lifetime)  == :ok
    assert Memcache.read( "foo", @epool_id)                    == {:ok, "bar"}
    assert Memcache.write("foo", "hoge", @epool_id, @lifetime) == :ok
    assert Memcache.read( "foo", @epool_id)                    == {:ok, "hoge"}
  end

  test "should write values to memcache and read them with read_or_else_write/5" do
    assert Memcache.read("foo", @epool_id)                                           == {:error, :not_found}
    assert Memcache.read_or_else_write("foo", @epool_id, @lifetime, fn -> "bar" end) == {:ok, "bar"}
    assert Memcache.read("foo", @epool_id)                                           == {:ok, "bar"}
  end

  test "should return an error with non existing keys" do
    assert Memcache.write("foo", "bar", @epool_id, @lifetime) == :ok
    assert Memcache.read( "non_existing_key", @epool_id)      == {:error, :not_found}
  end

  test "should return an error when memcache is expired" do
    assert Memcache.write("foo" , "bar", @epool_id, @lifetime) == :ok
    assert Memcache.write("hoge", 1    , @epool_id, 1)         == :ok
    :timer.sleep(1_000)
    assert Memcache.read("foo" , @epool_id) == {:ok   , "bar"}
    assert Memcache.read("hoge", @epool_id) == {:error, :not_found}
  end

  test "should not exceed the maximum number of records and evict the oldest record" do
    Enum.each(1..@max_records_num+1, fn n ->
      assert Memcache.write(n, "value #{n}", @epool_id, @lifetime) == :ok
    end)
    assert :ets.info(AntikytheraCore.Ets.Memcache.table_name(), :size) == @max_records_num
    assert Memcache.read(1, @epool_id) == {:error, :not_found}
  end

  test "should return an error with too large keys" do
    large_binary = String.duplicate("a", @max_key_size)
    assert TermUtil.size(large_binary) > @max_key_size
    assert Memcache.write(large_binary, "bar", @epool_id, @lifetime)                        == {:error, :too_large_key}
    assert Memcache.read_or_else_write(large_binary, @epool_id, @lifetime, fn -> "bar" end) == {:error, :too_large_key}
  end

  test "should return an error with too large values" do
    large_binary = String.duplicate("a", @max_value_size)
    assert TermUtil.size(large_binary) > @max_value_size
    assert Memcache.write("foo", large_binary, @epool_id, @lifetime)                        == {:error, :too_large_value}
    assert Memcache.read_or_else_write("foo", @epool_id, @lifetime, fn -> large_binary end) == {:error, :too_large_value}
  end
end
