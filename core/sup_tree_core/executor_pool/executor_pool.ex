# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool do
  alias Antikythera.GearName
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.ExecutorPool.AsyncJobBroker, as: JobBroker
  alias AntikytheraCore.ExecutorPool.ActionRunner
  alias AntikytheraCore.ExecutorPool.AsyncJobRunner
  alias AntikytheraCore.ExecutorPool.TimedJobStarter
  alias AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter
  alias AntikytheraCore.ExecutorPool.UsageReporter
  alias AntikytheraCore.ExecutorPool.MemcacheWriter
  alias AntikytheraCore.MetricsUploader
  alias AntikytheraCore.Ets.GearActionRunnerPools
  alias AntikytheraCore.TenantExecutorPoolsManager
  require AntikytheraCore.Logger, as: L

  @wait_time_for_broker_termination (if Mix.env() == :test, do: 100, else: TenantExecutorPoolsManager.polling_interval() * 2)

  def child_spec(args) do
    %{
      id:       __MODULE__,
      start:    {__MODULE__, :start_link, args},
      shutdown: :infinity,
      type:     :supervisor,
    }
  end

  defun start_link(epool_id :: v[EPoolId.t],
                   uploader :: v[atom | pid],
                   %EPoolSetting{n_pools_a: n_pools_a, pool_size_a: size_a, pool_size_j: size_j, ws_max_connections: ws_max}) :: {:ok, pid} do
    # Only during initialization of each ExecutorPool; allowed to call unsafe functions as long as `epool_id` argument is under control
    sup_name        = RegName.supervisor_unsafe(epool_id)
    job_pool_name   = RegName.async_job_runner_pool_unsafe(epool_id)
    queue_name      = RegName.async_job_queue_unsafe(epool_id)
    broker_name     = RegName.async_job_broker_unsafe(epool_id)
    ws_counter_name = RegName.websocket_connections_counter_unsafe(epool_id)
    memcache_name   = RegName.memcache_writer_unsafe(epool_id)

    children = [
      {PoolSup.Multi              , action_runner_pool_multi_args(epool_id, n_pools_a, size_a) },
      {PoolSup                    , async_job_runner_pool_args(epool_id, size_j, job_pool_name)},
      {JobBroker                  , [job_pool_name, queue_name, broker_name]                   },
      {TimedJobStarter            , [queue_name, uploader, epool_id]                           },
      {WebsocketConnectionsCounter, [ws_max, ws_counter_name]                                  },
      {UsageReporter              , [uploader, epool_id]                                       },
      {MemcacheWriter             , [memcache_name, epool_id]                                  },
    ]
    Supervisor.start_link(children, [strategy: :one_for_one, name: sup_name])
  end

  defp action_runner_pool_multi_args(epool_id, n_pools_a, size_a) do
    [
      GearActionRunnerPools.table_name(),
      epool_id, # key for the ETS record of this PoolSup.Multi
      n_pools_a,
      ActionRunner,
      epool_id, # arg for `ActionRunner.start_link/1`
      size_a,
      0,        # we don't use ondemand worker processes for gear actions
      [
        name:                  RegName.action_runner_pool_multi_unsafe(epool_id),
        checkout_max_duration: 60, # chosen as (1) sufficiently loger than gear action timeout (10s), (2) not too frequent
      ],
    ]
  end

  defp async_job_runner_pool_args(epool_id, size_j, job_pool_name) do
    [
      AsyncJobRunner,
      epool_id,
      0,        # we don't use reserved worker processes for async jobs
      size_j,
      [
        name:                  job_pool_name,
        checkout_max_duration: 2400, # must be longer than async job maximum duration (30m)
      ],
    ]
  end

  defun start_executor_pool(epool_id :: v[EPoolId.t], setting :: v[EPoolSetting.t]) :: :ok do
    L.info("starting executor pool for #{inspect(epool_id)}")
    case DynamicSupervisor.start_child(__MODULE__.Sup, {__MODULE__, [epool_id, MetricsUploader, setting]}) do
      {:ok, _pid}                        -> :ok
      {:error, {:already_started, _pid}} -> apply_setting(epool_id, setting)
    end
  end

  defun start_per_gear_executor_pool(gear_name :: v[GearName.t]) :: :ok do
    start_executor_pool({:gear, gear_name}, EPoolSetting.of_gear(gear_name))
  end

  defun kill_executor_pool(epool_id :: v[EPoolId.t]) :: :ok do
    try do
      Process.whereis(RegName.supervisor(epool_id))
    rescue
      ArgumentError ->
        L.error("unused executor pool ID is given to kill_executor_pool/1: #{inspect(epool_id)}")
        nil
    end
    |> case do
      nil -> :ok
      pid ->
        L.info("killing executor pool for #{inspect(epool_id)}")
        :ok = DynamicSupervisor.terminate_child(__MODULE__.Sup, pid)
        remove_job_queue(epool_id)
    end
  end

  defunp remove_job_queue(epool_id :: v[EPoolId.t]) :: :ok do
    # Remove cluster-wide job queue only when it's absolutely unnecessary.
    # Note that gear's executor pool is killed on shutdown of ErlangVM (by stop/1 of each gear application);
    # shutting-down an ErlangVM in a cluster of VMs should not remove a working job queue.
    case epool_id do
      {:gear, _}   -> :ok
      {:tenant, _} ->
        # As `AsyncJobBroker` process depends on the job queue,
        # we have to wait for terminations of all broker processes for this job queue in the cluster.
        # Note that it's OK to call `RaftFleet.remove_consensus_group/1` multiple times (once per each node).
        spawn(fn ->
          :timer.sleep(@wait_time_for_broker_termination)
          RaftFleet.remove_consensus_group(RegName.async_job_queue(epool_id))
        end)
    end
    :ok
  end

  defun apply_setting(epool_id :: v[EPoolId.t],
                      %EPoolSetting{n_pools_a: n_pools_a, pool_size_a: size_a, pool_size_j: size_j, ws_max_connections: ws_max}) :: :ok do
    L.info("changing setting of executor pool for #{inspect(epool_id)}")
    action_pool_name = RegName.action_runner_pool_multi(epool_id)
    job_pool_name    = RegName.async_job_runner_pool(epool_id)
    broker_name      = RegName.async_job_broker(epool_id)
    PoolSup.Multi.change_configuration(action_pool_name, n_pools_a, size_a, 0)
    PoolSup.change_capacity(job_pool_name, 0, size_j)
    JobBroker.notify_pool_capacity_may_have_changed(broker_name)
    WebsocketConnectionsCounter.set_max(epool_id, ws_max)
  end

  defmodule Sup do
    use DynamicSupervisor

    defun start_link([]) :: {:ok, pid} do
      DynamicSupervisor.start_link(__MODULE__, [], [name: __MODULE__])
    end

    @impl true
    def init([]) do
      DynamicSupervisor.init([strategy: :one_for_one])
    end
  end
end
