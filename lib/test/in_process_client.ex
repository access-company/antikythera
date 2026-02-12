# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Test.InProcessClient do
  @moduledoc """
  In-process test helper that runs the gear handler pipeline (routing, plugs, controller, before_send)
  without HTTP overhead. Same API as `Antikythera.Test.HttpClient`.

  This module uses a test-only code path that does not fully replicate the production request handling.
  Use `Antikythera.Test.HttpClient` for end-to-end testing of the full production path.

  ## Usage

      # In test_helper.exs, add alongside the existing Req:
      defmodule ReqInProcess do
        use Antikythera.Test.InProcessClient
      end

      # Then in tests, use ReqInProcess instead of Req:
      ReqInProcess.get("/api/hello")

  ## Limitations

  The following aspects of production request handling are **not** reproduced;
  tests that depend on them must use `Antikythera.Test.HttpClient` instead.

    * **HTTP streaming (SSE).** Routes declared with `streaming: true` are
      invoked once; the streaming loop that calls the action repeatedly until
      `Conn.end_chunked/1` is not run.
    * **WebSocket.** WebSocket upgrades go through `cowboy_websocket`; they
      cannot be exercised here.
    * **Static files (`:cowboy_static`).** `static_prefix` routes are served by
      cowboy directly and never reach a gear action, so they resolve to
      `no_route`.
    * **Response body compression.** Cowboy applies gzip based on
      `Accept-Encoding` after the gear returns; in-process callers see the
      uncompressed body.
    * **Action timeout and heap limit.** The action runs synchronously in the
      caller's process with no `spawn_opt` `max_heap_size` and no enforced
      timeout, so `:timeout` / `:killed` error-handler paths are unreachable
      and long-running actions block the test.
    * **Request body size cap.** Cowboy's 8 MB `read_body` limit is not
      enforced; oversized bodies are passed through.
    * **Executor pool resolution.** `executor_pool_id` is hardcoded to
      `{:gear, gear_name}`; the gear's `executor_pool_for_web_request/1`
      callback is not consulted, so tenant pools and the
      `bad_executor_pool_id` error path cannot be tested.
    * **Handler process lifetime.** The action runs in the calling test
      process, so assertions about a separate handler process (e.g.
      `Process.info(handler_pid, :dictionary)`) do not apply.
    * **Cowboy-provided features in general.** Anything that cowboy would do
      outside `init/2` (request-line parsing, protocol framing, TLS / peer
      info, stream handlers, connection timeouts, etc.) is not exercised.
  """

  defmacro __using__(_) do
    quote do
      @default_base_url Antikythera.Test.Config.base_url()
      @gear_name Mix.Project.config()[:app]

      alias Antikythera.Test.InProcessClient

      def get(path, headers \\ %{}, options \\ []) do
        InProcessClient.dispatch(@gear_name, :get, base_url() <> path, "", headers, options)
      end

      def post(path, body, headers \\ %{}, options \\ []) do
        InProcessClient.dispatch(@gear_name, :post, base_url() <> path, body, headers, options)
      end

      def post_json(path, json, headers \\ %{}, options \\ []) do
        post(path, {:json, json}, headers, options)
      end

      def post_form(path, query, headers \\ %{}, options \\ []) do
        post(path, {:form, query}, headers, options)
      end

      def put(path, body, headers \\ %{}, options \\ []) do
        InProcessClient.dispatch(@gear_name, :put, base_url() <> path, body, headers, options)
      end

      def put_json(path, json, headers \\ %{}, options \\ []) do
        put(path, {:json, json}, headers, options)
      end

      def delete(path, headers \\ %{}, options \\ []) do
        InProcessClient.dispatch(@gear_name, :delete, base_url() <> path, "", headers, options)
      end

      def base_url(), do: @default_base_url

      defoverridable base_url: 0
    end
  end

  alias Antikythera.GearName
  alias Antikythera.Http.{Method, Headers, SetCookie}
  alias Antikythera.Httpc.{Response, ReqBody}
  alias AntikytheraCore.Handler.GearAction.Web
  alias AntikytheraCore.Handler.GearError

  @default_secure_headers %{
    "x-frame-options" => "DENY",
    "x-xss-protection" => "1; mode=block",
    "x-content-type-options" => "nosniff",
    "strict-transport-security" => "max-age=31536000"
  }

  defun dispatch(
          gear_name :: v[GearName.t()],
          method :: v[Method.t()],
          url :: v[String.t()],
          body :: ReqBody.t(),
          headers :: v[Headers.t()],
          options :: Keyword.t()
        ) :: v[Response.t()] do
    uri = URI.parse(url)
    path_only = uri.path || "/"
    qs = build_qs(uri.query, Keyword.get(options, :params))
    {raw_body, body_headers} = make_raw_body(method, body)

    option_headers =
      %{}
      |> add_cookie_header(Keyword.get(options, :cookie))
      |> add_basic_auth_header(Keyword.get(options, :basic_auth))

    req_headers =
      body_headers
      |> Map.merge(option_headers)
      |> Map.merge(downcase_keys(headers))

    # Produce decoded path segments the same way cowboy's router does.
    # CowboyReq.path_info/1 will append "" for trailing slash, so we must not include it here.
    decoded_path_info =
      String.split(path_only, "/")
      |> tl()
      |> Enum.map(&URI.decode_www_form/1)
      |> strip_trailing_empty()

    fake_req = %{
      method: method |> Atom.to_string() |> String.upcase(),
      version: :"HTTP/1.1",
      scheme: uri.scheme || "http",
      host: uri.host || "localhost",
      port: uri.port || 80,
      path: path_only,
      path_info: decoded_path_info,
      qs: qs,
      headers: req_headers,
      peer: {{127, 0, 0, 1}, 0},
      sock: {{127, 0, 0, 1}, 0},
      cert: :undefined,
      ref: :fake_listener,
      pid: self(),
      streamid: 1,
      has_body: raw_body != "",
      body_length: byte_size(raw_body)
    }

    conn = Web.handle_in_process(fake_req, gear_name, raw_body)
    build_response(conn)
  end

  # ---------------------------------------------------------------------------
  # Raw body construction — only builds bytes + default content-type/length.
  # Parsing happens inside `Web.handle_in_process` via the shared BodyParser.
  # ---------------------------------------------------------------------------

  defunp make_raw_body(method :: v[Method.t()], body :: ReqBody.t()) :: {binary, Headers.t()} do
    if method in [:get, :delete, :head, :options] do
      {"", %{}}
    else
      case body do
        {:json, data} ->
          raw = Poison.encode!(data)
          {raw, content_headers(raw, "application/json")}

        {:form, params} ->
          binary_params = Enum.map(params, fn {k, v} -> {to_string(k), to_string(v)} end)
          raw = :cow_qs.qs(binary_params)
          {raw, content_headers(raw, "application/x-www-form-urlencoded")}

        body when is_binary(body) and byte_size(body) > 0 ->
          {body, %{"content-length" => byte_size(body) |> Integer.to_string()}}

        body when is_binary(body) ->
          {"", %{}}

        body when is_map(body) or is_list(body) ->
          raw = Poison.encode!(body)
          {raw, content_headers(raw, "application/json")}
      end
    end
  end

  defunp content_headers(raw :: v[binary], content_type :: v[String.t()]) :: v[Headers.t()] do
    %{
      "content-type" => content_type,
      "content-length" => byte_size(raw) |> Integer.to_string()
    }
  end

  # ---------------------------------------------------------------------------
  # Response transform — mirror `AntikytheraCore.Conn.reply_as_cowboy_res`
  # header handling (lowercased names, default secure headers, accurate
  # content-length) so callers see a response equivalent to an HTTP round trip.
  # ---------------------------------------------------------------------------

  defunp build_response(conn :: Antikythera.Conn.t()) :: v[Response.t()] do
    try do
      body = conn.resp_body

      if not is_binary(body) do
        raise "unexpected `resp_body` returned by controller action"
      end

      downcased = Map.new(conn.resp_headers, fn {k, v} -> {String.downcase(k), v} end)

      headers =
        @default_secure_headers
        |> Map.merge(Map.delete(downcased, "content-length"))
        |> Map.put("content-length", byte_size(body) |> Integer.to_string())

      Response.new!(
        status: conn.status,
        body: body,
        headers: headers,
        cookies: url_encode_cookies(conn.resp_cookies)
      )
    rescue
      e ->
        # Mirror `CoreConn.reply_as_cowboy_res` fallback: invalid conn fields -> invoke
        # gear error handler and recompute the response.
        st = __STACKTRACE__

        %Antikythera.Conn{conn | resp_body: ""}
        |> GearError.error({:error, e}, st)
        |> build_response()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defunp build_qs(existing_qs :: v[nil | String.t()], extra_params :: Keyword.t() | nil) ::
           v[String.t()] do
    parts = [existing_qs, if(extra_params, do: URI.encode_query(extra_params))]
    parts |> Enum.reject(&is_nil/1) |> Enum.join("&")
  end

  defunp downcase_keys(map :: v[Headers.t()]) :: v[Headers.t()] do
    Map.new(map, fn {k, v} -> {String.downcase(k), v} end)
  end

  # Match `Httpc`'s `:cookie` option handling (URL-encoded name=value joined by "; ").
  defp add_cookie_header(headers, nil), do: headers
  defp add_cookie_header(headers, []), do: headers

  defp add_cookie_header(headers, cookies) do
    value =
      Enum.map_join(cookies, "; ", fn {name, val} ->
        "#{URI.encode_www_form(to_string(name))}=#{URI.encode_www_form(to_string(val))}"
      end)

    Map.put(headers, "cookie", value)
  end

  # Match `Httpc`'s `:basic_auth` option (adds an `Authorization: Basic ...` header).
  defp add_basic_auth_header(headers, nil), do: headers

  defp add_basic_auth_header(headers, {user, pass}) do
    encoded = Base.encode64("#{user}:#{pass}")
    Map.put(headers, "authorization", "Basic #{encoded}")
  end

  defunp strip_trailing_empty(segments :: v[list]) :: v[list] do
    case List.last(segments) do
      "" -> List.delete_at(segments, -1)
      _ -> segments
    end
  end

  # Mirror the URL-encoding that `CoreCookies.merge_cookies_to_cowboy_req` applies
  # to outbound `Set-Cookie` headers, so that cookie names/values round-tripped
  # through `response_to_request_cookie` don't contain forbidden characters.
  defp url_encode_cookies(cookies) do
    Map.new(cookies, fn {name, %SetCookie{value: value} = cookie} ->
      encoded_name = URI.encode_www_form(name)
      {encoded_name, %SetCookie{cookie | value: URI.encode_www_form(value)}}
    end)
  end
end
