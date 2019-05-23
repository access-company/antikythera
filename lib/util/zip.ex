# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Zip do
  alias Croma.Result, as: R
  alias Antikythera.Context
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.TmpdirTracker

  @typep opts :: {:encryption, boolean} | {:password, String.t}

  defun zip(
    context_or_epool_id :: v[EPoolId.t | Context.t],
    zip_path            :: v[String.t],
    src_path            :: v[String.t],
    opts                :: v[list(opts)] \\ []
  ) :: R.t(Path.t) do
    epool_id = extract_epool_id(context_or_epool_id)
    with(
      {:ok, tmpdir} <- TmpdirTracker.get(epool_id),
      :ok           <- validate_within_tmpdir(zip_path, tmpdir),
      :ok           <- validate_within_tmpdir(src_path, tmpdir),
      {:ok, args}   <- opts |> Map.new() |> extract_zip_args(),
      :ok           <- try_zip_cmd(args ++ [zip_path, src_path])
    ) do
      {:ok, zip_path}
    end
  end

  defp extract_epool_id(%Context{executor_pool_id: epool_id}), do: epool_id
  defp extract_epool_id(epool_id),                             do: epool_id

  defunp validate_within_tmpdir(path :: v[String.t], tmpdir :: v[String.t]) :: :ok | {:error, tuple} do
    if path |> Path.expand() |> String.starts_with?("#{tmpdir}/") do
      :ok
    else
      {:error, {:permission_denied, %{path: path, tmpdir: tmpdir}}}
    end
  end

  defunp extract_zip_args(map :: map) :: R.t(list(String.t)) do
    case map do
      %{encryption: true,  password: password} ->
        {:ok,    ["-P", password]}
      %{encryption: false, password: _}        ->
        {:error, {:argument_error, map}}
      _                                        ->
        {:ok,    []}
    end
  end

  defunp try_zip_cmd(args :: v[list(String.t)]) :: :ok | {:error, tuple} do
    case System.cmd("zip", args) do
      {_,   0}      ->
        :ok
      {msg, status} ->
        {:error, {:shell_runtime_error, %{msg: msg, status: status}}}
    end
  end
end