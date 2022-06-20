# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

# Change in `mix_common.exs` should trigger full compilation of the antikythera project
# (see also `Mix.Tasks.Compile.PropagateFileModifications`)
mix_path = Path.join(__DIR__, "mix.exs")
mix_common_path = Path.join(__DIR__, "mix_common.exs")

if File.stat!(mix_path).mtime < File.stat!(mix_common_path).mtime do
  File.touch!(mix_path)
end

# It's allowed to load `mix_common.exs` multiple times in case it is changed after successful deps.update.
# We temporarily disable "redefining module" warning.
Code.compiler_options(ignore_module_conflict: true)
Code.require_file(mix_common_path)
Code.compiler_options(ignore_module_conflict: false)

# Cleanup too-old entries in tmp/ (if any)
case File.ls(Path.join(__DIR__, "tmp")) do
  {:error, :enoent} ->
    :ok

  {:ok, entries} ->
    one_day_ago_in_seconds = System.system_time(:second) - 24 * 60 * 60

    Enum.each(entries, fn entry ->
      path = Path.join([__DIR__, "tmp", entry])

      if File.stat!(path, time: :posix).mtime < one_day_ago_in_seconds do
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
      app: :antikythera,
      version: Antikythera.MixCommon.version_with_last_commit_info("0.4.1"),
      elixirc_paths: elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @github_url,
      homepage_url: @github_url,
      description: "An Elixir framework to build your own in-house PaaS (Platform as a Service).",
      package: package(),
      docs: docs()
    ] ++ Antikythera.MixCommon.common_project_settings()
  end

  def application() do
    [
      mod: {AntikytheraCore, []},
      applications:
        Antikythera.MixCommon.antikythera_runtime_dependency_applications(deps()) ++
          Application.fetch_env!(:antikythera, :required_applications)
    ]
  end

  defp elixirc_paths() do
    default = ["lib", "core", "eal"]

    additional =
      if System.get_env("ANTIKYTHERA_COMPILE_ENV") in [nil, "local"], do: ["local"], else: []

    default ++ additional
  end

  defp deps() do
    # In order to uniquely determine which versions of libraries are used by gears,
    # antikythera explicitly specify exact versions of all deps, including indirect ones
    # (otherwise versions of indirect deps become ambiguous in gear projects).
    [
      # The following libraries are included to realize antikythera's features;
      # these are considered as implementation details of antikythera and thus must not be used by gear implementations.
      {:cowboy, "2.6.3", [antikythera_internal: true]},
      {:cowlib, "2.7.3", [antikythera_internal: true]},
      {:hackney, "1.15.2", [antikythera_internal: true]},
      # 0.4.2 is broken!
      {:calliope, "0.4.1", [antikythera_internal: true]},
      {:pool_sup, "0.6.1", [antikythera_internal: true]},
      {:raft_fleet, "0.10.1", [antikythera_internal: true]},
      {:rafted_value, "0.11.1", [antikythera_internal: true]},
      {:syn, "1.6.3", [antikythera_internal: true]},
      {:fast_xml, "1.1.48", [antikythera_internal: true]},
      {:foretoken, "0.3.0", [antikythera_internal: true]},
      {:recon, "2.5.1", [antikythera_internal: true]},
      # only to generate release
      {:relx, "3.33.0", [antikythera_internal: true, only: :prod, runtime: false]},

      # The following libraries are used by both antikythera itself and gears.
      {:poison, "2.2.0"},
      {:jason, "1.2.2"},
      {:gettext, "0.17.1"},
      {:croma, "0.10.2"},

      # tools
      {:exsync, "0.2.4", [only: :dev]},
      # 0.23.0 requires Elixir 1.10 or later
      {:ex_doc, "0.22.2", [only: :dev, runtime: false]},
      {:dialyxir, "1.1.0", [only: :dev, runtime: false]},
      {:credo, "1.6.1", [only: :dev, runtime: false]},
      {:mix_test_watch, "1.1.0", [only: :dev, runtime: false]},
      {:meck, "0.9.2", [only: :test]},
      # 0.13.0 requires hackney ~> 1.16
      {:excoveralls, "0.12.0", [only: :test]},
      {:stream_data, "0.5.0", [only: :test]},
      # as a websocket client implementation to use during test (including upgrade_compatibility_test)
      # 1.4.0 requires OTP 21 or later
      {:websocket_client, "1.3.0", [only: :test]},
      # to test `Antikythera.Crypto.Aes`
      # TODO: replace by `:crypto.pbkdf2_hmac/5` which is introduced by OTP 24.2
      {:pbkdf2, "2.0.0", [only: :test]},

      # indirect deps
      # cowboy
      {:ranch, "1.7.1", [indirect: true]},
      # hackney
      {:certifi, "2.5.1", [indirect: true]},
      # hackney
      {:ssl_verify_fun, "1.1.5", [indirect: true]},
      # hackney
      {:idna, "6.0.0", [indirect: true]},
      # hackney
      {:metrics, "1.0.1", [indirect: true]},
      # hackney
      {:mimerl, "1.2.0", [indirect: true]},
      # certifi
      {:parse_trans, "3.3.0", [indirect: true]},
      # idna
      {:unicode_util_compat, "0.4.1", [indirect: true]},
      # fast_xml
      {:p1_utils, "1.0.23", [indirect: true]},
      # relx
      {:bbmustache, "1.5.0", [indirect: true, only: :prod, runtime: false]},
      # relx
      {:cf, "0.3.1", [indirect: true, only: :prod, runtime: false]},
      # relx
      {:erlware_commons, "1.2.0", [indirect: true, only: :prod, runtime: false]},
      # relx
      {:getopt, "1.0.1", [indirect: true, only: :prod, runtime: false]},
      # relx
      {:providers, "1.8.0", [indirect: true, only: :prod, runtime: false]},

      # indirect tool deps
      # credo
      {:bunt, "0.2.0", [indirect: true, only: :dev]},
      # ex_doc
      {:earmark, "1.4.10", [indirect: true, only: :dev]},
      # earmark
      {:earmark_parser, "1.4.10", [indirect: true, only: :dev]},
      # ex_doc
      {:makeup_elixir, "0.14.1", [indirect: true, only: :dev]},
      # makeup_elixir
      {:makeup, "1.0.3", [indirect: true, only: :dev]},
      # makeup
      {:nimble_parsec, "0.6.0", [indirect: true, only: :dev]},
      # credo, exsync and mix_test_watch
      {:file_system, "0.2.10", [indirect: true, only: :dev]},
      # dialyxir
      {:erlex, "0.2.6", [indirect: true, only: :dev]}
    ]
  end

  defp package() do
    [
      licenses: ["Apache 2.0"],
      maintainers: ["antikythera-gr@access-company.com"],
      links: %{"GitHub" => @github_url},
      files: [
        "config",
        "core",
        "eal",
        "lib",
        "local",
        "priv",
        "rel",
        "CHANGELOG.md",
        "LICENSE",
        "mix_common.exs",
        "mix.exs",
        "README.md"
      ]
    ]
  end

  defp docs() do
    [
      assets: "doc_src/assets",
      extras: [
        "README.md",
        "STYLE_GUIDE.md",
        "CONTRIBUTING.md",
        "doc_src/getting_started.md",
        "doc_src/development_environment.md",
        "doc_src/library_dependencies.md",
        {:"doc_src/gear_developers/README.md", [filename: "gear_developers"]},
        "doc_src/gear_developers/deployment.md",
        "doc_src/gear_developers/routing.md",
        "doc_src/gear_developers/g2g.md",
        "doc_src/gear_developers/controller.md",
        "doc_src/gear_developers/dynamic_html.md",
        "doc_src/gear_developers/websocket.md",
        "doc_src/gear_developers/async_job.md",
        "doc_src/gear_developers/executor_pool.md",
        "doc_src/gear_developers/logging.md",
        "doc_src/gear_developers/metrics_reporting.md",
        "doc_src/gear_developers/alerting.md",
        "doc_src/gear_developers/gear_config.md",
        "doc_src/gear_developers/i18n.md",
        "doc_src/gear_developers/testing.md",
        "doc_src/gear_developers/must_nots.md"
      ],
      groups_for_extras: [
        Basics: Path.wildcard("doc_src/*.md"),
        "Antikythera Instance Administration":
          Path.wildcard("doc_src/instance_administrators/*.md"),
        "Gear Development": Path.wildcard("doc_src/gear_developers/*.md")
      ]
    ]
  end
end
