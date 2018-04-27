# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Mix.Task do
  @moduledoc """
  Helper functions for making mix tasks in gears.

  **Functions in this module can only be used in mix tasks.**
  """

  @doc """
  Starts the current antikythera instance and its dependency applications without web server functionality.

  If you need web server functionality in your mix task,
  use `Application.ensure_all_started(SolomonLib.Env.antikythera_instance_name())`.
  """
  defun prepare_antikythera_instance() :: :ok do
    System.put_env("NO_LISTEN", "true")
    {:ok, _} = Application.ensure_all_started(SolomonLib.Env.antikythera_instance_name())
    :ok
  end
end
