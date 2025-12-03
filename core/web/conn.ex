# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Conn do
  alias Antikythera.{Http.Method, Conn, Request, Context, GearName}
  alias Antikythera.G2gRequest, as: GReq
  alias Antikythera.G2gResponse, as: GRes
  alias AntikytheraCore.Request, as: CoreReq
  alias AntikytheraCore.Context, as: CoreContext
  alias AntikytheraCore.Cookies, as: CoreCookies
  alias AntikytheraCore.Handler.GearError

  def make_from_cowboy_req(
        req,
        {gear_name, entry_point, method, path_info, path_matches},
        qparams,
        body_pair
      ) do
    antikythera_req =
      CoreReq.make_from_cowboy_req(req, method, path_info, path_matches, qparams, body_pair)

    # context_id is generated; epool_id will be filled afterward
    context = CoreContext.make(gear_name, entry_point)
    make_conn(antikythera_req, context)
  end

  def make_from_g2g_req_and_context(
        %GReq{
          method: method,
          query_params: query_params,
          headers: headers,
          cookies: cookies,
          body: body
        },
        %Context{gear_name: sender_name, context_id: context_id, executor_pool_id: epool_id},
        receiver_name,
        entry_point,
        path_info,
        path_matches
      ) do
    {raw_body, normalized_body, default_headers} =
      if method in [:put, :post, :patch] do
        get_normalized_body_and_default_headers(body)
      else
        {"", body, %{}}
      end

    headers_with_default = Map.merge(default_headers, headers)

    request = %Request{
      method: method,
      path_info: path_info,
      path_matches: path_matches,
      query_params: query_params,
      headers: headers_with_default,
      cookies: cookies,
      raw_body: raw_body,
      body: normalized_body,
      sender: {:gear, sender_name}
    }

    context = CoreContext.make(receiver_name, entry_point, context_id, epool_id)
    make_conn(request, context)
  end

  defp get_normalized_body_and_default_headers(body) when is_binary(body) do
    len = byte_size(body) |> Integer.to_string()
    {body, body, %{"content-type" => "text/plain", "content-length" => len}}
  end

  defp get_normalized_body_and_default_headers(body) when is_map(body) or is_list(body) do
    encoded = Poison.encode!(body)
    len = byte_size(encoded) |> Integer.to_string()
    normalized = Poison.decode!(encoded)
    {encoded, normalized, %{"content-type" => "application/json", "content-length" => len}}
  end

  defp make_conn(request, context) do
    # Explicitly fill default values here (current version of `Croma.Struct` provides no way to specify defaults of struct fields)
    %Conn{
      request: request,
      context: context,
      status: nil,
      resp_headers: %{},
      resp_cookies: %{},
      resp_body: "",
      before_send: [],
      assigns: %{},
      chunked: %{}
    }
  end

  def reply_as_cowboy_res(
        %Conn{
          status: status,
          resp_headers: headers,
          resp_cookies: resp_cookies,
          resp_body: body,
          chunked: chunked
        } = conn,
        req
      ) do
    try do
      headers_with_defaults = add_default_resp_headers(headers)
      req2 = CoreCookies.merge_cookies_to_cowboy_req(resp_cookies, req)

      # Check if this is a chunked response
      case Map.get(chunked, :enabled) do
        true ->
          send_chunked_response(status, headers_with_defaults, chunked, req2)

        _ ->
          send_normal_response(status, headers_with_defaults, body, req2)
      end
    rescue
      e ->
        # Field in `conn` is of unexpected type; we must fall-back to the gear's error handler (and then recur).
        st = __STACKTRACE__
        # Just to suppress validation error (due to invalid resp_body) during testing
        %Conn{conn | resp_body: ""}
        |> GearError.error({:error, e}, st)
        |> reply_as_cowboy_res(req)
    end
  end

  @default_secure_headers %{
    "x-frame-options" => "DENY",
    "x-xss-protection" => "1; mode=block",
    "x-content-type-options" => "nosniff",
    "strict-transport-security" => "max-age=31536000"
  }

  defp add_default_resp_headers(headers) do
    # Header names for :cowboy_req.reply must be lowercase; see also: http://ninenines.eu/docs/en/cowboy/HEAD/guide/resp/
    headers_downcased = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

    # content-length header should be calculated based on the actual body and thus neglected (if any)
    headers_without_cl = Map.delete(headers_downcased, "content-length")
    Map.merge(@default_secure_headers, headers_without_cl)
  end

  defp send_chunked_response(status, headers, chunked, req) do
    # Initiate chunked response
    req2 = :cowboy_req.stream_reply(status, headers, req)

    # Send all accumulated chunks (reverse because we cons'd them)
    chunks = Map.get(chunked, :chunks, [])

    Enum.each(Enum.reverse(chunks), fn chunk_body ->
      :cowboy_req.stream_body(chunk_body, :nofin, req2)
    end)

    # Send final chunk to close the stream
    :cowboy_req.stream_body("", :fin, req2)
  end

  defp send_normal_response(status, headers, body, req) do
    if body == nil or body == "" do
      :cowboy_req.reply(status, headers, req)
    else
      :cowboy_req.reply(status, headers, body, req)
    end
  end

  def reply_as_g2g_res(
        %Conn{status: status, resp_headers: headers, resp_cookies: resp_cookies, resp_body: body} =
          conn
      ) do
    downcased_headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)

    try do
      if not is_binary(body) do
        raise "unexpected `resp_body` returned by controller action"
      end

      GRes.new!(status: status, headers: downcased_headers, cookies: resp_cookies, body: body)
    rescue
      e ->
        # Field in `conn` is of unexpected type; we must fall-back to the gear's error handler (and then recur).
        st = __STACKTRACE__
        # Just to suppress validation error (due to invalid resp_body) during testing
        %Conn{conn | resp_body: ""}
        |> GearError.error({:error, e}, st)
        |> reply_as_g2g_res()
    end
  end

  def run_before_send(conn, conn_before_action) do
    try do
      case conn do
        %Conn{before_send: before_send} -> Enum.reduce(before_send, conn, & &1.(&2))
        _ -> raise "unexpected value returned by controller action"
      end
    rescue
      e -> GearError.error(conn_before_action, {:error, e}, __STACKTRACE__)
    end
  end

  defun gear_name(%Conn{context: %Context{gear_name: gear_name}}) :: GearName.t(), do: gear_name

  defun request_info(%Conn{request: %Request{method: m, path_info: pi, query_params: q}}) ::
          String.t() do
    method_string = Method.to_string(m)
    path = "/" <> Enum.join(pi, "/")

    if Enum.empty?(q) do
      "#{method_string} #{path}"
    else
      params = Enum.map_join(q, "&", fn {k, v} -> "#{k}=#{v}" end)
      "#{method_string} #{path}?#{params}"
    end
  end

  # RFC9110 says:
  # > All 1xx (Informational), 204 (No Content), and 304 (Not Modified) responses do not include content.
  # RFC9110 has only 100 and 101 for 1xx.
  @empty_body_status_codes [100, 101, 204, 304]
  defun validate(%Conn{status: status, resp_body: body}) :: :ok do
    if Enum.member?(@empty_body_status_codes, status) do
      0 = byte_size(body)
    end

    :ok
  end
end
