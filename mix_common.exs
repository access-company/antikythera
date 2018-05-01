# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

#
# `Antikythera.MixCommon` and `Antikythera.GearProject` provides common project configurations for both antikythera and gears.
# These 2 modules must be loadable independently of `Antikythera.Mixfile`, i.e.,
# these modules must be defined in a file separate from `mix.exs`
# (if we put these modules in `mix.exs`, mix complains about redefinition of the same mix project).
#

defmodule Antikythera.MixCommon do
  versions =
    File.read!(Path.join(__DIR__, ".tool-versions"))
    |> String.split("\n", trim: true)
    |> Map.new(fn line -> [n, v] = String.split(line, " ", trim: true); {n, v} end)
  @otp_version    Map.fetch!(versions, "erlang")
  @elixir_version Map.fetch!(versions, "elixir")

  # Strictly enforce Erlang/OTP version
  otp_version_path    = Path.join([:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"])
  current_otp_version = File.read!(otp_version_path) |> String.trim_trailing()
  if current_otp_version != @otp_version do
    Mix.raise("Incorrect Erlang/OTP version! required: '#{@otp_version}', used: '#{current_otp_version}'")
  end

  @on_cloud? System.get_env("ANTIKYTHERA_COMPILE_ENV") in ["dev", "prod"]
  def on_cloud?(), do: @on_cloud?

  # Argument validation in `Croma.Defun.defun` is enabled only in dev/test; disabled in the cloud environments
  if @on_cloud? do
    Application.put_env(:croma, :defun_generate_validation, false)
    Application.put_env(:croma, :debug_assert, false)
  end

  # Set application config for exsync
  if Mix.env() == :dev do
    Application.put_env(:exsync, :extra_extensions, [".haml"])
  end

  def common_project_settings() do
    [
      elixir:            @elixir_version,
      elixirc_options:   [warnings_as_errors: true],
      build_embedded:    Mix.env() == :prod,
      docs:              [output: "exdoc"],
      test_coverage:     [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.html": :test, "antikythera_local.upgrade_compatibility_test": :test],
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

defmodule Antikythera.GearProject do
  @moduledoc """
  Module to be `use`d by `Mixfile` module in each gear project.

  `__using__/1` of this module receives the following key in its argument.

  - (required) `:antikythera_instance_dep` : Dependency on the antikythera instance which this gear belongs to.
  - (optional) `:source_url`           : If given it's used as both `source_url` (and also `homepage_url`).

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
