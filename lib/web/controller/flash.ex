# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.Flash do
  @moduledoc """
  [DEPRECATED] Defines `Antikythera.Controller.Flash.get_flash/2` and `Antikythera.Controller.Flash.put_flash/3`.
  """

  defdelegate get_flash(conn, key), to: Antikythera.Conn
  defdelegate put_flash(conn, key, value), to: Antikythera.Conn
end
