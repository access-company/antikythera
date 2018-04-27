# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.File do
  @moduledoc """
  [DEPRECATED] Defines `Antikythera.Controller.File.send_priv_file/3`.
  """

  defdelegate send_priv_file(conn, status, path), to: Antikythera.Conn
end
