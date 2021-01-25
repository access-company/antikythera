# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraLocal.PrepareCore do
  @shortdoc "Builds an OTP release for an antikythera instance"

  use Mix.Task

  def run(args) do
    do_upgrade =
      case args do
        [] -> true
        ["noupgrade"] -> false
      end

    version = AntikytheraLocal.RunningEnvironment.prepare_new_version_of_core(do_upgrade)
    output_version = if do_upgrade, do: version, else: "#{version} noupgrade"
    IO.puts("Successfully prepared new version of core (#{output_version})")
  end
end
