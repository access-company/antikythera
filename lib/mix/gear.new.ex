# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.Antikythera.Gear.New do
  @shortdoc "Generates a mix project for a new gear application"
  @symlink_candidates [
    {".credo.exs",
     "Configuration file for static code analysis tool [Credo](https://github.com/rrrene/credo)"},
    {".tool-versions",
     "Local versions file for version manager tool [asdf](https://github.com/asdf-vm/asdf)"}
  ]
  @symlink_candidates_description @symlink_candidates
                                  |> Enum.map(fn {name, desc} -> "- `#{name}`\n    - #{desc}" end)
                                  |> Enum.join("\n")
  @dep_env_var "ANTIKYTHERA_INSTANCE_DEP"
  @moduledoc """
  #{@shortdoc}.

  ## Usage

  This mix task must be run from a mix project directory of either
  your antikythera instance or one of gears in your antikythera instance.

      mix antikythera.gear.new PATH

  Basename of `PATH` becomes the name of your gear.
  For example, if `~/workspace/my_gear` is used, `my_gear` becomes your gear name.

  Newly generated gear automatically belongs to an antikythera instance
  inferred from the mix project you are currently in.

  You can also manually specify your antikythera instance via `#{@dep_env_var}` environment variable like so:

      #{@dep_env_var}='{:instance_name, [git: "git@github.com:your-organization/instance_name.git"]}' mix antikythera.gear.new PATH

  `#{@dep_env_var}` must be a valid dependency tuple used in `mix.exs` files.
  See [`mix deps` doc](https://hexdocs.pm/mix/Mix.Tasks.Deps.html) for available options.

  ## Symbolic links to files in your antikythera instance

  In order to sync development environment configurations with your antikythera instance and other gears,
  this generator creates symbolic links to these files, if they exist in the current directory:

  #{@symlink_candidates_description}
  """

  use Mix.Task

  def run(args) do
    case args do
      [path] ->
        {gear_name, dest_dir} = validate_path!(path)
        instance_dep = infer_instance_dep!()
        gen_files(gear_name, dest_dir, instance_dep)
        add_symlinks(dest_dir, instance_dep)

      _ ->
        Mix.raise("Usage: mix antikythera.gear.new PATH")
    end
  end

  defp validate_path!(path0) do
    path = Path.expand(path0)
    gear_name = Path.basename(path)

    if !Antikythera.GearNameStr.valid?(gear_name) do
      Mix.raise(
        "gear name (basename of PATH) must (1) start with lowercase alphabet, (2) have only lowercase alphabets, numbers and underscore, and (3) its length must be within [3,32]."
      )
    end

    {gear_name, path}
  end

  defp infer_instance_dep!() do
    runtime_mix_project_config = Mix.Project.config()

    cond do
      instance_dep = System.get_env(@dep_env_var) ->
        validate_instance_dep_from_env_var!(instance_dep)

      gear_info = Keyword.get(runtime_mix_project_config, :antikythera_gear) ->
        Keyword.fetch!(gear_info, :instance_dep)

      true ->
        case Keyword.fetch!(runtime_mix_project_config, :app) do
          :antikythera ->
            Mix.raise(
              "You must be in a mix project directory of either your antikythera instance or one of gears in your antikythera instance."
            )

          instance_name ->
            {instance_name, [git: instance_git_url_from_git_remote!()]}
        end
    end
  end

  @dep_env_var_help "#{@dep_env_var} must be a proper mix dependency tuple! See https://hexdocs.pm/mix/Mix.Tasks.Deps.html for details."

  defp validate_instance_dep_from_env_var!(raw_str) do
    expression =
      try do
        {expression, _bindings} = Code.eval_string(raw_str)
        expression
      rescue
        e ->
          Mix.raise(Exception.message(e) <> "\n\n" <> @dep_env_var_help)
      end

    if is_tuple(expression), do: expression, else: Mix.raise(@dep_env_var_help)
  end

  defp instance_git_url_from_git_remote!() do
    case System.cmd("git", ["remote", "get-url", "origin"]) do
      {instance_git_url, 0} ->
        String.trim(instance_git_url)

      {output, _nonzero} ->
        Mix.raise(
          "Tried to read url of git remote 'origin' for antikythera instance dependency, but encountered the following error:\n#{
            output
          }"
        )
    end
  end

  defp gen_files(gear_name, dest_dir, instance_dep) do
    Mix.Generator.create_directory(dest_dir)

    binding = [
      gear_name: gear_name,
      gear_name_camel: Macro.camelize(gear_name),
      instance_dep: inspect(instance_dep)
    ]

    instance_name = elem(instance_dep, 0)
    dir1 = :code.priv_dir(:antikythera)

    dirs =
      :code.priv_dir(instance_name)
      |> case do
        {:error, _} -> [dir1]
        dir2 -> [dir1, dir2]
      end

    Enum.each(dirs, fn dir ->
      template_dir = Path.join(dir, "gear_template")

      Enum.each(template_files(template_dir), fn template_path ->
        dest_rel_path =
          template_path
          |> Path.relative_to(template_dir)
          |> String.replace("gear_name", gear_name)

        dest_path = Path.join(dest_dir, dest_rel_path)
        content = EEx.eval_file(template_path, binding)
        Mix.Generator.create_file(dest_path, content, force: true)
      end)
    end)
  end

  defp template_files(template_dir) do
    Path.join([template_dir, "**", "*"])
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
  end

  defp add_symlinks(dest_dir, instance_dep) do
    # Neither `File` nor `Mix.Generator` support copying symlinks without dereferencing, so we manually create symlinks
    instance_name_str = Atom.to_string(elem(instance_dep, 0))

    Enum.each(symlink_targets(), fn name ->
      link_from = Path.join(dest_dir, name)
      link_to = Path.join(["deps", instance_name_str, name])
      File.ln_s!(link_to, link_from)
      Mix.shell().info([:green, "* symbolic link ", :reset, link_from, " -> ", link_to])
    end)
  end

  @symlink_candidate_filenames Enum.map(@symlink_candidates, &elem(&1, 0))

  defp symlink_targets() do
    files_in_cwd = File.ls!(File.cwd!())

    # Assuming that, even if the task is run from a gear project, as long as that gear is generated for the same antikythera instance,
    # it should have the same set of configuration files symlinked to ones in the user's antikythera instance project
    Enum.filter(@symlink_candidate_filenames, fn candidate -> candidate in files_in_cwd end)
  end
end
