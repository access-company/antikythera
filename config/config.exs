# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Mix.Config

# Limit port range to be used for ErlangVM-to-ErlangVM communications
config :kernel, [
  inet_dist_listen_min: 6000,
  inet_dist_listen_max: 7999,
]

# SASL logs are handled by :logger
config :sasl, [
  sasl_error_logger: false,
]

config :logger, [
  level:               :info,
  utc_log:             true,
  handle_sasl_reports: true,
  translators:         [{AntikytheraCore.ErlangLogTranslator, :translate}],
  backends:            [:console, AntikytheraCore.Alert.LoggerBackend],
  console: [
    format:   "$dateT$time+00:00 [$level$levelpad] $metadata$message\n",
    metadata: [:module],
  ],
]

config :raft_fleet, [
  per_member_options_maker: AntikytheraCore.AsyncJob.RaftOptionsMaker,
]

# Auxiliary variables
repo_tmp_dir_basename = if System.get_env("ANTIKYTHERA_COMPILE_ENV") == "local", do: "local", else: :os.getpid()
repo_tmp_dir = Path.join([__DIR__, "..", "tmp", repo_tmp_dir_basename]) |> Path.expand()

config :antikythera, [
  # Name of the OTP application that runs as an antikythera instance.
  antikythera_instance_name: :antikythera, # `:antikythera` is used here only for testing.

  # Directory (which can be in a NFS volume) where antikythera's configuration files, build artifacts, etc. are stored.
  antikythera_root_dir: Path.join(repo_tmp_dir, "root"),

  # Directory where `Antikythera.Tmpdir.make/2` creates temporary workspaces for gear implementations.
  gear_tmp_dir: Path.join(repo_tmp_dir, "gear_tmp"),

  # Directory where log/snapshot files of persistent Raft consensus groups are stored.
  # (this is used by `AntikytheraCore.AsyncJob.RaftOptionsMaker`).
  raft_persistence_dir_parent: Path.join(repo_tmp_dir, "raft_fleet"),

  # Keyword list of deployments, where each deployment is a cluster of ErlangVMs to run an antikythera instance.
  # Each key is the name (atom) of a deployment and each value is the base domain of the deployment.
  # One can interact with a gear running in a deployment by accessing the subdomain of the base domain.
  # (To run blackbox tests against deployments, it's necessary to list all existing deployments here.)
  deployments: [
    dev:  "antikytheradev.example.com",
    prod: "antikythera.example.com"   ,
  ],

  # URL of Content Delivery Network for static assets (such as CSS, JS, etc.).
  asset_cdn_endpoint: nil,

  # Whether to include detailed information about request and stacktrace in response body
  # returned by the default error handler for debugging purpose.
  # Note that gears using their own custom error handlers are not affected by this configuration item.
  return_detailed_info_on_error?: true,

  # Alert settings.
  alert: [
    email: [
      from: "antikythera@example.com",
    ],
  ],

  # Pluggable modules that implement `AntikytheraEal.*.Behaviour` behaviours.
  eal_impl_modules: [
    cluster_configuration: AntikytheraEal.ClusterConfiguration.StandAlone,
    log_storage:           AntikytheraEal.LogStorage.FileSystem          ,
    metrics_storage:       AntikytheraEal.MetricsStorage.Memory          ,
    alert_mailer:          AntikytheraEal.AlertMailer.MemoryInbox        ,
    asset_storage:         AntikytheraEal.AssetStorage.NoOp              ,
  ],
]
