# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Httpc do
  @moduledoc """
  Management of [hackney](https://github.com/benoitc/hackney) connection pools dedicated to executor pools.

  Each executor pool (gear/tenant) owns a hackney connection pool so that outbound HTTP requests made on
  its behalf (via `Antikythera.Httpc`'s `:pool` option) don't share TCP connections across executor pools.

  - `AntikytheraCore.ExecutorPool` creates/resizes/stops the connection pool along the executor pool
    lifecycle by calling `set_connection_pool/2` and `stop_connection_pool/1`.
  - `Antikythera.Httpc` resolves the pool name for a request via `connection_pool_name/1`.
  """

  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting

  # Headroom multiplier applied to an executor pool's worker concurrency to size its connection pool
  # (keep-alive reuse, connections to multiple upstream hosts and transient overlap while connections
  # are recycled).
  @connection_pool_size_factor 2

  @doc """
  Name of the hackney connection pool dedicated to the given executor pool.

  `Antikythera.Httpc` passes this name as hackney's `:pool` option so that a request is served by the
  executor pool's dedicated connection pool.
  """
  defun connection_pool_name(epool_id :: v[EPoolId.t()]) :: v[String.t()] do
    EPoolId.to_string(epool_id)
  end

  @doc """
  Size (`max_connections`) of the connection pool dedicated to an executor pool.

  Sized to the executor pool's total worker concurrency (action + http-streaming + async-job workers),
  multiplied by `#{@connection_pool_size_factor}` for headroom.
  """
  defun connection_pool_size(setting :: v[EPoolSetting.t()]) :: v[pos_integer] do
    %EPoolSetting{
      n_pools_a: n_pools_a,
      pool_size_a: pool_size_a,
      n_pools_s: n_pools_s,
      pool_size_s: pool_size_s,
      pool_size_j: pool_size_j
    } = setting

    size =
      (n_pools_a * pool_size_a + n_pools_s * pool_size_s + pool_size_j) *
        @connection_pool_size_factor

    # Worker pool sizes are `Croma.NonNegInteger`, so `size` can be 0; keep at least 1 connection.
    max(size, 1)
  end

  @doc """
  Creates (sizing it on creation) or resizes the connection pool dedicated to the executor pool.

  The pool is sized by `connection_pool_size/1`. `start_pool/2` sizes the pool when it is first created
  and is a no-op if the pool already exists, while `set_max_connections/2` resizes an already-existing
  pool when the executor pool's setting changes.
  """
  defun set_connection_pool(epool_id :: v[EPoolId.t()], setting :: v[EPoolSetting.t()]) :: :ok do
    name = connection_pool_name(epool_id)
    size = connection_pool_size(setting)
    _ = :hackney_pool.start_pool(name, max_connections: size)
    _ = :hackney_pool.set_max_connections(name, size)
    :ok
  end

  @doc """
  Stops the connection pool dedicated to the executor pool. No-op if the pool does not exist.
  """
  defun stop_connection_pool(epool_id :: v[EPoolId.t()]) :: :ok do
    _ = :hackney_pool.stop_pool(connection_pool_name(epool_id))
    :ok
  end

  @typedoc """
  Current connection counts of a hackney connection pool.

  - `:max`     - configured `max_connections`, i.e. the pool's capacity
  - `:in_use`  - connections currently checked out for in-flight requests
  - `:free`    - idle keep-alive connections available for reuse
  """
  @type pool_stats :: %{
          max: non_neg_integer,
          in_use: non_neg_integer,
          free: non_neg_integer
        }

  @doc """
  Current connection counts of the executor pool's dedicated hackney connection pool
  (see `t:pool_stats/0`).

  Returns `nil` if the pool does not exist (e.g. it has not been created yet or has already been
  stopped).
  """
  defun connection_pool_stats(epool_id :: v[EPoolId.t()]) :: nil | pool_stats do
    pool_stats(connection_pool_name(epool_id))
  end

  @doc """
  Current connection counts of hackney's shared default connection pool (see `t:pool_stats/0`).

  This is the pool used for outbound requests that don't specify an executor pool's dedicated pool
  (i.e. `Antikythera.Httpc` calls made without the `:pool` option). Returns `nil` if the default
  pool has not been created yet (hackney starts it lazily on its first use).
  """
  defun default_connection_pool_stats() :: nil | pool_stats do
    pool_stats(:default)
  end

  # `name` is a per-executor-pool pool name (`String.t()`) or hackney's shared default pool (`:default`).
  defunp pool_stats(name :: String.t() | :default) :: nil | pool_stats do
    case :hackney_pool.find_pool(name) do
      pid when is_pid(pid) ->
        stats = :hackney_pool.get_stats(name)

        %{
          max: Keyword.fetch!(stats, :max),
          in_use: Keyword.fetch!(stats, :in_use_count),
          free: Keyword.fetch!(stats, :free_count)
        }

      _ ->
        nil
    end
  end
end
