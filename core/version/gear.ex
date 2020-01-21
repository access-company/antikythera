# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version.Gear do
  alias Antikythera.{Time, GearName, VersionStr, ContextId}
  alias AntikytheraCore.{Version, GearManager, GearModule, StartupManager, GearLog}
  alias AntikytheraCore.Version.{Artifact, History}
  alias AntikytheraCore.Path, as: CorePath
  require AntikytheraCore.Logger, as: L

  defun install_or_upgrade_to_next_version(gear_name :: v[GearName.t]) :: :ok do
    case Version.current_version(gear_name) do
      nil             -> install_latest_gear(gear_name)
      current_version -> upgrade_to_next_version(gear_name, current_version)
    end
  end

  defunp install_latest_gear(gear_name :: v[GearName.t]) :: :ok do
    latest_version = History.latest_installable_gear_version(gear_name)
    L.info("start to install '#{gear_name}' (#{latest_version})")
    gear_dir = Artifact.unpack_gear_tgz(gear_name, latest_version)
    add_code_path("#{gear_dir}/ebin", fn ->
      case Application.load(gear_name) do
        :ok                                     -> :ok
        {:error, {:already_loaded, ^gear_name}} -> :ok
      end
      L.info("successfully loaded '#{gear_name}' (#{latest_version})")
      if :code.get_mode() != :interactive do
        # Load module manually
        Enum.each(Application.spec(gear_name, :modules), fn(mod) ->
          # Croma defines modules (e.g. `Elixir.Croma.TypeGen.Nilable.Antikythera.Email`) automatically in the gear.
          # As a result, some modules which have the same name are defined in two or more gears.
          # We should avoid loading these modules twice.
          if !auto_generated_module?(mod) do
            {:module, _} = :code.load_file(mod)
          else
            if !:erlang.module_loaded(mod) do
              case :code.load_file(mod) do
                {:module, _}           -> :ok
                # When three or more same-name modules are loaded at the same time,
                # `:code.load_file(mod)` returns `:not_purged`. We can safely ignore the error in that case.
                {:error , :not_purged} -> :ok
                {:error , reason}      -> raise "Failed to load '#{mod}': #{reason}"
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

  defunp add_code_path(ebin_dir :: Path.t, f :: (() -> any)) :: any do
    dir = ebin_dir |> Path.expand() |> String.to_charlist()
    true = :code.add_pathz(dir)
    try do
      f.()
    rescue
      e ->
        original_stacktrace = System.stacktrace()
        :code.del_path(dir)
        reraise(e, original_stacktrace)
    end
  end

  defunp upgrade_to_next_version(gear_name :: v[GearName.t], current_version :: v[VersionStr.t]) :: :ok do
    case History.next_upgradable_version(gear_name, current_version) do
      nil          -> L.info("skip upgrade of #{gear_name}: already the latest (#{current_version})")
      next_version -> upgrade(gear_name, next_version)
    end
  end

  defunp upgrade(gear_name :: v[GearName.t], version :: v[VersionStr.t]) :: :ok do
    L.info("start to upgrade '#{gear_name}' to #{version}")
    new_gear_dir = Artifact.unpack_gear_tgz(gear_name, version)
    {:ok, _} = :release_handler.upgrade_app(gear_name, String.to_charlist(new_gear_dir))
    message = "successfully upgraded '#{gear_name}' to #{version}"
    L.info(message)
    GearLog.Writer.info(GearModule.logger(gear_name), Time.now(), ContextId.system_context(), message)
    StartupManager.update_routing(GearManager.running_gear_names())
  end

  @typep gear_dependencies  :: MapSet.t # MapSet.t(GearName.t)
  @typep gear_and_deps_pair :: {GearName.t, gear_dependencies}

  defun install_gears_at_startup(gear_names :: v[[GearName.t]]) :: :ok do
    if Antikythera.Env.running_with_release?() do
      do_install_gears_at_startup(gear_names)
    else
      :ok
    end
  end

  defunp do_install_gears_at_startup(gear_names :: v[[GearName.t]]) :: :ok do
    gear_and_deps_pairs = Enum.map(gear_names, fn g -> {g, gear_dependencies_from_app_file(g, gear_names)} end)
    pairs_not_installed =
      install_gears_whose_deps_met(gear_and_deps_pairs, MapSet.new(), fn gear_name ->
        try do
          install_or_upgrade_to_next_version(gear_name)
        rescue
          e -> L.error("Failed to install #{gear_name}: #{Exception.message(e)}")
        end
      end)
    Enum.each(pairs_not_installed, fn {gear_name, deps} ->
      L.error("#{gear_name} is not installed due to unmatched dependencies: #{inspect(deps)}")
    end)
  end

  defunpt install_gears_whose_deps_met(pairs :: v[[gear_and_deps_pair]], installed_gears_set :: MapSet.t, f :: (GearName.t -> :ok)) :: [gear_and_deps_pair] do
    if Enum.empty?(pairs) do
      []
    else
      {pairs_installable, pairs_not_installable} = Enum.split_with(pairs, fn {_, deps} -> MapSet.subset?(deps, installed_gears_set) end)
      if Enum.empty?(pairs_installable) do
        pairs_not_installable # we cannot make progress any more
      else
        gears_installable = Keyword.keys(pairs_installable)
        Enum.each(gears_installable, f)
        install_gears_whose_deps_met(pairs_not_installable, Enum.into(gears_installable, installed_gears_set), f)
      end
    end
  end

  defunp gear_dependencies_from_app_file(gear_name :: v[GearName.t], known_gear_names :: v[[GearName.t]]) :: gear_dependencies do
    version = History.latest_installable_gear_version(gear_name)
    # gear's tarball is not yet unpacked; directly read .app file in `compiled_gears` directory
    app_file_path = Path.join([CorePath.compiled_gears_dir(), "#{gear_name}-#{version}", "ebin", "#{gear_name}.app"])
    {:ok, [{:application, ^gear_name, kw}]} = :file.consult(app_file_path)
    Keyword.fetch!(kw, :applications)
    |> Enum.filter(&(&1 in known_gear_names))
    |> MapSet.new()
  end
end
