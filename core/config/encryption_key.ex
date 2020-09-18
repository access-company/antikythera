# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Config.EncryptionKey do
  @moduledoc """
  Utility functions to handle secret key which is used to encrypt/decrypt config files.
  """

  alias AntikytheraCore.Path, as: CorePath

  @type t :: binary
  @table_name AntikytheraCore.Ets.SystemCache.table_name()
  @ets_key :config_encryption_key

  defun init() :: :ok do
    key = File.read!(CorePath.config_encryption_key_path())
    :ets.insert(@table_name, {@ets_key, key})
    :ok
  end

  defun get() :: t do
    :ets.lookup_element(@table_name, @ets_key, 2)
  end
end
