# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.FileSetup do
  alias Antikythera.Env
  alias AntikytheraCore.{Ets, Config}
  alias AntikytheraCore.Path, as: CorePath

  defun setup_files_and_ets_tables() :: :ok do
    # When on cloud, directories should be made beforehand and should not be automatically created here, in order
    # (1) to appropriately set each dir's owner/permissions, and
    # (2) not to be confused by race conditions on NFS file operations.
    if non_cloud_and_using_tmp_dir?() do
      if File.dir?(CorePath.antikythera_root_dir()) do
        File.rm_rf!(CorePath.antikythera_root_dir())
      end
      ensure_dirs()

      # Note the timing of ETS table initialization:
      # - `Ets.init_all/0` requires `tmp/secret/config_encryption_key` file
      # - dumping core/gear configs to files requires that the encryption key be cached in ETS
      write_randomly_generated_secrets()
      Ets.init_all()
      Config.Core.dump_from_env_to_file()
      Config.Gear.dump_all_from_env_to_file()
      write_empty_tenant_ids()
    else
      Ets.init_all()
    end
  end

  defp non_cloud_and_using_tmp_dir?() do
    not Env.running_in_cloud?() and antikythera_root_dir_resides_in_tmp?()
  end

  defp antikythera_root_dir_resides_in_tmp?() do
    # for extra sanity check before touching `antikythera_root_dir`
    repo_tmp_dir = Path.join([__DIR__, "..", "..", "tmp"]) |> Path.expand()
    String.starts_with?(CorePath.antikythera_root_dir(), repo_tmp_dir)
  end

  defp write_randomly_generated_secrets() do
    config_enc_key_path = CorePath.config_encryption_key_path()
    File.mkdir_p!(Path.dirname(config_enc_key_path))
    File.write!(config_enc_key_path                     , :crypto.strong_rand_bytes(20) |> Base.encode64(padding: false))
    File.write!(CorePath.system_info_access_token_path(), :crypto.strong_rand_bytes(20) |> Base.encode64(padding: false))
  end

  defp ensure_dirs() do
    [
      CorePath.core_config_file_path() |> Path.dirname(),
      CorePath.gear_config_dir(),
      CorePath.history_dir(),
      CorePath.compiled_gears_dir(),
      CorePath.tenant_setting_dir(),
      CorePath.gear_tmp_dir(),
    ] |> Enum.each(&File.mkdir_p!/1)
  end

  defp write_empty_tenant_ids() do
    File.write!(CorePath.tenant_ids_file_path(), :zlib.gzip(""))
  end

  def write_initial_antikythera_instance_version_to_history_if_non_cloud(version) do
    if non_cloud_and_using_tmp_dir?() do
      path = Path.join(CorePath.history_dir(), "#{Env.antikythera_instance_name()}")
      File.write!(path, "#{version}\n", [:append])
    end
    :ok
  end
end
