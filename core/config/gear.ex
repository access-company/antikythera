# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Config.Gear do
  alias Croma.Result, as: R
  alias Antikythera.{GearName, SecondsSinceEpoch, Domain, CowboyWildcardSubdomain}
  alias Antikythera.Crypto.Aes
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraCore.Ets.ConfigCache.Gear, as: GCache
  alias AntikytheraCore.Config.EncryptionKey
  alias AntikytheraCore.GearManager
  alias AntikytheraCore.GearLog.{Writer, Level}
  alias AntikytheraCore.Alert.Manager, as: CoreAlertManager
  alias AntikytheraCore.Alert.HandlerConfigsMap
  require AntikytheraCore.Logger, as: L

  defmodule CustomDomainList do
    use Croma.SubtypeOfList,
      elem_module: Croma.TypeGen.union([Domain, CowboyWildcardSubdomain]),
      max_length: 10
  end

  use Croma.Struct,
    recursive_new?: true,
    fields: [
      kv: Croma.Map,
      domains: CustomDomainList,
      log_level: Level,
      alerts: HandlerConfigsMap,
      # can be used to store instance-specific information
      # whose structure needs to be managed by administrative gears
      internal_kv: {Croma.Map, default: %{}}
    ]

  defun default() :: t do
    %__MODULE__{kv: %{}, domains: [], log_level: Level.default(), alerts: %{}}
  end

  defun read(gear_name :: v[GearName.t()]) :: t do
    case CorePath.gear_config_file_path(gear_name) |> File.read() do
      {:ok, encrypted} ->
        Aes.ctr128_decrypt(encrypted, EncryptionKey.get())
        |> R.bind(&decode/1)
        |> case do
          {:ok, conf} ->
            conf

          {:error, reason} ->
            msg = "failed to decode gear config JSON (#{gear_name}): #{inspect(reason)}"

            # TODO: this log should be removed after fixing error
            L.error(
              Enum.join(
                [
                  msg,
                  "Raw data: " <> inspect(encrypted, limit: :infinity),
                  "Decrypted data: " <>
                    inspect(Aes.ctr128_decrypt(encrypted, EncryptionKey.get()))
                ],
                "\n"
              )
            )

            raise msg
        end

      {:error, :enoent} ->
        default()
    end
  end

  defunp decode(b :: v[binary]) :: R.t(t) do
    Poison.decode(b) |> R.bind(&new/1)
  end

  defun write(gear_name :: v[GearName.t()], config :: v[t]) :: :ok do
    path = CorePath.gear_config_file_path(gear_name)
    content = Aes.ctr128_encrypt(Poison.encode!(config), EncryptionKey.get())
    File.write!(path, content, [:sync])
  end

  defunp gear_names_having_modified_config_files(last_checked_at :: v[SecondsSinceEpoch.t()]) :: [
           GearName.t()
         ] do
    CorePath.list_modified_files(CorePath.gear_config_dir(), last_checked_at)
    # generate atom from trusted data source
    |> Enum.map(fn path -> Path.basename(path) |> String.to_atom() end)
  end

  defun load_all(last_checked_at :: v[SecondsSinceEpoch.t()]) :: :ok do
    gear_names = gear_names_having_modified_config_files(last_checked_at)

    if !Enum.empty?(gear_names) do
      L.info("found change in gear config: #{inspect(gear_names)}")
    end

    gear_configs = Enum.map(gear_names, fn gear_name -> {gear_name, read(gear_name)} end)
    any_domains_changed? = apply_changes(gear_configs)

    if any_domains_changed? do
      AntikytheraCore.StartupManager.update_routing(GearManager.running_gear_names())
    end

    :ok
  end

  defunpt apply_changes(gear_configs :: Keyword.t(t)) :: boolean do
    Enum.map(gear_configs, fn {gear_name,
                               %__MODULE__{domains: domains, log_level: level, alerts: alerts} =
                                 conf} ->
      case GCache.read(gear_name) do
        nil ->
          GCache.write(gear_name, conf)
          if level != Level.default(), do: Writer.set_min_level(gear_name, level)
          CoreAlertManager.update_handler_installations(gear_name, alerts)
          !Enum.empty?(domains)

        %__MODULE__{domains: cached_domains, log_level: cached_log_level, alerts: cached_alerts} =
            cached ->
          if conf != cached, do: GCache.write(gear_name, conf)
          if level != cached_log_level, do: Writer.set_min_level(gear_name, level)

          if alerts != cached_alerts,
            do: CoreAlertManager.update_handler_installations(gear_name, alerts)

          domains != cached_domains
      end
    end)
    |> Enum.any?()
  end

  defun ensure_loaded(gear_name :: v[GearName.t()]) :: :ok do
    # Assuming that this function is called from `GearApplication.start/2`,
    # (unlike `apply_changes/1` above) it's not necessary to notify gear's Logger and cowboy router of this config,
    # as it will be done within `GearApplication.start/2`.
    GCache.write(gear_name, read(gear_name))
  end

  defun dump_all_from_env_to_file() :: :ok do
    System.get_env()
    |> Enum.filter(fn {k, _} -> String.ends_with?(k, "_CONFIG_JSON") end)
    |> Enum.each(fn {key, json} ->
      # Only in dev/test environment, no problem
      gear_name =
        String.replace_suffix(key, "_CONFIG_JSON", "") |> String.downcase() |> String.to_atom()

      config = %__MODULE__{default() | kv: Poison.decode!(json)}
      write(gear_name, config)
    end)
  end

  # To be used by administrative gears
  defun read_all() :: Keyword.t(t) do
    all_known_gears =
      Enum.uniq(gear_names_having_modified_config_files(0) ++ GearManager.running_gear_names())

    Enum.map(all_known_gears, fn gear_name -> {gear_name, read(gear_name)} end)
  end
end
