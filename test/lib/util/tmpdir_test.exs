# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.TmpdirTest do
  use Croma.TestCase
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias Antikythera.Test.ConnHelper
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraCore.TmpdirTracker

  @context ConnHelper.make_conn().context
  @epool_id @context.executor_pool_id
  @base_dir Path.join(CorePath.gear_tmp_dir(), EPoolId.to_string(@epool_id))

  setup do
    assert Path.wildcard(Path.join(@base_dir, "*")) == []

    on_exit(fn ->
      assert Path.wildcard(Path.join(@base_dir, "*")) == []
    end)
  end

  defp make(f) do
    try do
      Tmpdir.make(Enum.random([@context, @epool_id]), fn tmpdir ->
        assert String.starts_with?(tmpdir, @base_dir)
        assert File.dir?(tmpdir)
        f.(tmpdir)
      end)
    after
      # wait until `:finished` message gets processed
      _ = :sys.get_state(TmpdirTracker)
    end
  end

  test "make/2 should remove directory when passed function successfully completes" do
    dir = make(fn tmpdir -> tmpdir end)
    refute File.dir?(dir)
  end

  test "make/2 should remove directory when passed function fails" do
    catch_error(make(fn _ -> raise "raise!" end))
    catch_throw(make(fn _ -> throw("throw!") end))
    catch_exit(make(fn _ -> exit("exit!") end))
  end

  test "make/2 should remove directory when calling process is killed" do
    test_pid = self()

    caller =
      spawn(fn ->
        make(fn _ ->
          send(test_pid, :inside_make)
          :timer.sleep(1000)
        end)
      end)

    # make sure that the directory was created
    assert_receive(:inside_make)
    Process.exit(caller, :kill)
    :timer.sleep(100)
  end

  test "nested call of make/2 should raise" do
    catch_error(
      make(fn _ ->
        make(fn dir -> dir end)
      end)
    )
  end
end
