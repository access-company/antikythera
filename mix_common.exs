# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

#
# Modules defined in this file provides common project settings
# for antikythera itself, antikythera instances and also gears.
# These modules must be loadable independently of `Antikythera.Mixfile`, i.e.,
# they must be defined in a file separate from `mix.exs`
# (if we put these modules in `mix.exs`, mix complains about redefinition of the same mix project).
#

defmodule Antikythera.MixCommon do
  def common_project_settings() do
    [
      elixir:            "~> 1.6",
      elixirc_options:   [warnings_as_errors: true],
      build_embedded:    Mix.env() == :prod,
      test_coverage:     [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.html": :test, "antikythera_local.upgrade_compatibility_test": :test],
    ]
  end

  #
  # deps
  #
  def filter_tool_deps(deps) do
    Enum.reject(deps, &dep_available_in_env?(&1, :prod))
  end

  defp dep_available_in_env?(dep, env) do
    extract_dep_options(dep) |> Keyword.get(:only, [:dev, :test, :prod]) |> List.wrap() |> Enum.member?(env)
  end

  defp dep_used_at_runtime?(dep) do
    extract_dep_options(dep) |> Keyword.get(:runtime, true)
  end

  defp dep_indirect?(dep) do
    extract_dep_options(dep) |> Keyword.get(:indirect, false)
  end

  defp dep_antikythera_internal?(dep) do
    extract_dep_options(dep) |> Keyword.get(:antikythera_internal, false)
  end

  defp extract_dep_options({_name, _ver, opts})             , do: opts
  defp extract_dep_options({_name, opts}) when is_list(opts), do: opts
  defp extract_dep_options(_)                               , do: []

  #
  # runtime dependencies (`applications` field in .app file)
  #
  def antikythera_runtime_dependency_applications(deps) do
    runtime_applications_from_deps =
      deps
      |> Enum.filter(&dep_available_in_env?(&1, Mix.env()))
      |> Enum.filter(&dep_used_at_runtime?/1)
      |> Enum.reject(&dep_indirect?/1)
      |> Enum.map(&elem(&1, 0))
    runtime_applications_from_deps ++ special_antikythera_internal_applications() ++ applications_required_in_dev_for_dialyzer()
  end

  def gear_runtime_dependency_applications(deps) do
    runtime_applications_from_deps =
      deps
      |> Enum.filter(&dep_available_in_env?(&1, Mix.env()))
      |> Enum.filter(&dep_used_at_runtime?/1)
      |> Enum.reject(&dep_indirect?/1)
      |> Enum.reject(&dep_antikythera_internal?/1)
      |> Enum.map(&elem(&1, 0))
    runtime_applications_from_deps ++ applications_required_in_dev_for_dialyzer()
  end

  defp special_antikythera_internal_applications() do
    [
      :sasl,     # To use :release_handler
      :inets,    # To use :httpd_util
      :crypto,
      :mnesia,
      :logger,
      :p1_utils, # :iconv does not declare this as a runtime dependency; we have to explicitly add this
    ]
  end

  defp applications_required_in_dev_for_dialyzer() do
    case Mix.env() do
      :dev -> [
        :mix,     # Suppress warning about Mix.Task behaviour
        :eex,     # Only used during compilation, suppress warning about EEx.Engine behaviour
        :ex_unit, # Suppress warnings about calling ExUnit functions in Antikythera.Test.*
      ]
      _ -> []
    end
  end

  #
  # util
  #
  def version_with_last_commit_info(major_minor_patch) do
    {git_log_output, 0}      = System.cmd("git", ["log", "-1", "--format=%cd", "--date=raw"])
    [seconds_str, _timezone] = String.split(git_log_output)
    seconds_since_epoch      = String.to_integer(seconds_str)
    time_as_tuple            = {div(seconds_since_epoch, 1_000_000), rem(seconds_since_epoch, 1_000_000), 0}
    {{y, mo, d}, {h, mi, s}} = :calendar.now_to_universal_time(time_as_tuple)
    last_commit_time         = :io_lib.format('~4..0w~2..0w~2..0w~2..0w~2..0w~2..0w', [y, mo, d, h, mi, s]) |> List.to_string()
    {last_commit_sha1, 0}    = System.cmd("git", ["rev-parse", "HEAD"])
    major_minor_patch <> "-" <> last_commit_time <> "+" <> String.trim(last_commit_sha1)
  end
end

defmodule Antikythera.MixConfig do
  @moduledoc """
  Helper module to simplify `config.exs` files in antikythera instance projects.

  Antikythera uses a number of mix configurations of many OTP applications for various purposes;
  setting the same set of mix configurations in `config.exs` files of all antikythera instance projects
  introduces too much boilerplate.
  To avoid the boilerplate, you can call `Antikythera.MixConfig.all/0` to obtain the default values
  and then set the values by `Mix.Config.config/2` macro in your `config.exs` file.
  The default values returned by `Antikythera.MixConfig.all/0` should suffice for most cases.

  None of the mix configurations of `:antikythera` application are included in the return value
  (as there's no appropriate defaults for them); you must properly set them yourself.
  For explanations of the configuration items of `:antikythera`, see antikythera's `config.exs` file.
  As a result, your `config.exs` file should look like the following:

      use Mix.Config

      try do
        for {app, kw} <- Antikythera.MixConfig.all() do
          config(app, kw)
        end
      rescue
        UndefinedFunctionError -> :ok
      end

      config :antikythera, [
        <key1>: <value1>,
        ...
      ]

  Note that the `try`-`rescue` is needed to correctly bootstrap your project
  from the situation where `:antikythera` as a dependency is not yet fetched.
  """

  @spec all() :: Keyword.t(Keyword.t(any))
  def all() do
    default_configs() ++ croma_configs() ++ exsync_configs()
  end

  defp default_configs() do
    [
      # Limit port range to be used for ErlangVM-to-ErlangVM communications.
      kernel: [
        inet_dist_listen_min: 6000,
        inet_dist_listen_max: 7999,
      ],

      # Logger configurations.
      sasl: [
        sasl_error_logger: false, # SASL logs are handled by :logger
      ],

      logger: [
        level:               :info,
        utc_log:             true,
        handle_sasl_reports: true,
        translators:         [{AntikytheraCore.ErlangLogTranslator, :translate}],
        backends:            [:console, AntikytheraCore.Alert.LoggerBackend],
        console: [
          format:   "$dateT$time+00:00 [$level$levelpad] $metadata$message\n",
          metadata: [:module],
        ],
      ],

      # Persist Raft logs & snapshots for async job queues.
      raft_fleet: [
        rafted_value_config_maker: AntikytheraCore.AsyncJob.RaftedValueConfigMaker,
        per_member_options_maker:  AntikytheraCore.AsyncJob.RaftPerMemberOptionsMaker,
      ],
    ]
  end

  defp croma_configs() do
    # (compile-time configuration) Disable croma's runtime validations
    # when running as a "deployment" (see also `:deployments` in `config.exs` file).
    local? = System.get_env("ANTIKYTHERA_COMPILE_ENV") in [nil, "local"]
    [
      croma: [
        defun_generate_validation: local?,
        debug_assert:              local?,
      ],
    ]
  end

  defp exsync_configs() do
    # During gear development, recompile and reload on modifications of HAML files.
    if Mix.env() == :dev do
      [
        exsync: [
          extra_extensions: [".haml"],
        ],
      ]
    else
      []
    end
  end
end

defmodule Antikythera.GearProject do
  @moduledoc """
  Module to be `use`d by `Mixfile` module in each gear project.

  `__using__/1` of this module receives the following key in its argument.

  - (required) `:antikythera_instance_dep` : Dependency on the antikythera instance which this gear belongs to.
  - (optional) `:source_url`               : If given it's used as both `source_url` (and also `homepage_url`).

  The following private functions are used by this module and thus mandatory.

  - `gear_name/0` : Name of the gear as an atom.
  - `version/0    : Current version of the gear.
  - `gear_deps/0  : Dependencies on other gears.
  """

  def load_antikythera_instance_mix_config_file!(instance_name) do
    # Load mix config to import compile-time configurations;
    # if antikythera instance is not yet available, raise `Mix.Config.LoadError` and fallback to `AntikytheraGearInitialSetup`.
    config_path = Path.join([antikythera_instance_dir(instance_name), "config", "config.exs"])
    Mix.Config.persist(Mix.Config.read!(config_path))
    # Since 1.7.x `Mix.Config.read!/1` is deprecated. This line should be changed as follows:
    # {configs, _} = Mix.Config.eval!(config_path)
    # Mix.Config.persist(configs)
  end

  def get_antikythera_instance_project_settings!(instance_name) do
    Mix.Project.in_project(instance_name, antikythera_instance_dir(instance_name), fn mod ->
      mod.project()
    end)
  end

  defp antikythera_instance_dir(instance_name) do
    # When `use`d by a gear, this file resides in "deps/antikythera/"; antikythera instance is located at the sibling dir.
    Path.join([__DIR__, "..", "#{instance_name}"]) |> Path.expand()
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @antikythera_instance_dep     Keyword.fetch!(opts, :antikythera_instance_dep)
      @antikythera_instance_name    elem(@antikythera_instance_dep, 0)
      @antikythera_instance_project Antikythera.GearProject.get_antikythera_instance_project_settings!(@antikythera_instance_name)
      @antikythera_instance_deps    @antikythera_instance_project[:deps]
      @source_url                   Keyword.get(opts, :source_url)
      Antikythera.GearProject.load_antikythera_instance_mix_config_file!(@antikythera_instance_name)

      # Deliberately undocumented option; only used by special gears (mostly for testing or administrative purposes)
      @use_antikythera_internal_modules? Keyword.get(opts, :use_antikythera_internal_modules?, false)

      use Mix.Project

      def project() do
        [
          app:              gear_name(),
          version:          Antikythera.MixCommon.version_with_last_commit_info(version()),
          elixirc_paths:    ["lib", "web"],
          compilers:        [:ensure_gear_dependencies, :gettext, :propagate_file_modifications] ++ Mix.compilers() ++ [:gear_static_analysis],
          start_permanent:  false,
          deps:             deps(),
          docs:             [output: "exdoc"],
          antikythera_gear: [
            instance_dep:                      @antikythera_instance_dep,
            gear_deps:                         gear_deps(),
            use_antikythera_internal_modules?: @use_antikythera_internal_modules?,
          ],
        ] ++ urls() ++ Antikythera.MixCommon.common_project_settings()
      end

      defp urls() do
        case @source_url do
          nil -> []
          url -> [source_url: url, homepage_url: url]
        end
      end

      def application() do
        gear_application_module_name    = gear_name() |> Atom.to_string() |> Macro.camelize()
        gear_application_module         = Module.concat([gear_application_module_name])
        runtime_dependency_applications = Antikythera.MixCommon.gear_runtime_dependency_applications(@antikythera_instance_deps)
        gear_dependency_names           = Enum.map(gear_deps(), &elem(&1, 0))
        [
          mod:          {gear_application_module, []},
          applications: [@antikythera_instance_name] ++ runtime_dependency_applications ++ gear_dependency_names,
        ]
      end

      defp deps() do
        # :dev/:test-only deps of antikythera instance are not automatically added to gear projects.
        # We must declare the same set of tool deps in gear projects in order
        # not only to make tool deps available but also to use the exact version specified by the antikythera instance.
        tool_deps = Antikythera.MixCommon.filter_tool_deps(@antikythera_instance_deps)
        [@antikythera_instance_dep] ++ tool_deps ++ gear_deps()
      end
    end
  end
end
