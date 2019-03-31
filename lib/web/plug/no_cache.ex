# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Plug.NoCache do
  @header_value "private, no-cache, no-store, max-age=0"
  def header_value(), do: @header_value

  @moduledoc """
  Plug to set a fixed value of `cache-control` response header in order to disable client side caching.

  The value used is: `"#{@header_value}"`.

  ## Usage

  Put the following line in your controller module:

      plug Antikythera.Plug.NoCache, :put_resp_header, []

  Note that this plug runs before your controller's actions; in your actions you can overwrite the `cache-control` header set by this plug.
  """

  alias Antikythera.Conn

  defun put_resp_header(conn :: v[Conn.t], _opts :: any) :: Conn.t do
    Conn.put_resp_header(conn, "cache-control", @header_value)
  end
end
