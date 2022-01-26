# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearTaskTest do
  use Croma.TestCase, alias_as: T

  def fun_normal(), do: 1 + 1
  def fun_raise(), do: raise("foobar")
  def fun_throw(), do: throw("foobar")
  def fun_exit(), do: exit("foobar")
  def fun_timeout(), do: :timer.sleep(1_000)

  defp no_task_running?() do
    Enum.all?(Process.list(), fn pid ->
      Process.info(pid)[:initial_call] != {T, :worker_run, 2}
    end)
  end

  test "exec_wait/4" do
    success_fun = fn x -> x + 1 end
    failure_fun = fn reason, _st -> reason end

    [
      fun_normal: 3,
      fun_raise: {:error, %RuntimeError{message: "foobar"}},
      fun_throw: {:throw, "foobar"},
      fun_exit: {:exit, "foobar"},
      fun_timeout: :timeout
    ]
    |> Enum.each(fn {f, expected} ->
      assert no_task_running?()
      assert T.exec_wait({__MODULE__, f, []}, 100, success_fun, failure_fun) == expected
      assert no_task_running?()
    end)
  end
end
