# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

# Change in `mix_common.exs` should trigger full compilation of the antikythera project
# (see also `Mix.Tasks.Compile.PropagateFileModifications`)
mix_path        = Path.join(__DIR__, "mix.exs"       )
mix_common_path = Path.join(__DIR__, "mix_common.exs")
if File.stat!(mix_path).mtime < File.stat!(mix_common_path).mtime do
  File.touch!(mix_path)
end

# It's allowed to load `mix_common.exs` multiple times in case it is changed after successful deps.update.
# We temporarily disable "redefining module" warning.
Code.compiler_options(ignore_module_conflict: true)
Code.load_file(mix_common_path)
Code.compiler_options(ignore_module_conflict: false)

# Cleanup too-old entries in tmp/ (if any)
case File.ls(Path.join(__DIR__, "tmp")) do
  {:error, :enoent} -> :ok
  {:ok, entries}    ->
    one_month_ago_in_seconds = System.system_time(:seconds) - 30 * 24 * 60 * 60
    Enum.each(entries, fn entry ->
      path = Path.join([__DIR__, "tmp", entry])
      if File.stat!(path, [time: :posix]).mtime < one_month_ago_in_seconds do
        IO.puts("Removing old entry in tmp/ : #{path}")
        File.rm_rf!(path)
      end
    end)
end

defmodule Antikythera.Mixfile do
  use Mix.Project

  @github_url "https://github.com/access-company/antikythera"

  def project() do
    [
      app:             :antikythera,
      version:         Antikythera.MixCommon.version_with_last_commit_info("0.1.0"),
      elixirc_paths:   elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps:            deps(),
      source_url:      @github_url,
      homepage_url:    @github_url,
    ] ++ Keyword.update!(Antikythera.MixCommon.common_project_settings(), :docs, &(&1 ++ docs()))
  end

  def application() do
    [
      mod:          {AntikytheraCore, []},
      applications: Antikythera.MixCommon.antikythera_runtime_dependency_applications(deps()),
    ]
  end

  defp elixirc_paths() do
    default    = ["lib", "core", "eal"]
    additional = if Antikythera.MixCommon.on_cloud?(), do: [], else: ["local"]
    default ++ additional
  end

  defp deps() do
    # In order to uniquely determine which versions of libraries are used by gears,
    # antikythera explicitly specify exact versions of all deps, including indirect ones
    # (otherwise versions of indirect deps become ambiguous in gear projects).
    [
      # The following libraries are included to realize antikythera's features;
      # these are considered as implementation details of antikythera and thus must not be used by gear implementations.
      {:cowboy      , "2.2.2" , [antikythera_internal: true]},
      {:cowlib      , "2.1.0" , [antikythera_internal: true]},
      {:hackney     , "1.9.0" , [antikythera_internal: true]},
      {:calliope    , "0.4.1" , [antikythera_internal: true]}, # 0.4.2 is broken!
      {:pool_sup    , "0.4.0" , [antikythera_internal: true]},
      {:raft_fleet  , "0.8.2" , [antikythera_internal: true]},
      {:rafted_value, "0.9.2" , [antikythera_internal: true]},
      {:syn         , "1.6.3" , [antikythera_internal: true]},
      {:fast_xml    , "1.1.29", [antikythera_internal: true, manager: :rebar3]}, # :fast_xml contains not only rebar.config but also mix.exs, but we don't use it
      {:recon       , "2.3.5" , [antikythera_internal: true]},
      {:relx        , "3.23.1", [antikythera_internal: true, only: :prod, runtime: false]}, # only to generate release

      # The following libraries are used by both antikythera itself and gears.
      {:poison , "2.2.0" },
      {:gettext, "0.15.0"},
      {:croma  , "0.9.3" },
      {:pbkdf2 , "2.0.0" },

      # tools
      {:exsync          , "0.2.3" , [only: :dev ]},
      {:ex_doc          , "0.18.3", [only: :dev , runtime: false]},
      {:dialyze         , "0.2.1" , [only: :dev , runtime: false]},
      {:credo           , "0.8.10", [only: :dev , runtime: false]},
      {:mix_test_watch  , "0.6.0" , [only: :dev , runtime: false]},
      {:meck            , "0.8.9" , [only: :test]},
      {:mox             , "0.3.2" , [only: :test]},
      {:excoveralls     , "0.8.1" , [only: :test]},
      {:stream_data     , "0.4.2" , [only: :test]},
      {:websocket_client, "1.3.0" , [only: :test]}, # as a websocket client implementation to use during test (including upgrade_compatibility_test)

      # indirect deps
      {:ranch              , "1.4.0" , [indirect: true]}, # cowboy
      {:certifi            , "2.0.0" , [indirect: true]}, # hackney
      {:ssl_verify_fun     , "1.1.1" , [indirect: true]}, # hackney
      {:idna               , "5.1.0" , [indirect: true]}, # hackney
      {:metrics            , "1.0.1" , [indirect: true]}, # hackney
      {:mimerl             , "1.0.2" , [indirect: true]}, # hackney
      {:unicode_util_compat, "0.3.1" , [indirect: true]}, # hackney
      {:p1_utils           , "1.0.11", [indirect: true]}, # fast_xml
      {:bbmustache         , "1.0.4" , [indirect: true, only: :prod, runtime: false]}, # relx
      {:cf                 , "0.2.2" , [indirect: true, only: :prod, runtime: false]}, # relx
      {:erlware_commons    , "1.0.0" , [indirect: true, only: :prod, runtime: false]}, # relx
      {:getopt             , "0.8.2" , [indirect: true, only: :prod, runtime: false]}, # relx
      {:providers          , "1.6.0" , [indirect: true, only: :prod, runtime: false]}, # relx

      # indirect tool deps
      {:bunt       , "0.2.0", [indirect: true, only: :dev ]}, # credo
      {:earmark    , "1.2.5", [indirect: true, only: :dev ]}, # ex_doc
      {:file_system, "0.2.4", [indirect: true, only: :dev ]}, # exsync
      {:fs         , "0.9.1", [indirect: true, only: :dev ]}, # mix_test_watch, 0.9.2 is available on hex.pm but it's broken!
      {:exjsx      , "4.0.0", [indirect: true, only: :test]}, # excoveralls
      {:jsx        , "2.8.3", [indirect: true, only: :test]}, # excoveralls
    ]
  end

  defp docs() do
    [
      assets: "doc/assets",
      extras: [
        "README.md",
        "STYLE_GUIDE.md",
        "CONTRIBUTING.md",
        "doc/getting_started.md",
        "doc/development_environment.md",
        "doc/library_dependencies.md",
        {"doc/gear_developers/README.md", [filename: "gear_developers"]},
        "doc/gear_developers/deployment.md",
        "doc/gear_developers/routing.md",
        "doc/gear_developers/g2g.md",
        "doc/gear_developers/controller.md",
        "doc/gear_developers/dynamic_html.md",
        "doc/gear_developers/websocket.md",
        "doc/gear_developers/async_job.md",
        "doc/gear_developers/executor_pool.md",
        "doc/gear_developers/logging.md",
        "doc/gear_developers/metrics_reporting.md",
        "doc/gear_developers/alerting.md",
        "doc/gear_developers/gear_config.md",
        "doc/gear_developers/i18n.md",
        "doc/gear_developers/testing.md",
        "doc/gear_developers/must_nots.md",
      ],
      groups_for_extras: [
        "Basics":                              Path.wildcard("doc/*.md"),
        "Antikythera Instance Administration": Path.wildcard("doc/instance_administrators/*.md"),
        "Gear Development":                    Path.wildcard("doc/gear_developers/*.md"),
      ],
    ]
  end
end
