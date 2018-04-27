# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Controller.Json do
  @moduledoc """
  [DEPRECATED] Defines `SolomonLib.Controller.Json.json/3`.
  """

  defdelegate json(conn, status, body), to: SolomonLib.Conn
end
