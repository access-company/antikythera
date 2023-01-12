# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version.Artifact do
  alias Antikythera.{Env, GearName, VersionStr}
  alias AntikytheraCore.Path, as: CorePath

  defun gears_dir() :: Path.t() do
    Path.join([Application.app_dir(:antikythera), "..", "..", "gears"]) |> Path.expand()
  end

  defunp gear_dir(gear_name :: v[GearName.t()], version :: v[VersionStr.t()]) :: Path.t() do
    Path.join([gears_dir(), "#{gear_name}-#{version}"])
  end

  defun copy_core_release_tgz(version :: v[VersionStr.t()]) :: non_neg_integer do
    dest_dir = core_releases_dir(version)
    File.mkdir_p!(dest_dir)

    File.copy!(
      core_release_tgz_path(version),
      Path.join(dest_dir, "#{Env.antikythera_instance_name()}.tar.gz")
    )
  end

  defunp core_release_tgz_path(version :: v[VersionStr.t()]) :: Path.t() do
    Path.join([CorePath.compiled_core_dir(), version, "#{Env.antikythera_instance_name()}.tar.gz"])
  end

  defunp core_releases_dir(version :: v[VersionStr.t()]) :: Path.t() do
    Path.join([Application.app_dir(:antikythera), "..", "..", "releases", version])
    |> Path.expand()
  end

  defun unpack_gear_tgz(gear_name :: v[GearName.t()], version :: v[VersionStr.t()]) :: Path.t() do
    tarball_path = Path.join(CorePath.compiled_gears_dir(), "#{gear_name}-#{version}.tgz")
    {_, 0} = System.cmd("tar", ["-xzf", tarball_path, "--directory", gears_dir()])
    gear_dir(gear_name, version)
  end
end
