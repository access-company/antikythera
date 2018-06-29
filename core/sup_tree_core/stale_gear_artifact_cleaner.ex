# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.StaleGearArtifactCleaner do
  @moduledoc """
  A `GenServer` which periodically removes already unused artifact files for running gears.

  "Artifact files" here means files created by unpacking OTP application tarballs of gears.
  Since gears as OTP applications are not included in OTP releases of antikythera instances,
  we can remove the artifact files directly; no coordination with `:release_handler` is required.

  Depends on `AntikytheraCore.GearManager`.
  """

  use GenServer
  alias Croma.Result, as: R
  alias Antikythera.{GearName, GearNameStr, VersionStr}
  alias AntikytheraCore.GearManager
  alias AntikytheraCore.Version.Artifact

  @interval (if Antikythera.Env.compile_env() == :local, do: 1_000, else: 24 * 60 * 60 * 1_000)

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}, @interval}
  end

  @impl true
  def handle_info(:timeout, state) do
    cleanup()
    {:noreply, state, @interval}
  end

  defp cleanup() do
    gears_dir           = Artifact.gears_dir()
    gear_names          = GearManager.running_gear_names()
    current_version_map = currently_running_gear_version_map(gear_names)
    artifacts_map       = scan_artifact_dirs(gears_dir)
    Enum.each(current_version_map, fn {gear_name, current_version} ->
      Map.get(artifacts_map, Atom.to_string(gear_name), [])
      |> select_removable_versions(current_version)
      |> Enum.each(fn version ->
        remove_stale_artifact_dir(gears_dir, gear_name, version)
      end)
    end)
  end

  defunp currently_running_gear_version_map(gear_names :: v[[GearName.t]]) :: %{GearName.t => VersionStr.t} do
    Application.started_applications()
    |> Map.new(fn {app, _, v} -> {app, List.to_string(v)} end)
    |> Map.take(gear_names)
  end

  defunp scan_artifact_dirs(gears_dir :: Path.t) :: %{GearNameStr.t => [VersionStr.t]} do
    File.ls(gears_dir)
    |> R.get([]) # `gears_dir` may not exist in development environment
    |> Enum.map(fn entry ->
      [gear_name_str, version] = String.split(entry, "-", parts: 2)
      {gear_name_str, version}
    end)
    |> Enum.group_by(fn {g, _} -> g end, fn {_, v} -> v end)
  end

  defunp select_removable_versions(vs :: v[[VersionStr.t]], current :: v[VersionStr.t]) :: [VersionStr.t] do
    vs
    |> Enum.sort()
    |> Enum.reverse() # descending order
    |> Enum.drop_while(&(&1 >= current))
    |> Enum.drop(1) # keep 1 old version just for safety
  end

  defunp remove_stale_artifact_dir(gears_dir :: Path.t, gear_name :: v[GearName.t], version :: v[VersionStr.t]) :: :ok do
    require AntikytheraCore.Logger, as: L
    path = Path.join(gears_dir, "#{gear_name}-#{version}")
    L.info("removing #{path}")
    File.rm_rf!(path)
    :ok
  end
end
