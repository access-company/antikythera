# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.RunningEnvironment do
  alias Croma.Result, as: R
  alias Antikythera.{Env, GearNameStr, VersionStr, Httpc, EnumUtil}
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraLocal.{Cmd, StartScript}

  # Paths for test process that controls the ErlangVM that runs the release
  @release_output_dir "rel_local_erlang-#{System.otp_release()}"

  # Paths for the ErlangVM that runs the release
  current_os_pid = :os.getpid()
  @antikythera_root_dir          CorePath.antikythera_root_dir()          |> String.replace(~r|/tmp/#{current_os_pid}/|, "/tmp/local/")
  @compiled_gears_dir            CorePath.compiled_gears_dir()            |> String.replace(~r|/tmp/#{current_os_pid}/|, "/tmp/local/")
  @history_dir                   CorePath.history_dir()                   |> String.replace(~r|/tmp/#{current_os_pid}/|, "/tmp/local/")
  @system_info_access_token_path CorePath.system_info_access_token_path() |> String.replace(~r|/tmp/#{current_os_pid}/|, "/tmp/local/")
  @raft_fleet_dir                CorePath.raft_persistence_dir_parent()   |> String.replace(~r|/tmp/#{current_os_pid}/|, "/tmp/local/")
  @release_dir                   Path.join([@antikythera_root_dir, "..", "release_per_node"]) |> Path.expand()
  @unpacked_gears_dir            Path.join(@release_dir, "gears")

  def unpacked_gears_dir(), do: @unpacked_gears_dir

  @compile_environment_vars [{"ANTIKYTHERA_COMPILE_ENV", "local"}, {"MIX_ENV", "prod"}]

  defun setup(gear_repo_dirs :: [Path.t]) :: :ok do
    create_dir_same_as_node()
    build_core_and_unpack_at_release_dir()
    StartScript.run("start", @release_dir)
    wait_until_directories_are_created()
    Enum.each(gear_repo_dirs, fn gear_repo_dir ->
      {gear_name_str, version} = build_gear_and_move_to_artifact_dir(gear_repo_dir, false)
      :ok = add_version_to_history_file(gear_name_str, version, true)
    end)
    IO.puts("Successfully finished setting-up an OTP release for #{Env.antikythera_instance_name()}")
  end

  defp wait_until_directories_are_created(n \\ 10) do
    if n == 0 do
      raise "Directories under #{@antikythera_root_dir} haven't been created!"
    else
      :timer.sleep(500)
      if File.dir?(@history_dir) do
        :ok
      else
        wait_until_directories_are_created(n - 1)
      end
    end
  end

  defun teardown() :: :ok do
    StartScript.run("stop", @release_dir)
    # Kill epmd (running under `@release_dir`) as it prevents us from removing `tmp/` when using NFS
    _ = System.cmd("pkill", ["-f", "#{Env.antikythera_instance_name()}.*epmd"])
    clear_local_running_dir_and_release_products()
  end

  defun prepare_new_version_of_gear(gear_repo_dir :: Path.t, do_upgrade :: v[boolean]) :: String.t do
    {gear_name_str, new_version} = build_gear_and_move_to_artifact_dir(gear_repo_dir, true)
    :ok = add_version_to_history_file(gear_name_str, new_version, do_upgrade)
    new_version
  end

  defun prepare_new_version_of_core(do_upgrade :: v[boolean]) :: VersionStr.t do
    version = build_core()
    :ok = add_version_to_history_file("#{Env.antikythera_instance_name()}", version, do_upgrade)
    version
  end

  defun currently_running_os_process_ids() :: [String.t] do
    script_basename = "#{Env.antikythera_instance_name()}.sh"
    {pids, _} = System.cmd("pgrep", ["-f", script_basename])
    pids |> String.split("\n", trim: true)
  end

  defun wait_until_upgrade_applied(app_name :: v[atom], sha1 :: v[String.t]) :: :ok do
    wait_until_upgrade_applied_impl(Atom.to_string(app_name), sha1, 0)
  end
  defp wait_until_upgrade_applied_impl(app_name_str, sha1, count) do
    if count >= 20 do
      raise "Upgrade of #{app_name_str} to #{sha1} hasn't been applied!"
    else
      :timer.sleep(10_000)
      current_version = fetch_current_version(app_name_str)
      if R.ok?(current_version) and R.get!(current_version) |> String.ends_with?(sha1) do
        :ok
      else
        wait_until_upgrade_applied_impl(app_name_str, sha1, count + 1)
      end
    end
  end

  defp fetch_current_version(app_name_str) do
    url = "http://#{AntikytheraCore.Cmd.hostname()}:8080/versions"
    token = File.read!(@system_info_access_token_path)
    Httpc.get(url, %{"authorization" => token})
    |> R.map(fn %Httpc.Response{status: 200, body: body} -> extract_version_str(body, app_name_str) end)
  end

  defp extract_version_str(body, app_name_str) do
    String.split(body, "\n", trim: true)
    |> EnumUtil.find_value!(fn line ->
      case String.split(line) do
        [^app_name_str, v] -> v
        _                  -> nil
      end
    end)
  end

  defp create_dir_same_as_node() do
    File.rm_rf!(@release_dir)
    File.mkdir_p!(@unpacked_gears_dir)
  end

  defp clear_local_running_dir_and_release_products() do
    File.rm_rf!(@release_dir)
    File.rm_rf!(@raft_fleet_dir)
    File.rm_rf!(@release_output_dir)
    :ok
  end

  defunp build_gear_and_move_to_artifact_dir(gear_repo_dir :: Path.t, generate_appup? :: v[boolean]) :: {GearNameStr.t, VersionStr.t} do
    gear_name_str = Path.basename(gear_repo_dir)
    build_gear_dir = build_gear(gear_name_str, gear_repo_dir)
    version = AntikytheraCore.Version.read_from_app_file(build_gear_dir, gear_name_str)
    IO.puts("Successfully built #{gear_name_str} (#{version})")
    if generate_appup?, do: generate_appup(gear_name_str, gear_repo_dir)
    :ok = File.rename(build_gear_dir, Path.join(@compiled_gears_dir, "#{gear_name_str}-#{version}"))
    {_, 0} = System.cmd("tar", ["-czhf", "#{gear_name_str}-#{version}.tgz", "#{gear_name_str}-#{version}"], [cd: @compiled_gears_dir])
    {gear_name_str, version}
  end

  defunp build_gear(gear_name_str :: v[GearNameStr.t], gear_repo_dir :: Path.t) :: Path.t do
    Cmd.exec_and_output_log!("mix", ["deps.get"], cd: gear_repo_dir, env: @compile_environment_vars) # fetch antikythera instance
    Cmd.exec_and_output_log!("mix", ["deps.get"], cd: gear_repo_dir, env: @compile_environment_vars) # fetch antikythera (if changed)
    Cmd.exec_and_output_log!("mix", ["compile" ], cd: gear_repo_dir, env: @compile_environment_vars)
    Path.join([gear_repo_dir, "_build", "prod", "lib", gear_name_str])
  end

  defunp generate_appup(gear_name_str :: v[GearNameStr.t], gear_repo_dir :: Path.t) :: :ok do
    {last_line, 0} = System.cmd("tail", ["-1", Path.join(@history_dir, gear_name_str)])
    current_version = String.trim_trailing(last_line) |> String.split(" ") |> hd()
    current_dir = Path.join(@compiled_gears_dir, "#{gear_name_str}-#{current_version}")
    Cmd.exec_and_output_log!("mix", ["antikythera_core.generate_appup", current_dir], cd: gear_repo_dir, env: @compile_environment_vars)
  end

  defp build_core_and_unpack_at_release_dir() do
    instance_name = Env.antikythera_instance_name()
    version = build_core()
    dest = Path.join(@release_dir, "#{instance_name}.tar.gz")
    File.cp!(Path.join([@release_output_dir, "#{instance_name}", "releases", version, "#{instance_name}.tar.gz"]), dest)
    Cmd.exec_and_output_log!("tar", ["-xf", "#{instance_name}.tar.gz"], cd: @release_dir)
    File.rm!(dest)
  end

  defp build_core() do
    Cmd.exec_and_output_log!("mix", ["compile"], env: @compile_environment_vars)
    Cmd.exec_and_output_log!("mix", ["antikythera_core.generate_release"], env: @compile_environment_vars)
    version = get_core_version_from_release_file()
    IO.puts("Successfully built core (#{version})")
    version
  end

  defp get_core_version_from_release_file() do
    instance_name_charlist = Env.antikythera_instance_name() |> Atom.to_charlist()
    releases_file_path = Path.join([@release_output_dir, "#{instance_name_charlist}", "releases", "RELEASES"])
    {:ok, [term]} = :file.consult(String.to_charlist(releases_file_path))
    [{:release, ^instance_name_charlist, version, _, _, _}] = term
    List.to_string(version)
  end

  defunp add_version_to_history_file(app_name :: v[String.t], version :: v[VersionStr.t], do_upgrade :: v[boolean]) :: :ok do
    history_file_path = Path.join(@history_dir, app_name)
    line = if do_upgrade, do: version, else: "#{version} noupgrade"
    :ok = File.write(history_file_path, "#{line}\n", [:append])
  end
end
