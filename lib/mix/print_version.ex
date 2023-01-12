# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.Antikythera.PrintVersion do
  @shortdoc "Prints the current version of an OTP app (defaults to current mix project)"

  use Mix.Task

  def run([]) do
    IO.puts(Mix.Project.config()[:version])
  end

  def run([app_name]) do
    lib_dir = Path.join([Mix.Project.build_path(), "lib", app_name])
    IO.puts(AntikytheraCore.Version.read_from_app_file(lib_dir, app_name))
  end
end
