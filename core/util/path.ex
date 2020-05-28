# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Path do
  alias Antikythera.{Env, GearName, TenantId, SecondsSinceEpoch}

  #
  # paths under antikythera root directory
  #
  if Env.compiling_for_cloud?() do
    # Use compile-time application config
    @antikythera_root_dir Application.fetch_env!(:antikythera, :antikythera_root_dir)
    defun(antikythera_root_dir() :: Path.t(), do: @antikythera_root_dir)
    defun(compiled_core_dir() :: Path.t(), do: Path.join(antikythera_root_dir(), "releases"))
  else
    # Use runtime application config
    defun(antikythera_root_dir() :: Path.t(),
      do: Application.fetch_env!(:antikythera, :antikythera_root_dir)
    )

    defun compiled_core_dir() :: Path.t() do
      parent_dir = Path.join([__DIR__, "..", "..", ".."]) |> Path.expand()

      release_generating_project_dir =
        case Path.basename(parent_dir) do
          # from antikythera instance or gear projects
          "deps" -> Path.join([parent_dir, ".."])
          # as a standalone project
          _ -> Path.join([__DIR__, "..", ".."])
        end
        |> Path.expand()

      Path.join([
        release_generating_project_dir,
        "rel_local_erlang-#{System.otp_release()}",
        "#{Env.antikythera_instance_name()}",
        "releases"
      ])
    end
  end

  defun(core_config_file_path() :: Path.t(),
    do: Path.join([antikythera_root_dir(), "config", "antikythera"])
  )

  defun(gear_config_dir() :: Path.t(), do: Path.join(antikythera_root_dir(), "gear_config"))
  defun(history_dir() :: Path.t(), do: Path.join(antikythera_root_dir(), "history"))

  defun(compiled_gears_dir() :: Path.t(),
    do: Path.join(antikythera_root_dir(), "compiled_gears_erlang-#{System.otp_release()}")
  )

  defunp(tenant_dir() :: Path.t(), do: Path.join(antikythera_root_dir(), "tenant"))

  defun(tenant_ids_file_path() :: Path.t(), do: Path.join(tenant_dir(), "ids.gz"))
  defun(tenant_setting_dir() :: Path.t(), do: Path.join(tenant_dir(), "setting"))

  defun(tenant_setting_file_path(id :: v[TenantId.t()]) :: Path.t(),
    do: Path.join(tenant_setting_dir(), id)
  )

  defun gear_config_file_path(gear_name :: v[GearName.t()]) :: Path.t() do
    Path.join(gear_config_dir(), Atom.to_string(gear_name))
  end

  #
  # paths under unpacked release directory
  #
  defun gear_log_dir(gear_name :: v[GearName.t()]) :: Path.t() do
    Path.join([Application.app_dir(:antikythera), "..", "..", "log", Atom.to_string(gear_name)])
    |> Path.expand()
  end

  defun gear_log_file_path(gear_name :: v[GearName.t()]) :: Path.t() do
    Path.join(gear_log_dir(gear_name), "#{gear_name}.log.gz")
  end

  defun core_log_file_path(name :: v[String.t()]) :: Path.t() do
    Path.join(gear_log_dir(:antikythera), "#{name}.log.gz")
  end

  #
  # paths under "secret" directory in each node
  #
  defunp secret_dir() :: Path.t() do
    if Env.running_in_cloud?() do
      # At runtime `:code.root_dir/0` returns the unpacked "release" directory; "secret" is placed next to "release"
      Path.join([:code.root_dir(), "..", "secret"]) |> Path.expand()
    else
      case System.get_env("ANTIKYTHERA_SECRET_DIR") do
        nil -> Path.join([antikythera_root_dir(), "..", "secret"]) |> Path.expand()
        dir -> dir
      end
    end
  end

  defun config_encryption_key_path() :: Path.t() do
    Path.join(secret_dir(), "config_encryption_key")
  end

  defun system_info_access_token_path() :: Path.t() do
    Path.join(secret_dir(), "system_info_access_token")
  end

  #
  # path for Antikythera.Tmpdir
  #
  defun gear_tmp_dir() :: Path.t() do
    # This must be fetched at runtime at least in non-cloud environment in order to use
    # path with the current OS pid, not with the OS pid of `$ mix compile` command.
    Application.fetch_env!(:antikythera, :gear_tmp_dir)
  end

  #
  # path for RaftedValue & RaftFleet
  #
  defun raft_persistence_dir_parent() :: Path.t() do
    # This must be fetched at runtime at least in non-cloud environment in order to use
    # path with the current OS pid, not with the OS pid of `$ mix compile` command.
    Application.fetch_env!(:antikythera, :raft_persistence_dir_parent)
  end

  #
  # utilities
  #
  # In order not to miss file modifications due to NFS caching (if any) and/or clock skew,
  # we make margin by shifting `since` by a few seconds.
  # We don't care if the same modification is observed multiple times here.
  # The value comes from: default max lifetime of NFS client-side caches (60s) added by 2s to avoid issues due to clock skew.
  # (Should we make this a mix config item?)
  @file_modification_time_margin_in_seconds if Env.compiling_for_cloud?(), do: 62, else: 0

  defun changed?(path :: Path.t(), since :: v[SecondsSinceEpoch.t()]) :: boolean do
    since_with_margin = max(0, since - @file_modification_time_margin_in_seconds)
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    since_with_margin <= mtime
  end

  defun list_modified_files(dir :: Path.t(), since :: v[SecondsSinceEpoch.t()]) :: [String.t()] do
    since_with_margin = max(0, since - @file_modification_time_margin_in_seconds)

    Path.wildcard(Path.join(dir, "*"))
    |> Enum.filter(fn path -> modified_regular_file?(path, since_with_margin) end)
    |> Enum.sort()
  end

  defunp modified_regular_file?(path :: Path.t(), since :: v[SecondsSinceEpoch.t()]) :: boolean do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{type: :regular, mtime: t}} when t >= since -> true
      {:ok, _unchanged_or_not_regular} -> false
      # removed between `Path.wildcard/1` and `File.stat/2`
      {:error, :enoent} -> false
    end
  end
end
