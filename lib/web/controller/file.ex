# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Controller.File do
  @moduledoc """
  [DEPRECATED] Defines `SolomonLib.Controller.File.send_priv_file/3`.
  """

  defdelegate send_priv_file(conn, status, path), to: SolomonLib.Conn
end
