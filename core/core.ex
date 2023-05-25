# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore do
  use Application
  alias AntikytheraEal.ClusterConfiguration
  require AntikytheraCore.Logger, as: L

  defun add_translator_to_logger() :: :ok do
    Logger.add_translator({AntikytheraCore.ErlangLogTranslator, :translate})
  end

  @doc """
  Callback implementation of `Application.start/2`.

  Interdependencies between initialization steps here are crucial.
  See also `AntikytheraCore.StartupManager` for initializations after construction
  of the supervision tree.
  """
  @impl true
  def start(_type, _args) do
    add_translator_to_logger()
    # In dev or local environment, the log level is initially set to `:notice` at mix_common.exs
    # in order to avoid SASL progress reports.
    # The log level is restored to `:info` after loading antikythera.
    Logger.configure(level: :info)
    L.info("starting AntikytheraCore")
    add_gears_dir_to_erl_libs()
    AntikytheraCore.FileSetup.setup_files_and_ets_tables()
    AntikytheraCore.Config.Core.load()
    # Just to suppress log messages by `:syn.add_node_to_scopes/1`.
    if not Antikythera.Env.no_listen?() do
      calculate_connection_trial_count_from_health_check_grace_period()
      |> establish_connections_to_other_nodes()

      :syn.add_node_to_scopes([:antikythera])
    end

    L.info("activating RaftFleet")

    activate_raft_fleet(fn ->
      if not Antikythera.Env.no_listen?() do
        start_cowboy_http()
      end

      {:ok, pid} = start_sup()
      # `GearManager` and `StartupManager` must be up and running here
      AntikytheraCore.Config.Gear.load_all(0)
      L.info("started AntikytheraCore")
      {:ok, pid}
    end)
  end

  defp add_gears_dir_to_erl_libs() do
    # Set ERL_LIBS environment variable in order to load gear's code appropriately.
    # See also: http://www.erlang.org/doc/man/code.html#lib_dir-1
    dirs = (System.get_env("ERL_LIBS") || "") |> String.split(":")
    new_value = [AntikytheraCore.Version.Artifact.gears_dir() | dirs] |> Enum.join(":")
    System.put_env("ERL_LIBS", new_value)
  end

  @connection_retrial_interval_in_milliseconds 5_000

  defunpt calculate_connection_trial_count_from_health_check_grace_period() :: pos_integer do
    connection_retrial_interval_in_seconds = @connection_retrial_interval_in_milliseconds / 1000

    (ClusterConfiguration.health_check_grace_period_in_seconds() /
       connection_retrial_interval_in_seconds)
    |> trunc()
    |> max(1)
  end

  defp establish_connections_to_other_nodes(tries_remaining) do
    if tries_remaining == 0 do
      raise "cannot establish connections to other nodes!"
    else
      case AntikytheraCore.Cluster.connect_to_other_nodes_on_start() do
        {:ok, true} ->
          :ok

        _otherwise ->
          L.info("failed to establish connections to other nodes; retry afterward")
          :timer.sleep(@connection_retrial_interval_in_milliseconds)
          establish_connections_to_other_nodes(tries_remaining - 1)
      end
    end
  end

  defp activate_raft_fleet(f) do
    :ok = RaftFleet.activate(ClusterConfiguration.zone_of_this_host())

    try do
      f.()
    catch
      type, reason ->
        # When an error occurred in the core part of `start/2`, try to cleanup this node so that
        # existing consensus groups (especially `RaftFleet.Cluster`) are not disturbed by the failing node.
        RaftFleet.deactivate()
        # wait for a moment in the hope that deactivation succeeds...
        :timer.sleep(10_000)
        {:error, {type, reason}}
    end
  end

  defp start_cowboy_http() do
    dispatch_rules = AntikytheraCore.Handler.CowboyRouting.compiled_routes([], false)

    ranch_transport_opts = %{
      # limit is imposed on a per-executor pool basis
      max_connections: :infinity,
      socket_opts: [port: Antikythera.Env.port_to_listen()]
    }

    cowboy_proto_opts = %{
      # timeout of a request with no data transfer; must be sufficiently longer than the gear action timeout (10_000)
      idle_timeout: 30_000,
      # timeout of a connection with no requests; this should be longer than LB's idle timeout
      request_timeout: 120_000,
      env: %{dispatch: dispatch_rules},
      stream_handlers: [:cowboy_compress_h, :cowboy_stream_h]
    }

    {:ok, _} =
      :cowboy.start_clear(:antikythera_http_listener, ranch_transport_opts, cowboy_proto_opts)
  end

  defp start_sup() do
    children = [
      AntikytheraCore.ErrorCountsAccumulator,
      {AntikytheraCore.Alert.Manager, [:antikythera, AntikytheraCore.Alert.Manager]},
      AntikytheraCore.GearManager,
      AntikytheraCore.ClusterHostsPoller,
      AntikytheraCore.ClusterNodesConnector,
      AntikytheraCore.MnesiaNodesCleaner,
      AntikytheraCore.StartupManager,
      AntikytheraCore.TerminationManager,
      AntikytheraCore.CoreConfigPoller,
      AntikytheraCore.GearConfigPoller,
      AntikytheraCore.VersionUpgradeTaskQueue,
      AntikytheraCore.VersionSynchronizer,
      AntikytheraCore.StaleGearArtifactCleaner,
      {AntikytheraCore.MetricsUploader, [:antikythera, AntikytheraCore.MetricsUploader]},
      {AntikytheraCore.SystemMetricsReporter, [AntikytheraCore.MetricsUploader]},
      AntikytheraCore.ExecutorPool.Sup,
      AntikytheraCore.GearExecutorPoolsManager,
      AntikytheraCore.TenantExecutorPoolsManager,
      AntikytheraCore.TmpdirTracker,
      AntikytheraCore.ExecutorPool.AsyncJobLog.Writer
    ]

    children_for_dev =
      if Antikythera.Env.runtime_env() == :prod,
        do: [],
        else: [
          Supervisor.child_spec(
            {
              AntikytheraCore.PeriodicLog.Writer,
              [AntikytheraCore.PeriodicLog.ReductionBuilder, "reduction"]
            },
            id: :periodic_log_writer_1
          ),
          Supervisor.child_spec(
            {
              AntikytheraCore.PeriodicLog.Writer,
              [AntikytheraCore.PeriodicLog.MessageBuilder, "message"]
            },
            id: :periodic_log_writer_2
          )
        ]

    opts = [strategy: :one_for_one, name: AntikytheraCore.Supervisor]
    Supervisor.start_link(children ++ children_for_dev, opts)
  end
end
