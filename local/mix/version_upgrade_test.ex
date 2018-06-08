# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Mix.Tasks.AntikytheraLocal.VersionUpgradeTest do
  @shortdoc "Runs an antikythera release with testgear and check whether upgrades are successfully applied"

  use Mix.Task
  import ExUnit.Assertions
  alias Antikythera.Httpc
  alias AntikytheraLocal.{NodeName, RunningEnvironment}

  @instance_name Antikythera.Env.antikythera_instance_name()

  defp rpc(mod, fun, args) do
    :rpc.call(NodeName.get(), mod, fun, args)
  end

  def run([testgear_dir]) do
    {_, 0} = System.cmd("epmd", ["-daemon"]) # epmd must be up and running for distributed erlang
    {:ok, _} = Node.start(:"test_client_node@host.local")
    Node.set_cookie(:local)
    {:ok, _} = Application.ensure_all_started(:hackney) # to use Antikythera.Httpc
    Mix.Task.run("antikythera_local.start", [testgear_dir])
    :timer.sleep(5_000)

    instance_mixfile_path = Path.expand("mix.exs")
    testgear_mixfile_path = Path.join(testgear_dir, "mix.exs")
    instance_original_version = Mix.Project.config()[:version]
    {testgear_version_output, 0} = System.cmd("mix", ["antikythera.print_version"], [cd: testgear_dir])
    testgear_original_version = String.split(testgear_version_output, "\n", trim: true) |> List.last()

    try do
      [
        check_version:                                   [@instance_name, instance_original_version],
        check_version:                                   [:testgear, testgear_original_version],
        check_application_configs:                       [],
        check_healthcheck_and_gear_endpoints:            [],
        check_repository_is_clean:                       ["."],
        check_repository_is_clean:                       [testgear_dir],
        check_new_version_is_applied:                    [@instance_name, "9.0.0", instance_original_version, instance_mixfile_path],
        check_new_version_with_noupgrade_is_not_applied: [@instance_name, "9.0.1", instance_original_version, instance_mixfile_path],
        check_testgear_artifact_dirs:                    [["0.0.1"]],
        check_new_version_is_applied:                    [:testgear, "9.0.0", testgear_original_version, testgear_mixfile_path],
        check_testgear_artifact_dirs:                    [["0.0.1", "9.0.0"]],
        check_new_version_is_applied:                    [:testgear, "9.0.1", testgear_original_version, testgear_mixfile_path],
        check_testgear_artifact_dirs:                    [["9.0.0", "9.0.1"]], # 0.0.1 should be removed
        check_new_version_with_noupgrade_is_not_applied: [:testgear, "9.0.2", testgear_original_version, testgear_mixfile_path],
        check_testgear_artifact_dirs:                    [["9.0.0", "9.0.1"]],
      ] |> Enum.each(fn {fun_name, args} ->
        IO.puts("#{fun_name} #{inspect(args)} ...")
        apply(__MODULE__, fun_name, args)
        IO.puts("#{fun_name} #{inspect(args)} OK")
      end)
    after
      {_, 0} = System.cmd("git", ["checkout", "mix.exs"])
      {_, 0} = System.cmd("git", ["checkout", "mix.exs"], [cd: testgear_dir])
      Mix.Task.run("antikythera_local.stop")
    end
  end

  defp version(app_name) do
    case rpc(AntikytheraCore.Version, :current_version, [app_name]) do
      {:badrpc, reason} -> raise "Failed to communicate with the running node! reason: #{reason}"
      value             -> value
    end
  end

  def check_version(app_name, expected_version) do
    assert version(app_name) == expected_version
  end

  def check_application_configs() do
    conf = rpc(Application, :get_all_env, [:kernel])
    assert conf[:inet_dist_listen_min] == 6000
    assert conf[:inet_dist_listen_max] == 7999
  end

  def check_healthcheck_and_gear_endpoints() do
    assert Httpc.get!("http://testgear.localhost:8080/json").status == 200
    assert Httpc.get!("http://localhost:8080/healthcheck"  ).status == 200
  end

  def check_repository_is_clean(dir) do
    assert System.cmd("git", ["diff", "HEAD"], [cd: dir]) == {"", 0}
  end

  def check_new_version_is_applied(app_name, new_semver, original_version, mixfile_path) do
    current_version = version(app_name)
    override_version_in_mix_file(app_name, new_semver, mixfile_path)
    {_, 0} = run_mix_prepare(app_name, true, Path.dirname(mixfile_path))
    assert wait_until_version_changed(app_name, new_version(new_semver, original_version), current_version, 20) == :ok
  end

  def check_new_version_with_noupgrade_is_not_applied(app_name, new_semver, original_version, mixfile_path) do
    current_version = version(app_name)
    override_version_in_mix_file(app_name, new_semver, mixfile_path)
    {_, 0} = run_mix_prepare(app_name, false, Path.dirname(mixfile_path))
    assert wait_until_version_changed(app_name, new_version(new_semver, original_version), current_version, 10) == :new_version_not_applied
    assert version(app_name) == current_version
  end

  defp new_version(new_semver, original_version) do
    [_old_semver, rest] = String.split(original_version, "-")
    new_semver <> "-" <> rest
  end

  defunp override_version_in_mix_file(app_name :: g[atom], new_version :: g[String.t], mixfile_path :: Path.t) :: :ok do
    replacement = "\\1\"#{new_version}\"\\3"
    case app_name do
      @instance_name -> override_file(mixfile_path, ~R/(version\:[^\(]+\()([^\)]+)(\),\n)/   , replacement)
      :testgear      -> override_file(mixfile_path, ~R/(defp\sversion[^\:]+\:\s)([^\n]+)(\n)/, replacement)
    end
  end

  defunp override_file(file_path :: g[String.t], regex :: Regex.t, replacement :: g[String.t]) :: :ok do
    new_content = File.read!(file_path) |> String.replace(regex, replacement)
    File.write!(file_path, new_content)
  end

  defp run_mix_prepare(@instance_name, true , _repo_dir), do: System.cmd("mix", ["antikythera_local.prepare_core"                       ])
  defp run_mix_prepare(@instance_name, false, _repo_dir), do: System.cmd("mix", ["antikythera_local.prepare_core",           "noupgrade"])
  defp run_mix_prepare(:testgear     , true , repo_dir ), do: System.cmd("mix", ["antikythera_local.prepare_gear", repo_dir,            ])
  defp run_mix_prepare(:testgear     , false, repo_dir ), do: System.cmd("mix", ["antikythera_local.prepare_gear", repo_dir, "noupgrade"])

  defunp wait_until_version_changed(app_name :: g[atom], new_version :: g[String.t], old_version :: g[String.t], tries_remaining :: g[non_neg_integer]) :: :ok | :new_version_not_applied do
    case tries_remaining do
      0 -> :new_version_not_applied
      _ ->
        case version(app_name) do
          ^new_version -> :ok
          ^old_version ->
            :timer.sleep(1_000)
            wait_until_version_changed(app_name, new_version, old_version, tries_remaining - 1)
        end
    end
  end

  def check_testgear_artifact_dirs(expected_versions) do
    case list_artifact_versions() do
      ^expected_versions -> :ok
      _otherwise         ->
        :timer.sleep(2_000)
        assert list_artifact_versions() == expected_versions
    end
  end

  defp list_artifact_versions() do
    gears_dir = RunningEnvironment.unpacked_gears_dir()
    artifact_dirs = File.ls!(gears_dir) |> Enum.sort()
    Enum.map(artifact_dirs, fn "testgear-" <> v -> String.split(v, "-") |> hd() end) # extract `major.minor.patch` part
  end
end
