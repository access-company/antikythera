# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.RegisteredName do
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  @prefix "AntikytheraCore.ExecutorPool"

  defun supervisor(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(supervisor_parts(epool_id))
  end

  defun supervisor_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(supervisor_parts(epool_id))
  end

  defunp supervisor_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "Sup")
  end

  defun action_runner_pool_multi(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(action_runner_pool_multi_parts(epool_id))
  end

  defun action_runner_pool_multi_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(action_runner_pool_multi_parts(epool_id))
  end

  defunp action_runner_pool_multi_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "ActionRunnerPoolMulti")
  end

  defun http_streaming_runner_pool_multi(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(http_streaming_runner_pool_multi_parts(epool_id))
  end

  defun http_streaming_runner_pool_multi_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(http_streaming_runner_pool_multi_parts(epool_id))
  end

  defunp http_streaming_runner_pool_multi_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "HttpStreamingRunnerPoolMulti")
  end

  defun async_job_runner_pool(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(async_job_runner_pool_parts(epool_id))
  end

  defun async_job_runner_pool_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(async_job_runner_pool_parts(epool_id))
  end

  defunp async_job_runner_pool_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "AsyncJobRunnerPool")
  end

  defun async_job_broker(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(async_job_broker_parts(epool_id))
  end

  defun async_job_broker_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(async_job_broker_parts(epool_id))
  end

  defunp async_job_broker_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "AsyncJobBroker")
  end

  defun websocket_connections_counter(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(websocket_connections_counter_parts(epool_id))
  end

  defun websocket_connections_counter_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(websocket_connections_counter_parts(epool_id))
  end

  defunp websocket_connections_counter_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "WebsocketConnectionsCounter")
  end

  defun memcache_writer(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(memcache_writer_parts(epool_id))
  end

  defun memcache_writer_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(memcache_writer_parts(epool_id))
  end

  defunp memcache_writer_parts(epool_id :: v[EPoolId.t()]) :: [String.t()] do
    common_parts(epool_id, "MemcacheWriter")
  end

  defunp common_parts(epool_id :: EPoolId.t(), suffix :: String.t()) :: [String.t()] do
    {:gear, gear_name}, suffix -> ["#{@prefix}.Gear", Atom.to_string(gear_name), suffix]
    {:tenant, tenant_id}, suffix -> ["#{@prefix}.Tenant", tenant_id, suffix]
  end

  # Async job queues are treated a bit differently, as they are cluster-wide.
  # `:async_job_queue_name_prefix` is introduced here so that some existing deployments can preserve the historic name of job queues.
  # New deployments should be OK with the default value.
  @job_queue_prefix Application.compile_env(:antikythera, :async_job_queue_name_prefix, @prefix)

  defun async_job_queue(epool_id :: v[EPoolId.t()]) :: atom do
    Module.safe_concat(async_job_queue_parts(epool_id))
  end

  defun async_job_queue_unsafe(epool_id :: v[EPoolId.t()]) :: atom do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(async_job_queue_parts(epool_id))
  end

  defunp async_job_queue_parts(epool_id :: EPoolId.t()) :: [String.t()] do
    {:gear, gear_name} ->
      ["#{@job_queue_prefix}.Gear", Atom.to_string(gear_name), "AsyncJobQueue"]

    {:tenant, tenant_id} ->
      ["#{@job_queue_prefix}.Tenant", tenant_id, "AsyncJobQueue"]
  end
end
