# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.TenantSetting do
  alias Croma.Result, as: R
  alias Antikythera.{GearName, TenantId, SecondsSinceEpoch}
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraCore.ExecutorPool.Setting, as: EPoolSetting
  alias AntikytheraCore.ExecutorPool.WsConnectionsCapping
  alias AntikytheraCore.TenantExecutorPoolsManager
  require AntikytheraCore.Logger, as: L

  setting_keys = EPoolSetting.default() |> Map.from_struct() |> Map.keys()
  fields = Enum.map(setting_keys, fn k -> {k, Croma.NonNegInteger} end) ++ [gears: Croma.TypeGen.list_of(GearName)]
  use Croma.Struct, recursive_new?: true, fields: fields

  @default EPoolSetting.default() |> Map.put(:__struct__, __MODULE__) |> Map.put(:gears, [])
  defun default() :: t, do: @default

  @typep fetch_result :: {:all | :partial, %{TenantId.t => t}}

  defun fetch_all_modified(since :: v[SecondsSinceEpoch.t]) :: fetch_result do
    if CorePath.changed?(CorePath.tenant_ids_file_path(), since) or CorePath.changed?(CorePath.tenant_setting_dir(), since) do
      all_tenants_with_default_settings =
        File.read!(CorePath.tenant_ids_file_path())
        |> :zlib.gunzip()
        |> String.split("\n", trim: true)
        |> Map.new(fn tenant_id -> {tenant_id, @default} end)
      {:all, Map.merge(all_tenants_with_default_settings, read_custom_tenant_settings(0))}
    else
      {:partial, read_custom_tenant_settings(since)}
    end
  end

  defunp read_custom_tenant_settings(since :: v[SecondsSinceEpoch.t]) :: %{TenantId.t => t} do
    CorePath.list_modified_files(CorePath.tenant_setting_dir(), since)
    |> Enum.map(&read_and_parse/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defunp read_and_parse(json_path :: Path.t) :: nil | {TenantId.t, t} do
    R.m do
      tenant_id  <- Path.basename(json_path) |> R.wrap_if_valid(TenantId) # skip files with unexpected name
      content    <- File.read(json_path)
      parsed     <- Poison.decode(content)
      gear_names =  Enum.map(parsed["gears"], &String.to_atom/1) # generate atom from trusted data source
      replaced1  =  Map.put(parsed, "gears", gear_names)
      replaced2  =  Map.put_new(replaced1, "ws_max_connections", 100) # fill the default value to migrate from JSON without "ws_max_connections" to JSON with the field
      tsetting   <- new(replaced2)
      capped     =  WsConnectionsCapping.cap_based_on_available_memory(tsetting)
      pure {tenant_id, capped}
    end
    |> case do
      {:ok, pair}       -> pair
      {:error, :enoent} -> nil # the file has been removed between `CorePath.list_modified_files/2` and `File.read/1`
      {:error, reason}  -> L.error("skipping invalid tenant setting JSON at '#{json_path}': #{inspect(reason)}"); nil
    end
  end

  defunpt fetch_or_default(tenant_id :: v[TenantId.t]) :: t do
    case read_and_parse(CorePath.tenant_setting_file_path(tenant_id)) do
      nil           -> @default
      {_, tsetting} -> tsetting
    end
  end

  defunpt put(tenant_id :: v[TenantId.t], setting :: v[t]) :: :ok do
    path = CorePath.tenant_setting_file_path(tenant_id)
    if Enum.empty?(setting.gears) do
      case File.rm(path) do
        :ok               -> :ok
        {:error, :enoent} -> :ok
      end
    else
      :ok = File.write(path, Poison.encode!(setting))
    end
  end

  # To be used by administrative gears
  defun associate_with_gear(gear_name :: v[GearName.t], tenant_id :: v[TenantId.t]) :: :ok do
    change_association(tenant_id, true, fn gear_names ->
      [gear_name | gear_names] |> Enum.uniq() |> Enum.sort()
    end)
  end

  defun disassociate_from_gear(gear_name :: v[GearName.t], tenant_id :: v[TenantId.t]) :: :ok do
    change_association(tenant_id, false, fn gear_names ->
      List.delete(gear_names, gear_name)
    end)
  end

  defunp change_association(tenant_id :: v[TenantId.t], broadcast? :: v[boolean], f :: ([GearName.t] -> [GearName.t])) :: :ok do
    tsetting     = fetch_or_default(tenant_id)
    new_gears    = f.(tsetting.gears)
    new_tsetting = %__MODULE__{tsetting | gears: new_gears}
    put(tenant_id, new_tsetting)
    if broadcast? do
      broadcast_new_tenant_setting(tenant_id, new_tsetting)
    end
    :ok
  end

  # To be used by sazabi
  defun persist_new_tenant_and_broadcast(tenant_id :: v[TenantId.t], gears :: [GearName.t]) :: :ok do
    tsetting = %__MODULE__{@default | gears: Enum.sort(gears)}
    put(tenant_id, tsetting)
    broadcast_new_tenant_setting(tenant_id, tsetting)
  end

  defunp broadcast_new_tenant_setting(tenant_id :: v[TenantId.t], tsetting :: v[t]) :: :ok do
    nodes   = [Node.self() | Node.list()]
    message = {:apply, tenant_id, tsetting}
    {_, bad_nodes} = GenServer.multi_call(nodes, TenantExecutorPoolsManager, message, 5_000)
    if !Enum.empty?(bad_nodes) do
      L.error("following nodes failed to load new tenant setting for #{tenant_id}: #{inspect(bad_nodes)}")
    end
    :ok
  end
end
