# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.TmpdirTrackerTest do
  use ExUnit.Case
  alias Antikythera.Tmpdir
  alias AntikytheraCore.TmpdirTracker

  @context Antikythera.Test.ConnHelper.make_conn().context

  test "TmpdirTracker.get/1 returns tmpdir only within Tmpdir.make/2" do
    Tmpdir.make(@context, fn tmpdir ->
      assert {:ok, tmpdir} == TmpdirTracker.get(@context.executor_pool_id)
    end)
    assert {:error, :not_found} == TmpdirTracker.get(@context.executor_pool_id)
  end
end
