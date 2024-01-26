# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version.Gear do
  alias Antikythera.{Time, GearName, VersionStr, ContextId}
  alias AntikytheraCore.{Version, GearManager, GearModule, StartupManager, GearLog}
  alias AntikytheraCore.Version.{Artifact, History}
  alias AntikytheraCore.Path, as: CorePath
  require AntikytheraCore.Logger, as: L

  @installed_gear_ratio_threshold 0.5
  @notify_threshold Application.compile_env!(
                      :antikythera,
                      :gear_install_notify_threshold_in_seconds
                    )

  defun install_or_upgrade_to_next_version(gear_name :: v[GearName.t()]) :: :ok do
    case Version.current_version(gear_name) do
      nil -> install_latest_gear(gear_name)
      current_version -> upgrade_to_next_version(gear_name, current_version)
    end
  end

  defunp install_latest_gear(gear_name :: v[GearName.t()]) :: :ok do
    latest_version = History.latest_installable_gear_version(gear_name)
    L.info("start to install '#{gear_name}' (#{latest_version})")
    gear_dir = Artifact.unpack_gear_tgz(gear_name, latest_version)

    add_code_path("#{gear_dir}/ebin", fn ->
      case Application.load(gear_name) do
        :ok -> :ok
        {:error, {:already_loaded, ^gear_name}} -> :ok
      end

      L.info("successfully loaded '#{gear_name}' (#{latest_version})")

      if :code.get_mode() != :interactive do
        # Load module manually
        Enum.each(Application.spec(gear_name, :modules), fn mod ->
          # Croma defines modules (e.g. `Elixir.Croma.TypeGen.Nilable.Antikythera.Email`) automatically in the gear.
          # As a result, some modules which have the same name are defined in two or more gears.
          # We should avoid loading these modules twice.
          if !auto_generated_module?(mod) do
            {:module, _} = :code.load_file(mod)
          else
            if !:erlang.module_loaded(mod) do
              case :code.load_file(mod) do
                {:module, _} -> :ok
                # When three or more same-name modules are loaded at the same time,
                # `:code.load_file(mod)` returns `:not_purged`. We can safely ignore the error in that case.
                {:error, :not_purged} -> :ok
                {:error, reason} -> raise "Failed to load '#{mod}': #{reason}"
              end
            end
          end
        end)

        L.info("successfully loaded all modules in '#{gear_name}'")
      end

      case Application.start(gear_name) do
        :ok ->
          L.info("successfully installed '#{gear_name}' (#{latest_version})")

        {:error, reason} ->
          :ok = Application.unload(gear_name)
          raise "Failed to install '#{gear_name}': #{inspect(reason)}"
      end
    end)
  end

  defunpt auto_generated_module?(mod :: atom) :: boolean do
    Atom.to_string(mod) |> String.starts_with?("Elixir.Croma.TypeGen.")
  end

  defunp add_code_path(ebin_dir :: Path.t(), f :: (() -> any)) :: any do
    dir = ebin_dir |> Path.expand() |> String.to_charlist()
    true = :code.add_pathz(dir)

    try do
      f.()
    rescue
      e ->
        original_stacktrace = __STACKTRACE__
        :code.del_path(dir)
        reraise(e, original_stacktrace)
    end
  end

  defunp upgrade_to_next_version(
           gear_name :: v[GearName.t()],
           current_version :: v[VersionStr.t()]
         ) :: :ok do
    case History.next_upgradable_version(gear_name, current_version) do
      nil -> L.info("skip upgrade of #{gear_name}: already the latest (#{current_version})")
      next_version -> upgrade(gear_name, next_version)
    end
  end

  defunp upgrade(gear_name :: v[GearName.t()], version :: v[VersionStr.t()]) :: :ok do
    L.info("start to upgrade '#{gear_name}' to #{version}")
    new_gear_dir = Artifact.unpack_gear_tgz(gear_name, version)
    {:ok, _} = :release_handler.upgrade_app(gear_name, String.to_charlist(new_gear_dir))
    message = "successfully upgraded '#{gear_name}' to #{version}"
    L.info(message)

    GearLog.Writer.info(
      GearModule.logger(gear_name),
      Time.now(),
      ContextId.system_context(),
      message
    )

    StartupManager.update_routing(GearManager.running_gear_names())
  end

  # MapSet.t(GearName.t)
  @typep gear_dependencies :: MapSet.t()
  @typep gear_and_deps_pair :: {GearName.t(), gear_dependencies}

  defun install_gears_at_startup(gear_names :: v[[GearName.t()]]) :: :ok | :error do
    if Antikythera.Env.running_with_release?() do
      do_install_gears_at_startup(gear_names)
    else
      :ok
    end
  end

  defunpt do_install_gears_at_startup(gear_names :: v[[GearName.t()]]) :: :ok | :error do
    # Tests need `__MODULE__.` to mock these functions.
    gear_and_deps_pairs =
      Enum.map(gear_names, fn g ->
        {g, __MODULE__.gear_dependencies_from_app_file(g, gear_names)}
      end)

    {microsec, {pairs_not_installed, num_failed_install}} =
      :timer.tc(__MODULE__, :install_gears_whose_deps_met, [
        gear_and_deps_pairs,
        MapSet.new(),
        0,
        fn gear_name ->
          try do
            install_or_upgrade_to_next_version(gear_name)
          rescue
            e ->
              L.error("Failed to install #{gear_name}: #{Exception.message(e)}")
              :error
          end
        end
      ])

    sec = div(microsec, 1_000_000)
    msg = "Finish gear installation. time: #{sec} seconds, num_of_gaers: #{length(gear_names)}"

    if is_number(@notify_threshold) and sec > @notify_threshold do
      L.error(msg)
    else
      L.info(msg)
    end

    Enum.each(pairs_not_installed, fn {gear_name, deps} ->
      L.error("#{gear_name} is not installed due to unmatched dependencies: #{inspect(deps)}")
    end)

    num_installable = length(gear_names)
    num_installed = num_installable - length(pairs_not_installed) - num_failed_install
    # version_upgrade_test starts Antikythera without gears.
    # Then, we can't check number of installed gears.
    needs_check = Antikythera.Env.runtime_env() != :local

    is_enough_gears_installed =
      num_installable != 0 and num_installed / num_installable > @installed_gear_ratio_threshold

    if !needs_check || is_enough_gears_installed do
      :ok
    else
      :error
    end
  end

  # public for mock
  defun install_gears_whose_deps_met(
          pairs :: v[[gear_and_deps_pair]],
          installed_gears_set :: MapSet.t(),
          num_failed_install :: v[non_neg_integer],
          f :: (GearName.t() -> :ok | :error)
        ) :: {[gear_and_deps_pair], non_neg_integer} do
    if Enum.empty?(pairs) do
      {[], num_failed_install}
    else
      {pairs_installable, pairs_not_installable} =
        Enum.split_with(pairs, fn {_, deps} -> MapSet.subset?(deps, installed_gears_set) end)

      if Enum.empty?(pairs_installable) do
        # we cannot make progress any more
        {pairs_not_installable, num_failed_install}
      else
        gears_installable = Keyword.keys(pairs_installable)
        gears_installed = Enum.filter(gears_installable, fn gear -> f.(gear) == :ok end)

        install_gears_whose_deps_met(
          pairs_not_installable,
          Enum.into(gears_installed, installed_gears_set),
          num_failed_install + length(gears_installable) - length(gears_installed),
          f
        )
      end
    end
  end

  # public for mock
  defun gear_dependencies_from_app_file(
          gear_name :: v[GearName.t()],
          known_gear_names :: v[[GearName.t()]]
        ) :: gear_dependencies do
    version = History.latest_installable_gear_version(gear_name)
    # gear's tarball is not yet unpacked; directly read .app file in `compiled_gears` directory
    app_file_path =
      Path.join([
        CorePath.compiled_gears_dir(),
        "#{gear_name}-#{version}",
        "ebin",
        "#{gear_name}.app"
      ])

    {:ok, [{:application, ^gear_name, kw}]} = :file.consult(app_file_path)

    Keyword.fetch!(kw, :applications)
    |> Enum.filter(&(&1 in known_gear_names))
    |> MapSet.new()
  end
end
