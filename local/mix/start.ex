# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraLocal.Start do
  @shortdoc "Builds an OTP release for an antikythera instance and runs it with the specified gears"

  use Mix.Task
  alias Antikythera.Env

  def run(gear_repo_dirs) do
    if !Enum.empty?(AntikytheraLocal.RunningEnvironment.currently_running_os_process_ids()) do
      raise "#{Env.antikythera_instance_name()} already started"
    end

    AntikytheraLocal.RunningEnvironment.setup(gear_repo_dirs)
    IO.puts("Successfully started #{Env.antikythera_instance_name()}.")
  end
end
