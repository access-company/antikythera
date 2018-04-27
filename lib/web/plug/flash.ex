# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Plug.Flash do
  @moduledoc """
  Plug to automatically load flash messages from session.

  ## Usage

  Add the following line in a controller module (note that the order of the plugs is important):

      plug SolomonLib.Plug.Session, :load, [key: "12345678"]
      plug SolomonLib.Plug.Flash  , :load, []

  Then you can access flash messages by

  - `SolomonLib.Conn.get_flash/2`
  - `SolomonLib.Conn.put_flash/3`
  """

  alias SolomonLib.Conn

  @session_key "antikythera_flash"

  defun load(conn :: v[Conn.t], _opts :: any) :: Conn.t do
    flash = case Conn.get_session(conn, @session_key) do
      nil   -> %{}
      value -> value
    end
    conn
    |> Conn.assign(:flash, flash)
    |> Conn.register_before_send(&before_send/1)
  end

  defunp before_send(%Conn{status: status, assigns: assigns} = conn) :: Conn.t do
    if !Enum.empty?(assigns.flash) and status in 300..308 do
      Conn.put_session(conn, @session_key, assigns.flash)
    else
      Conn.delete_session(conn, @session_key)
    end
  end
end
