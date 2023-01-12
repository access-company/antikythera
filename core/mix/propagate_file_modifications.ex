# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.Compile.PropagateFileModifications do
  @shortdoc "Touches source files that need to be recompiled"

  @moduledoc """
  #{@shortdoc}.

  Normally mix automatically resolves which source files to recompile based on file modification times.
  However some macro-related code modifications do not trigger recompilation.
  This mix task finds those kinds of modifications and touch files to compile so that subsequent task recompiles them.

  Note that `@external_resource` module attribute does not support directory as external dependency of a module.
  For a module that depends on all files under a directory, we have to manually check the latest modification time
  of the whole directory tree.

  Current targets of this task are:

  - `mix.exs` files in gear projects depend on `mix_common.exs` in the antikythera repository.
    Mix assumes that project configurations reside only in `mix.exs` and `config/*.exs`,
    so even if `mix_common.exs` has been modified mix does not notice.
    Note that antikythera's `mix.exs` also depends on `mix_common.exs` but it's handled differently
    (at the beginning of `mix.exs`), because we can't run mix tasks before it's compiled!
  - `SomeGear.Template` module depends on all existing HAML templates in `web/template/`.
  - Similarly, `SomeGear.Asset` module depends on all asset files in `priv/static/`.
    Although `SomeGear.Asset` is recompiled after modifying an asset file, it doesn't automatically trigger
    recompilation/reload in iex session because `priv/static/**` is not monitored by `:exsync` (in current configuration).
  """

  use Mix.Task.Compiler

  def run(_) do
    mix_common_path = Path.join([__DIR__, "..", "..", "mix_common.exs"])
    touch_if_older_than_any("mix.exs", [mix_common_path])
    touch_if_older_than_any_in_dir(Path.join("web", "template.ex"), Path.join("web", "template"))
    touch_if_older_than_any_in_dir(Path.join("web", "asset.ex"), Path.join("priv", "static"))
    {:ok, []}
  end

  defp touch_if_older_than_any(target, dependencies) do
    case File.stat(target) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if newer_dependency_exists?(mtime, dependencies) do
          File.touch!(target)
        end

      {:error, :enoent} ->
        :ok
    end
  end

  defp newer_dependency_exists?(target_mtime, dependencies) do
    Enum.any?(dependencies, fn d ->
      case File.stat(d) do
        {:ok, stat} -> target_mtime < stat.mtime
        # neglect nonexisting entry (probably due to absence of toplevel of the directory tree)
        {:error, :enoent} -> false
      end
    end)
  end

  defp touch_if_older_than_any_in_dir(target, dir) do
    paths = Path.wildcard(Path.join(dir, "**"))
    touch_if_older_than_any(target, [dir | paths])
  end
end
