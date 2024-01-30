# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

ExUnit.start()

ExUnit.after_suite(fn _result ->
  Path.join([__DIR__, "..", "_build", "test", "log", "antikythera"])
  |> Path.expand()
  |> Path.join("{async_job,message,reduction}.log.*.gz")
  |> Path.wildcard()
  |> Enum.each(fn path -> :ok = File.rm(path) end)
end)

defmodule ExecutorPoolHelper do
  import ExUnit.Assertions
  alias Antikythera.Test.{ProcessHelper, GenServerHelper}
  alias AntikytheraCore.ExecutorPool
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName

  def assert_current_setting(epool_id, na, sa, sj, ws) do
    action_name = RegName.action_runner_pool_multi(epool_id)

    action_pools =
      Supervisor.which_children(action_name) |> Enum.map(fn {_, pid, _, _} -> pid end)

    assert length(action_pools) == na

    Enum.each(action_pools, fn p ->
      %{reserved: ^sa, ondemand: 0} = PoolSup.status(p)
    end)

    task_name = RegName.async_job_runner_pool(epool_id)
    %{reserved: 0, ondemand: ^sj} = PoolSup.status(task_name)

    ws_counter_name = RegName.websocket_connections_counter(epool_id)
    %{max: ^ws} = :sys.get_state(ws_counter_name)
  end

  def hurry_action_pool_multi(epool_id) do
    # Send internal message to `PoolSup.Multi` so that it terminates child pools
    action_name = RegName.action_runner_pool_multi(epool_id)
    GenServerHelper.send_message_and_wait(action_name, :check_progress_of_termination)
  end

  def wait_until_async_job_queue_added(epool_id, remaining_tries \\ 10) do
    if remaining_tries == 0 do
      flunk("job queue for #{inspect(epool_id)} is not added!")
    else
      :timer.sleep(100)
      queue_name = RegName.async_job_queue(epool_id)

      if match?(%{^queue_name => 3}, RaftFleet.consensus_groups()) && Process.whereis(queue_name) do
        :ok
      else
        wait_until_async_job_queue_added(epool_id, remaining_tries - 1)
      end
    end
  end

  def kill_and_wait(epool_id) do
    kill_and_wait(epool_id, fn ->
      assert ExecutorPool.kill_executor_pool(epool_id) == :ok
    end)
  end

  def kill_and_wait(epool_id, kill_fun) do
    queue_name = RegName.async_job_queue(epool_id)
    queue_pid = Process.whereis(queue_name)
    assert queue_pid
    kill_fun.()

    case epool_id do
      {:gear, _} -> assert RaftFleet.remove_consensus_group(queue_name) == :ok
      # job queue is removed asynchronously; wait until it's removed before sending `:adjust_members`
      {:tenant, _} -> :timer.sleep(150)
    end

    # accelerate termination of consensus member process
    send(RaftFleet.Manager, :adjust_members)
    ProcessHelper.monitor_wait(queue_pid)
    # discard all generated snapshot & log files of async job queue
    persist_dir =
      Path.join(AntikytheraCore.Path.raft_persistence_dir_parent(), Atom.to_string(queue_name))

    File.rm_rf!(persist_dir)
  end
end
