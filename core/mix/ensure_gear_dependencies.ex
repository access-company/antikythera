# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.Compile.EnsureGearDependencies do
  @shortdoc "Ensures only gear applications are specifed in `gear_deps/0`"
  @moduledoc """
  #{@shortdoc}.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Project.config()
    |> Keyword.fetch!(:antikythera_gear)
    |> Keyword.fetch!(:gear_deps)
    |> Enum.each(fn dep -> ensure_gear_dependency!(elem(dep, 0), extract_opts_from_dep(dep)) end)
  end

  defp extract_opts_from_dep({_app, _req, opts})             , do: opts
  defp extract_opts_from_dep({_app, opts}) when is_list(opts), do: opts
  defp extract_opts_from_dep({_app, _req})                   , do: []

  defp ensure_gear_dependency!(gear_name, opts) do
    gear_mixfile_module = Mix.Project.in_project(gear_name, gear_dir(gear_name, opts), fn mod -> mod end)
    if gear_mixfile_module.project() |> Keyword.has_key?(:antikythera_gear) do
      :ok
    else
      Mix.raise("#{gear_name} is not a gear application! `gear_deps/0` may only contain gear dependencies.")
    end
  end

  defp gear_dir(gear_name, opts) do
    case Keyword.fetch(opts, :path) do
      {:ok, path} -> gear_dir_as_local_dep(path)
      :error      -> gear_dir_as_remote_dep(gear_name)
    end
  end

  defp gear_dir_as_local_dep(path) do
    if Antikythera.Env.compiling_for_cloud?() do
      Mix.raise("Local path dependencies are not allowed in cloud environment (#{path}).")
    else
      Path.absname(path) |> Path.expand()
    end
  end

  defp gear_dir_as_remote_dep(gear_name) do
    cwd               = File.cwd!()
    parent_dir_of_cwd = Path.expand("..", cwd)
    gear_name_str     = Atom.to_string(gear_name)
    case Path.basename(parent_dir_of_cwd) do
      "deps" -> Path.join(parent_dir_of_cwd, gear_name_str) # this gear project itself is being compiled as a gear dependency; its gear dependencies are located at sibling directories
      _      -> Path.join([cwd, "deps", gear_name_str])     # this gear project is the toplevel mix project
    end
  end
end
