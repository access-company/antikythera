# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraLocal.Stop do
  @shortdoc "Stops a locally running OTP release for an antikythera instance"

  use Mix.Task
  alias Antikythera.Env

  def run(_args) do
    :ok = AntikytheraLocal.RunningEnvironment.teardown()
    IO.puts("Successfully stopped #{Env.antikythera_instance_name()}.")
  end
end
