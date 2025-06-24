defmodule Acs.SyncTimeoutTest do
  use ExUnit.Case

  test "returns ok when function completes in time" do
    f = fn -> :ok end
    assert Acs.SyncTimeout.run(f, 1000, :step1) == {:ok, :ok}
  end

  test "returns error with tag when function exceeds timeout" do
    f = fn ->
      :timer.sleep(2000)
      :ok
    end

    assert Acs.SyncTimeout.run(f, 500, :step1) == {:error, :step1}
  end
end
