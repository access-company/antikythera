# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Zip do
  alias Croma.Result, as: R
  alias Antikythera.Context
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.TmpdirTracker

  defun zip(
    context_or_epool_id :: v[EPoolId.t | Context.t],
    zip_path            :: v[String.t],
    src_path            :: v[String.t]
  ) :: R.t(Path.t) do
    epool_id = extract_epool_id(context_or_epool_id)
    with(
      {:ok, tmpdir} <- TmpdirTracker.get(epool_id),
      {_,   0}      <- try_zip_cmd([zip_path, src_path])
    ) do
      {:ok, zip_path}
    end
  end

  defp extract_epool_id(%Context{executor_pool_id: epool_id}), do: epool_id
  defp extract_epool_id(epool_id),                             do: epool_id
end
