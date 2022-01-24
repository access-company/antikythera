# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Plug.ContentDecoding do
  @moduledoc """
  Plug to decompress the request body when the request has `Content-Encoding` header.

  Currently only `gzip` is supported.

  Antikythera does not transparently handle compressed request body, as [cowboy](https://github.com/ninenines/cowboy/issues/946).
  Compression can pack very large data into a small body, so automatically decompressing it may lead to running out of memory.

  Therefore, this plug can be used only if the request client is trusted (e.g. after authentication).

  ## Usage

  Put the following line in your controller module:

      plug Antikythera.Plug.ContentDecoding, :decode, []
  """

  alias Croma.Result
  alias Antikythera.{Request, Conn, Http.Body}

  defun decode(%Conn{request: request} = conn) :: v[Conn.t()] do
    case Conn.get_req_header(conn, "content-encoding") do
      "gzip" -> decode_gzip(request.body)
      _ -> {:ok, request.body}
    end
    |> case do
      {:ok, decoded_body} ->
        Conn.request(conn, Request.body(request, decoded_body))

      {:error, _} ->
        Conn.put_status(conn, 400) |> Conn.put_resp_body("Unable to decode the body.")
    end
  end

  defunp decode_gzip(body :: Body.t()) :: Result.t(binary) do
    Result.try(fn -> :zlib.gunzip(body) end)
  end
end
