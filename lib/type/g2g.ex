# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma
alias Antikythera.Http

defmodule Antikythera.G2gRequest do
  alias Antikythera.EncodedPath

  use Croma.Struct,
    recursive_new?: true,
    fields: [
      method: Http.Method,
      path: EncodedPath,
      query_params: Http.QueryParams,
      headers: Http.Headers,
      cookies: Http.ReqCookiesMap,
      body: Http.Body
    ]

  defun from_web_request(%Antikythera.Request{
          method: m,
          path_info: pi,
          query_params: q,
          headers: hs,
          cookies: cookies,
          body: b
        }) :: t do
    %__MODULE__{
      method: m,
      path: "/" <> Enum.join(pi, "/"),
      query_params: q,
      headers: hs,
      cookies: cookies,
      body: b
    }
  end
end

defmodule Antikythera.G2gResponse do
  use Croma.Struct,
    recursive_new?: true,
    fields: [
      status: Http.Status.Int,
      headers: Http.Headers,
      cookies: Http.SetCookiesMap,
      body: Http.Body
    ]

  @doc """
  Creates a new version of `Antikythera.G2gResponse` struct by body decompression and decoding.

  This function decompresses body of g2g response according to `content-encoding` and then
  decodes the uncompressed body according to `content-type`.
  If decompressed, `content-encoding` header is removed from the returned `Antikythera.G2gResponse`.

  This function is used internally in `G2g.send/{1,2}` (i.e. body decoding is done automatically).
  Basically gear implementations do not need this function.
  The typical use case of this function (in conjunction with `G2g.send_without_decoding/{1,2}`)
  is to avoid unnecessary encoding/decoding when a gear action

  - returns the g2g response as it is, and
  - reads body of the g2g response.
  """
  defun decode_body(%__MODULE__{headers: headers, body: body} = res) :: t do
    if is_map(body) or is_list(body) do
      res
    else
      {uncompressed, headers2} =
        case headers["content-encoding"] do
          "gzip" -> {:zlib.gunzip(body), Map.delete(headers, "content-encoding")}
          "deflate" -> {:zlib.unzip(body), Map.delete(headers, "content-encoding")}
          _ -> {body, headers}
        end

      decoded =
        case headers2["content-type"] do
          "application/json" <> _charset -> Poison.decode!(uncompressed)
          _ -> uncompressed
        end

      %__MODULE__{res | headers: headers2, body: decoded}
    end
  end
end
