# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore do
  use Application
  require AntikytheraCore.Logger, as: L

  @impl true
  def start(_type, _args) do
    add_gears_dir_to_erl_libs()
    AntikytheraCore.FileSetup.setup_files_and_ets_tables()
    AntikytheraCore.Config.Core.load()
    if not Antikythera.Env.no_listen?() do # Just to suppress log messages by :syn.init()
      establish_connections_to_other_nodes()
      :syn.init()
    end
    activate_raft_fleet(fn ->
      if not Antikythera.Env.no_listen?() do
        start_cowboy_http()
      end
      {:ok, pid} = start_sup()
      AntikytheraCore.Config.Gear.load_all(0) # `GearManager` and `StartupManager` must be up and running here
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

  defp establish_connections_to_other_nodes(tries_remaining \\ 3) do
    if tries_remaining == 0 do
      raise "cannot establish connections to other nodes!"
    else
      case AntikytheraCore.Cluster.connect_to_other_nodes_on_start() do
        {:ok, true} -> :ok
        _otherwise  ->
          L.info("failed to establish connections to other nodes; retry afterward")
          :timer.sleep(5_000)
          establish_connections_to_other_nodes(tries_remaining - 1)
      end
    end
  end

  defp activate_raft_fleet(f) do
    :ok = RaftFleet.activate(AntikytheraEal.ClusterConfiguration.zone_of_this_host())
    try do
      f.()
    catch
      type, reason ->
        # When an error occurred in the core part of `start/2`, try to cleanup this node so that
        # existing consensus groups (especially `RaftFleet.Cluster`) are not disturbed by the failing node.
        RaftFleet.deactivate()
        :timer.sleep(10_000) # wait for a moment in the hope that deactivation succeeds...
        {:error, {type, reason}}
    end
  end

  defp start_cowboy_http() do
    dispatch_rules = AntikytheraCore.Handler.CowboyRouting.compiled_routes([], false)
    ranch_transport_opts = %{
      max_connections: :infinity, # limit is imposed on a per-executor pool basis
      socket_opts:     [port: Antikythera.Env.port_to_listen()],
    }
    cowboy_proto_opts = %{
      idle_timeout:    120_000, # increase idle timeout of keepalive connections; this should be longer than LB's idle timeout
      request_timeout: 30_000,  # timeout must be sufficiently longer than the gear action timeout (10_000)
      env:             %{dispatch: dispatch_rules},
      stream_handlers: [:cowboy_compress_h, :cowboy_stream_h],
    }
    {:ok, _} = :cowboy.start_clear(:antikythera_http_listener, ranch_transport_opts, cowboy_proto_opts)
  end

  defp start_sup() do
    children = [
      AntikytheraCore.ErrorCountsAccumulator    ,
      {AntikytheraCore.Alert.Manager            , [:antikythera, AntikytheraCore.Alert.Manager]},
      AntikytheraCore.GearManager               ,
      AntikytheraCore.ClusterHostsPoller        ,
      AntikytheraCore.ClusterNodesConnector     ,
      AntikytheraCore.MnesiaNodesCleaner        ,
      AntikytheraCore.StartupManager            ,
      AntikytheraCore.TerminationManager        ,
      AntikytheraCore.CoreConfigPoller          ,
      AntikytheraCore.GearConfigPoller          ,
      AntikytheraCore.VersionUpgradeTaskQueue   ,
      AntikytheraCore.VersionSynchronizer       ,
      AntikytheraCore.StaleGearArtifactCleaner  ,
      {AntikytheraCore.MetricsUploader          , [:antikythera, AntikytheraCore.MetricsUploader]},
      {AntikytheraCore.SystemMetricsReporter    , [AntikytheraCore.MetricsUploader]},
      AntikytheraCore.ExecutorPool.Sup          ,
      AntikytheraCore.GearExecutorPoolsManager  ,
      AntikytheraCore.TenantExecutorPoolsManager,
      AntikytheraCore.TmpdirTracker             ,
    ]
    opts = [strategy: :one_for_one, name: AntikytheraCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
