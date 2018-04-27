# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule SolomonLib.Controller do
  @moduledoc """
  Helper module to bulk-import many controller-related modules.

  It's recommended to `use SolomonLib.Controller` (either directly or indirectly) in your controller modules.
  """

  defmacro __using__(_) do
    quote do
      use   SolomonLib.Controller.Plug
      alias SolomonLib.Conn
    end
  end
end
