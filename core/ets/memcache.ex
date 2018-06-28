# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Ets.Memcache do
  alias Croma.Result, as: R
  alias Antikythera.ExecutorPool.Id, as: EPoolId

  @table_name :antikythera_memcache
  defun table_name() :: atom, do: @table_name

  defun init() :: :ok do
    AntikytheraCore.Ets.create_read_optimized_table(@table_name)
  end

  defun read(key :: term, epool_id :: v[EPoolId.t]) :: R.t(term, :not_found) do
    case :ets.lookup(@table_name, {epool_id, key}) do
      []        -> {:error, :not_found}
      [element] -> {:ok   , element}
    end
  end

  defun write(key :: term, value :: term, expire_at :: integer, prob_expire_at :: integer, epool_id :: v[EPoolId.t]) :: :ok do
    :ets.insert(@table_name, {{epool_id, key}, expire_at, prob_expire_at, value})
    :ok
  end

  defun delete(key :: term, epool_id :: v[EPoolId.t]) :: :ok do
    :ets.delete(@table_name, {epool_id, key})
    :ok
  end
end
