# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraCore.GenerateAppup do
  @shortdoc "Generates an appup file using the previous version located at the specified directory"

  @moduledoc """
  #{@shortdoc}.

  This task is invoked during gear deployments.
  """

  use Mix.Task
  alias AntikytheraCore.Release.Appup

  def run([prev_dir]) do
    config       = Mix.Project.config()
    name         = config[:app]
    new_version  = config[:version]
    new_dir      = "#{build_path()}/#{Mix.env()}/lib/#{name}"
    prev_version = AntikytheraCore.Version.read_from_app_file(prev_dir, name)

    Appup.make(name, prev_version, new_version, prev_dir, new_dir)
    IO.puts("Successfully generated #{new_dir}/ebin/#{name}.appup")
  end

  defp build_path() do
    # See also `Antikythera.MixCommon.build_path/0`
    if System.get_env("ANTIKYTHERA_COMPILE_ENV") == "local", do: "_build_local", else: "_build"
  end
end
