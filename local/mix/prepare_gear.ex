# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraLocal.PrepareGear do
  @shortdoc "Builds an OTP application tarball of the specified gear"

  use Mix.Task

  def run(args) do
    {gear_repo_dir, do_upgrade} = case args do
      [gear_repo_dir]              -> {gear_repo_dir, true }
      [gear_repo_dir, "noupgrade"] -> {gear_repo_dir, false}
    end
    version = AntikytheraLocal.RunningEnvironment.prepare_new_version_of_gear(gear_repo_dir, do_upgrade)
    output_version = if do_upgrade, do: version, else: "#{version} noupgrade"
    IO.puts("Successfully prepared new version of #{Path.basename(gear_repo_dir)} (#{output_version})")
  end
end
