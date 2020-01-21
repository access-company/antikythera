# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraLocal.UpgradeCompatibilityTest do
  @shortdoc "Runs tests to ensure that antikythera's upgrade doesn't break backward-compatibility"
  @moduledoc """
  #{@shortdoc}.

  It works in the following sequence:

  - Starts an antikythera instance of a version specified by a git ref, with gears in specified directories installed
  - (If [testgear] is used, establishes websocket connection to [testgear]. Periodically sends echo requests)
  - Upgrades the antikythera instance to new version specified by another git ref
  - Run blackbox tests defined in each gear, checking whether their external behaviors are kept intact
  - (Raises if the websocket connection established above was abnormally closed before here)

  [testgear]: https://github.com/access-company/testgear

  ## Usage

      $ mix antikythera_local.upgrade_compatibility_test <comma_separated_gear_directories> [git_ref_from[ git_ref_to]]

  - `comma_separated_gear_directories` can be absolute or relative paths to directories, such as `../testgear,/path/to/another_gear`.
      - It assumes basenames of paths exactly match gear_names, for [testgear] detection.
  - `git_ref_from` defaults to `HEAD^`. `git_ref_to` defaults to `HEAD`.
  """

  use Mix.Task
  alias AntikytheraLocal.RunningEnvironment

  @antikythera_instance_name Antikythera.Env.antikythera_instance_name()

  def run([comma_separated_gear_dirs | git_refs]) do
    {:ok, _} = Application.ensure_all_started(:hackney) # to fetch current versions via `Antikythera.Httpc`
    ensure_working_repository_clean()
    branch = current_branch()
    gears_map = gears_to_test(comma_separated_gear_dirs)
    has_testgear? = Map.has_key?(gears_map, "testgear")
    {hash_from, hash_to} = upgrade_from_and_to(git_refs)

    status = try do
      start_antikythera_local(gears_map, hash_from)
      prepare_and_run_blackbox_test(has_testgear?, gears_map, hash_to)
    after
      checkout_and_deps_get(branch)
      _ = run_mix_task(["antikythera_local.stop"])
    end
    exit({:shutdown, status})
  end

  defp gears_to_test(comma_separated_gear_dirs) do
    comma_separated_gear_dirs
    |> String.split(",", trim: true)
    |> Map.new(fn dir -> {Path.basename(dir), dir} end)
  end

  defp upgrade_from_and_to(git_refs) do
    case git_refs do
      []         -> {commit_hash("HEAD^"), commit_hash("HEAD")}
      [from]     -> {commit_hash(from   ), commit_hash("HEAD")}
      [from, to] -> {commit_hash(from   ), commit_hash(to    )}
    end
  end

  defp current_branch() do
    case System.cmd("git", ["symbolic-ref", "--quiet", "--short", "HEAD"]) do
      {branch, 0} -> String.trim_trailing(branch)
      {_, 1}      -> commit_hash("HEAD") # HEAD is not a symbolic ref
    end
  end

  defp commit_hash(ref) do
    {hash, 0} = System.cmd("git", ["rev-parse", ref])
    String.trim_trailing(hash)
  end

  defp start_antikythera_local(gears_map, hash_from) do
    gear_names = Enum.join(Map.keys(gears_map), ", ")
    IO.puts("Start #{@antikythera_instance_name} (#{hash_from}) with #{gear_names}")
    checkout_and_deps_get(hash_from)
    clean()
    gear_dirs = Map.values(gears_map)
    0 = run_mix_task(["antikythera_local.start" | gear_dirs])
  end

  defp prepare_and_run_blackbox_test(has_testgear?, gears_map, hash_to) do
    with_websocket_client_process(has_testgear?, fn ->
      IO.puts("Now upgrade #{@antikythera_instance_name} to #{hash_to}")
      checkout_and_deps_get(hash_to)
      clean()
      0 = run_mix_task(["antikythera_local.prepare_core"])
      RunningEnvironment.wait_until_upgrade_applied(@antikythera_instance_name, hash_to)

      run_blackbox_test(gears_map)
    end)
  end

  defp checkout_and_deps_get(ref) do
    # `mix.lock` file can have modifications if some package info (e.g. build tool) is missing in `hash_from` version.
    # We discard the diff (possibly a conflict) before `git checkout`.
    {output, 0} = System.cmd("git", ["diff", "--name-only", "HEAD"])
    case String.split(output, "\n", trim: true) do
      []           -> :ok
      ["mix.lock"] -> {_, 0} = System.cmd("git", ["checkout", "mix.lock"])
      # fail if other files have modifications
    end
    {_, 0} = System.cmd("git", ["checkout", ref], [stderr_to_stdout: true])
    0 = run_mix_task(["deps.get"])
  end

  defp ensure_working_repository_clean() do
    {"", 0} = System.cmd("git", ["diff", "HEAD"])
  end

  defp clean() do
    build_dir = Mix.Project.build_path() |> Path.dirname()
    File.rm_rf!(Path.join([build_dir, "prod", "lib", "antikythera"]))
    File.rm_rf!(Path.join([build_dir, "prod", "lib", "#{@antikythera_instance_name}"]))
  end

  defp run_mix_task(args) do
    run_mix_task(args, [], false)
  end
  defp run_mix_task(args, opts, always_output?) do
    {output, status} = System.cmd("mix", args, opts)
    cond do
      status != 0    -> IO.puts("running mix task #{inspect(args)} failed! output =\n#{output}")
      always_output? -> IO.puts(output)
      true           -> :ok
    end
    status
  end

  defp run_blackbox_test(gears_map) do
    Enum.each(gears_map, fn {gear_name, gear_dir} ->
      IO.puts("Test whether #{gear_name} is correctly functioning")
      env = %{"TEST_MODE" => "blackbox_local"}
      0 = run_mix_task(["test"], [env: env, cd: gear_dir], true)
    end)
  end

  defmodule WS do
    if Mix.env() == :test do
      use Antikythera.Test.WebsocketClient
      def base_url(), do: "ws://testgear.localhost:8080"

      def send_loop() do
        send_loop(__MODULE__.spawn_link("/ws?name=upgrade_test"))
      end
      defp send_loop(ws_client_pid) do
        :timer.sleep(500)
        send_json(ws_client_pid, %{"command" => "echo"})
        receive do
          {{:text, _json_string}, ^ws_client_pid} -> send_loop(ws_client_pid)
          :exit                                   -> :ok
        after
          1_000 -> raise "No reply from ws server!"
        end
      end
    else
      # Avoid using :websocket_client in case of non-test environment
      def send_loop(), do: :ok
    end
  end

  defp with_websocket_client_process(false, f) do
    f.()
  end
  defp with_websocket_client_process(true, f) do
    IO.puts("Start websocket connection to testgear")
    send_loop_closure = fn -> WS.send_loop() end # Load `WS` module before calling `f.()`
    :timer.sleep(5_000) # wait for initialization of the target web server
    {sender_pid, ref} = spawn_monitor(send_loop_closure)
    f.()
    send(sender_pid, :exit)
    receive do
      {:DOWN, ^ref, :process, ^sender_pid, reason} ->
        if reason != :normal do
          raise "Error in websocket client: #{inspect(reason)}"
        end
    end
  end
end
