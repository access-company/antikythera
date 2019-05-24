# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Zip do
  @moduledoc """
  Wrapper module for `zip` command.

  For the consistency in working with antikythera and other gears, scope of this module is limited under a temporary directory reserved by `Antikythera.Tmpdir.make/2`.

  Functions only accept absolute paths for both source and resulting archive.
  """

  alias Croma.Result, as: R
  alias Antikythera.Context
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.TmpdirTracker

  @typep opts :: {:encryption, boolean} | {:password, String.t}

  defmodule FileName do
    use Croma.SubtypeOfString, pattern: ~r/[^\/]\z/
  end

  @doc """
  Creates a ZIP file.

  Encryption using a password is supported in which `encryption` option is set `true`.

  ## Example
    Tmpdir.make(context, fn tmpdir ->
      src_path = tmpdir <> "/src.txt"
      zip_path = tmpdir <> "/archive.zip"
      File.write!(src_path, "text")
      Antikythera.Zip.zip(context, zip_path, src_path, [encryption: true, password: "password"])
      |> case do
        {:ok, archive_path} ->
          ...
      end
      ...
    end)
  """
  defun zip(
    context_or_epool_id :: v[EPoolId.t | Context.t],
    zip_raw_path        :: v[FileName.t],
    src_raw_path        :: v[String.t],
    opts                :: v[list(opts)] \\ []
  ) :: R.t(Path.t) do
    epool_id = extract_epool_id(context_or_epool_id)
    with(
      {:ok, tmpdir} <- TmpdirTracker.get(epool_id),
      :ok           <- validate_path_type(src_raw_path),
      zip_path      <- Path.expand(zip_raw_path),
      src_path      <- Path.expand(src_raw_path),
      :ok           <- validate_within_tmpdir(zip_path, tmpdir),
      :ok           <- validate_within_tmpdir(src_path, tmpdir),
      :ok           <- validate_path_exists(src_path),
      :ok           <- ensure_dir_exists(zip_path, tmpdir),
      {:ok, args}   <- opts |> Map.new() |> extract_zip_args(),
      :ok           <- try_zip_cmd(args ++ [zip_path, src_path])
    ) do
      {:ok, zip_path}
    end
  end

  defp extract_epool_id(%Context{executor_pool_id: epool_id}), do: epool_id
  defp extract_epool_id(epool_id),                             do: epool_id

  defunp validate_path_type(path :: v[String.t]) :: :ok | {:error, tuple} do
    if String.ends_with?(path, "/") and !File.dir?(path) do
      {:error, {:not_dir, %{path: path}}}
    else
      :ok
    end
  end

  defunp validate_within_tmpdir(path :: v[String.t], tmpdir :: v[String.t]) :: :ok | {:error, tuple} do
    if String.starts_with?(path, "#{tmpdir}/") do
      :ok
    else
      {:error, {:permission_denied, %{path: path, tmpdir: tmpdir}}}
    end
  end

  defunp validate_path_exists(path :: v[String.t]) :: :ok | {:error, tuple} do
    if File.exists?(path) do
      :ok
    else
      {:error, {:not_found, %{path: path}}}
    end
  end

  defunp ensure_dir_exists(path :: v[String.t], tmpdir :: v[String.t]) :: :ok do
    dirname = Path.dirname(path)
    if dirname != tmpdir do
      dirname
      |> String.trim_leading(tmpdir <> "/")
      |> String.split("/")
      |> Enum.reduce(tmpdir, fn (x, acc) ->
        child = acc <> "/" <> x
        File.mkdir_p!(child)
        child
      end)
    end
    :ok
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
