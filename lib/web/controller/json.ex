# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.Json do
  @moduledoc """
  [DEPRECATED] Defines `Antikythera.Controller.Json.json/3`.
  """

  defdelegate json(conn, status, body), to: Antikythera.Conn
end
