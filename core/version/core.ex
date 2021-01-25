# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version.Core do
  alias Antikythera.{Time, Env, VersionStr, ContextId}
  alias AntikytheraCore.{Version, GearManager, GearModule, GearLog}
  alias AntikytheraCore.Version.{Artifact, History}
  require AntikytheraCore.Logger, as: L

  defunp current_antikythera_instance_version!() :: VersionStr.t() do
    Version.current_version(Env.antikythera_instance_name()) ||
      raise "antikythera instance version is not found!"
  end

  defun upgrade_to_next_version() :: :ok do
    current_version = current_antikythera_instance_version!()

    case History.next_upgradable_version(Env.antikythera_instance_name(), current_version) do
      nil ->
        L.info("skip upgrade of antikythera instance: already the latest (#{current_version})")

      next_version ->
        upgrade(next_version)
    end
  end

  defunp upgrade(version :: v[VersionStr.t()]) :: :ok do
    L.info("start to upgrade core to #{version}")
    Artifact.copy_core_release_tgz(version)

    with {:ok, version_charlist} <-
           :release_handler.unpack_release('#{version}/#{Env.antikythera_instance_name()}'),
         {:ok, _, _} <- :release_handler.check_install_release(version_charlist, [:purge]),
         {:ok, _, _} <- :release_handler.install_release(version_charlist) do
      emit_success_message_to_all_log_files(version)
    else
      {:error, reason} -> L.error("failed to upgrade antikythera instance: #{inspect(reason)}")
    end
  end

  defunp emit_success_message_to_all_log_files(version :: v[VersionStr.t()]) :: :ok do
    message = "successfully upgraded core to #{version}"
    L.info(message)

    GearManager.running_gear_names()
    |> Enum.each(fn gear_name ->
      GearLog.Writer.info(
        GearModule.logger(gear_name),
        Time.now(),
        ContextId.system_context(),
        message
      )
    end)
  end
end
