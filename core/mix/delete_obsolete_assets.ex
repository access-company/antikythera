# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Mix.Tasks.AntikytheraCore.DeleteObsoleteAssets do
  @retention_days SolomonLib.Asset.retention_days()

  @shortdoc "Deletes obsolete asset files in asset storage"

  @moduledoc """
  #{@shortdoc}.

  To judge whether each asset file should be kept or deleted we use "asset list file"s.
  Each asset list file is created during deployment of a gear version (see `Mix.Tasks.AntikytheraCore.UploadNewAssetVersions`).

  Based on the asset retention policy described in the moduledoc of `SolomonLib.Asset`,
  it can be seen that, within all existing asset list files, only the following ones are relevant:

  1. asset list files created within the latest #{@retention_days} days
  2. the latest asset list file among ones created up to #{@retention_days} days before

  Assets included in any of the relevant asset list files should be kept.
  Assets not included in all of the relevant asset list files are "obsolete"; they should be deleted.
  """

  use Mix.Task
  alias SolomonLib.{GearName, Time}
  alias AntikytheraEal.AssetStorage
  alias AntikytheraCore.Version.History
  alias AntikytheraCore.Mix.AssetList

  def run(_) do
    deployable_gears = History.all_deployable_gear_names() |> MapSet.new()
    {gears_existing, gears_nonexisting} =
      AssetStorage.list_toplevel_prefixes()
      |> Enum.map(&String.to_atom/1) # it's OK to make dynamic atoms within mix task
      |> Enum.split_with(&(&1 in deployable_gears))
    handle_existing_gears(gears_existing)
    Enum.each(gears_nonexisting, &delete_all_assets_for_gear/1)
  end

  defunp handle_existing_gears(gear_names :: [GearName.t]) :: :ok do
    threshold_time = Time.now() |> Time.shift_days(-@retention_days)
    Enum.each(gear_names, fn gear_name ->
      delete_obsolete_assets_for_gear(gear_name, threshold_time)
    end)
  end

  defunp delete_obsolete_assets_for_gear(gear_name :: v[GearName.t], threshold_time :: v[Time.t]) :: :ok do
    keys_to_retain = AssetList.load_all(gear_name, threshold_time)
    AssetStorage.list(gear_name)
    |> Enum.reject(&(&1 in keys_to_retain))
    |> Enum.each(&delete/1)
  end

  defunp delete_all_assets_for_gear(gear_name :: v[GearName.t]) :: :ok do
    AssetStorage.list(gear_name)
    |> Enum.each(&delete/1)
  end

  defunp delete(key :: String.t) :: :ok do
    IO.puts("deleting an asset in cloud storage: #{key}")
    AssetStorage.delete(key)
  end
end
