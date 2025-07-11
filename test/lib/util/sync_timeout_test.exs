# Copyright(c) 2015-2025 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.SyncTimeoutTest do
  use ExUnit.Case

  test "returns {:ok, value} when function completes within timeout" do
    f = fn -> :ok end
    assert Antikythera.SyncTimeout.run(f, 1000, :step1) == {:ok, :ok}
  end

  test "returns {:error, tag} when function exceeds timeout" do
    f = fn ->
      :timer.sleep(2000)
      :ok
    end

    assert Antikythera.SyncTimeout.run(f, 500, :step2) == {:error, :step2}
  end

  test "returns {:ok, {:error, :something}} when function returns error tuple as normal value" do
    f = fn -> {:error, :reason} end
    assert Antikythera.SyncTimeout.run(f, 1000, :step3) == {:ok, {:error, :reason}}
  end

  test "returns {:error, {:exception, ...}} when function raises" do
    f = fn -> raise "fail!" end

    assert match?(
             {:error, {:exception, %RuntimeError{message: "fail!"}, _}},
             Antikythera.SyncTimeout.run(f, 1000, :step4)
           )
  end

  test "returns {:error, {kind, reason}} when function throws" do
    f = fn -> throw(:my_throw) end
    assert Antikythera.SyncTimeout.run(f, 1000, :step5) == {:error, {:throw, :my_throw}}
  end

  test "returns {:error, {kind, reason}} when function exits" do
    f = fn -> exit(:my_exit) end
    assert Antikythera.SyncTimeout.run(f, 1000, :step6) == {:error, {:exit, :my_exit}}
  end

  test "returns {:error, :nested_sync_timeout} when nested in same process" do
    Process.put(:antikythera_sync_timeout_running, true)
    try do
      assert Antikythera.SyncTimeout.run(fn -> :ok end, 1000, :inner) == {:error, :nested_sync_timeout}
    after
      Process.delete(:antikythera_sync_timeout_running)
    end
  end
end
