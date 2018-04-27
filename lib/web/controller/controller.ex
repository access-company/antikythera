# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Controller do
  @moduledoc """
  Helper module to bulk-import many controller-related modules.

  It's recommended to `use Antikythera.Controller` (either directly or indirectly) in your controller modules.
  """

  defmacro __using__(_) do
    quote do
      use   Antikythera.Controller.Plug
      alias Antikythera.Conn
    end
  end
end
