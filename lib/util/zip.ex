# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Zip do
  @moduledoc """
  Wrapper module for `zip` command.

  For the security and consistency in working with antikythera and other gears, scopes of

  - working directory
  - input file
  - output file

  are limited under a temporary directory reserved by `Antikythera.Tmpdir.make/2`.

  Functions only accept absolute paths for both source and resulting archive.
  """

  alias Croma.Result, as: R
  alias Antikythera.Context
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.TmpdirTracker

  @typep opts :: {:encryption, boolean} | {:password, String.t}

  defmodule FileName do
    use Croma.SubtypeOfString, pattern: ~R/\A(?!.*\/\.{0,2}\z).*\z/
  end

  defmodule NonTraversalPath do
    use Croma.SubtypeOfString, pattern: ~R/\A([^.\/]|((?<!\.)\.)|((?<!\A)\/))+\z/
  end

  @doc """
  Creates a ZIP file.

  Encryption using a password is supported in which `encryption` option is set `true`.

  ## Example
    Tmpdir.make(context, fn tmpdir ->
      src_path = "src.txt"
      zip_path = "archive.zip"
      File.write!(tmpdir <> "/" <> src_path, "text")
      Antikythera.Zip.zip(context, tmpdir, zip_path, src_path, [encryption: true, password: "password"])
      |> case do
        {:ok, archive_path} ->
          ...
      end
      ...
    end)
  """
  defun zip(context_or_epool_id :: v[EPoolId.t | Context.t],
            cwd_path            :: v[String.t],
            zip_path            :: v[FileName.t],
            src_path            :: v[NonTraversalPath.t],
            opts                :: v[list(opts)] \\ []) :: R.t(Path.t) do
    epool_id = extract_epool_id(context_or_epool_id)
    with {:ok, tmpdir} <- TmpdirTracker.get(epool_id),
         cwd_full_path <- Path.expand(cwd_path),
         zip_full_path <- Path.expand(zip_path, cwd_full_path),
         src_full_path <- Path.expand(src_path, cwd_full_path),
         :ok           <- validate_within_tmpdir(cwd_full_path, tmpdir),
         :ok           <- validate_within_tmpdir(zip_full_path, tmpdir),

         :ok           <- reject_existing_file(cwd_full_path),
         :ok           <- reject_existing_dir(zip_full_path),
         :ok           <- ensure_dir_exists(zip_full_path, tmpdir),
         :ok           <- validate_path_exists(src_full_path),
         :ok           <- validate_suffix(src_path, cwd_full_path),
         {:ok, args}   <- opts |> Map.new() |> extract_zip_args(),
         :ok           <- try_zip_cmd(args ++ [zip_path, src_path], cwd_full_path) do
      if zip_full_path |> Path.basename() |> String.contains?(".") do
        {:ok, zip_full_path}
      else
        {:ok, zip_full_path <> ".zip"}
      end
    end
  end

  defp extract_epool_id(%Context{executor_pool_id: epool_id}), do: epool_id
  defp extract_epool_id(epool_id),                             do: epool_id

  defunp validate_within_tmpdir(path :: v[String.t], tmpdir :: v[String.t]) :: :ok | {:error, tuple} do
    if path == tmpdir or String.starts_with?(path, "#{tmpdir}/") do
      :ok
    else
      {:error, {:permission_denied, %{path: path, tmpdir: tmpdir}}}
    end
  end

  defunp reject_existing_file(path :: v[String.t]) :: :ok | {:error, tuple} do
    if File.dir?(path) do
      :ok
    else
      {:error, {:not_dir, %{path: path}}}
    end
  end

  defunp reject_existing_dir(path :: v[String.t]) :: :ok | {:error, tuple} do
    if File.dir?(path) do
      {:error, {:is_dir, %{path: path}}}
    else
      :ok
    end
  end

  defunp ensure_dir_exists(path :: v[String.t], tmpdir :: v[String.t]) :: :ok | {:error, tuple} do
    dirname = Path.dirname(path)
    if dirname != tmpdir do
      case File.mkdir_p(dirname) do
        :ok ->
          :ok
        {:error, :eexist} ->
          {:error, {:not_dir, %{path: path}}}
      end
    else
      :ok
    end
  end

  defunp validate_path_exists(path :: v[String.t]) :: :ok | {:error, tuple} do
    if File.exists?(path) do
      :ok
    else
      {:error, {:not_found, %{path: path}}}
    end
  end

  defunp validate_suffix(src_path :: v[String.t], cwd_path :: v[String.t]) :: :ok | {:error, tuple} do
    suffixed = String.ends_with?(src_path, "/")
    src_full_path = Path.expand(src_path, cwd_path)
    if suffixed and !File.dir?(src_full_path) do
      {:error, {:not_dir, %{path: src_full_path}}}
    else
      :ok
    end
  end

  defunp extract_zip_args(map :: map) :: R.t(list(String.t)) do
    case map do
      %{password: ""} ->
        {:error, {:argument_error, map}}
      %{encryption: true,  password: password} ->
        {:ok,    ["-P", password]}
      %{encryption: true} ->
        {:error, {:argument_error, map}}
      %{encryption: false, password: _} ->
        {:error, {:argument_error, map}}
      _ ->
        {:ok,    []}
    end
  end

  defunp try_zip_cmd(args :: v[list(String.t)], cwd_path :: v[String.t]) :: :ok | {:error, :shell_runtime_error} do
    case System.cmd("zip", args, [cd: cwd_path]) do
      {_, 0} ->
        :ok
      _ ->
        {:error, :shell_runtime_error}
    end
  end
end
