# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Tmpdir do
  alias Antikythera.Context
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.TmpdirTracker

  @doc """
  Creates a temporary directory which can be used as a working space for the passed function `f`.

  This function is basically intended for async jobs which processes large amount of data.
  For example, an async job that accumulates data into files and upload them to somewhere
  can utilize this function to obtain a temporary working space.

  The temporary directory is created before `f` is invoked.
  When execution of `f` is finished (either successfully or by exception) the directory is automatically removed.
  The function returns the return value of `f`.

  Nested calls to this function is not allowed.
  Instead you can freely make subdirectories of the temporary directory.

  ## Example

      Antikythera.Tmpdir.make(context, fn tmpdir ->
        path = Path.join(tmpdir, "foo")
        File.open(path, [:write], fn file ->
          IO.write(file, "some data 1")
          IO.write(file, "some data 2")
        end)
        upload_to_object_storage_service("object_key", path)
      end)
  """
  defun make(context_or_epool_id :: v[EPoolId.t() | Context.t()], f :: (Path.t() -> a)) :: a
        when a: any do
    epool_id = extract_epool_id(context_or_epool_id)
    {:ok, tmpdir} = TmpdirTracker.request(epool_id)

    try do
      f.(tmpdir)
    after
      TmpdirTracker.finished()
    end
  end

  defp extract_epool_id(%Context{executor_pool_id: epool_id}), do: epool_id
  defp extract_epool_id(epool_id), do: epool_id
end
