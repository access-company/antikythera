# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Config.Core do
  alias Croma.Result, as: R
  alias Antikythera.SecondsSinceEpoch
  alias Antikythera.Crypto.Aes
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Config.EncryptionKey
  alias AntikytheraCore.Alert.Manager, as: CoreAlertManager
  require AntikytheraCore.Logger, as: L

  defunp read(last_changed_at :: v[SecondsSinceEpoch.t]) :: {map, SecondsSinceEpoch.t} | :not_modified do
    path = CorePath.core_config_file_path()
    case File.stat(path, [time: :posix]) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if mtime > last_changed_at do
          {:ok, value} = File.read!(path) |> decrypt_and_eval()
          {value, mtime}
        else
          :not_modified
        end
      {:error, :enoent} ->
        # config file does not exist (probably during bootstrapping of antikythera); create one with an empty map and retry
        write(%{})
        read(0)
    end
  end

  defunp decrypt_and_eval(encrypted :: v[binary]) :: R.t(map) do
    Aes.ctr128_decrypt(encrypted, EncryptionKey.get())
    |> R.bind(&eval/1)
  end

  defunp eval(b :: v[binary]) :: R.t(map) do
    R.try(fn ->
      {value, _bindings} = Code.eval_string(b)
      value
    end)
  end

  defun load(last_changed_at :: v[SecondsSinceEpoch.t] \\ 0) :: SecondsSinceEpoch.t do
    case read(last_changed_at) do
      :not_modified            -> last_changed_at
      {new_config, changed_at} ->
        L.info("found change in core config")
        ConfigCache.Core.write(new_config)
        alert_config = Map.get(new_config, :alerts, %{})
        CoreAlertManager.update_handler_installations(:antikythera, alert_config)
        changed_at
    end
  end

  @doc """
  Writes a map to antikythera's config file.

  Currently this function is intended to be used within remote_console.
  """
  defun write(config :: v[map]) :: :ok do
    path = CorePath.core_config_file_path()
    content = Aes.ctr128_encrypt(inspect(config), EncryptionKey.get())
    File.write!(path, content)
  end

  defun dump_from_env_to_file() :: :ok do
    env_var = System.get_env("ANTIKYTHERA_CONFIG") || ""
    {content, _bindings} = Code.eval_string(env_var)
    write(content || %{})
  end
end
