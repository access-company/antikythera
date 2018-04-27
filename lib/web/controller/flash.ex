# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Controller.Flash do
  @moduledoc """
  [DEPRECATED] Defines `SolomonLib.Controller.Flash.get_flash/2` and `SolomonLib.Controller.Flash.put_flash/3`.
  """

  defdelegate get_flash(conn, key), to: SolomonLib.Conn
  defdelegate put_flash(conn, key, value), to: SolomonLib.Conn
end
