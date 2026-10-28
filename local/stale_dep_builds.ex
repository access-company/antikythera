# Copyright(c) 2015-2026 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.StaleDepBuilds do
  @moduledoc """
  Removes builds of hex deps whose versions differ from the ones in `mix.lock`.

  `mix deps.get` marks fetched deps to be recompiled only under the build path of the current run,
  which is either `_build` or `_build_local` (see `Antikythera.MixCommon`).
  When a gear directory is used with both build paths (e.g. by a gear's own CI job and by
  `mix antikythera_local.upgrade_compatibility_test`), only the run that first fetches a new version
  marks its builds; builds under the other build path are left with the old version.
  Mix then refuses to compile such a dep if its version doesn't satisfy an exact version requirement
  ("the dependency does not match the requirement"), or silently keeps using the old build otherwise.
  Removing the stale builds makes mix recompile them.
  """

  @build_dirs ["_build", "_build_local"]

  defun remove(project_dir :: Path.t()) :: :ok do
    for {app, lock_entry} <- read_lock(Path.join(project_dir, "mix.lock")),
        elem(lock_entry, 0) == :hex,
        build_dir <- @build_dirs,
        app_file <-
          Path.wildcard(
            Path.join([project_dir, build_dir, "*", "lib", "#{app}", "ebin", "#{app}.app"])
          ) do
      remove_if_stale(app, elem(lock_entry, 2), app_file)
    end

    :ok
  end

  defunp remove_if_stale(app :: atom, locked_version :: String.t(), app_file :: Path.t()) :: :ok do
    case read_built_version(app_file) do
      ^locked_version ->
        :ok

      built_version ->
        lib_dir = app_file |> Path.dirname() |> Path.dirname()

        IO.puts(
          "Removing stale build of #{app} (built: #{inspect(built_version)}, locked: #{locked_version}): #{lib_dir}"
        )

        File.rm_rf!(lib_dir)
        :ok
    end
  end

  defunp read_lock(lock_path :: Path.t()) :: map do
    # Suppress warnings about quoted keys (e.g. `"certifi": ...`), as mix does when reading `mix.lock`
    {:ok, quoted} =
      Code.string_to_quoted(File.read!(lock_path), file: lock_path, emit_warnings: false)

    {%{} = lock, _bindings} = Code.eval_quoted(quoted, [], file: lock_path)
    lock
  end

  defunp read_built_version(app_file :: Path.t()) :: nil | String.t() do
    with {:ok, [{:application, _, kw}]} <- :file.consult(app_file),
         vsn when is_list(vsn) <- kw[:vsn] do
      List.to_string(vsn)
    else
      _ -> nil
    end
  end
end
