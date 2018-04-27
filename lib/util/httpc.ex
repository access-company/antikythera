# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Httpc do
  @default_max_body  10 * 1024 * 1024
  @maximum_max_body 100 * 1024 * 1024

  @max_retry_attempts 3

  @moduledoc """
  HTTP client library.

  This is a wrapper around [`hackney`](https://github.com/benoitc/hackney), an HTTP client library.
  `Httpc` supports the following features:

  - gzip-compression is tranparently handled
  - headers are represented by maps instead of lists
  - header names are always lower case
  - TCP connections are automatically re-established when closed by server due to keepalive timeout (see #86169)

  ## Body format

  The `body` argument in `post/4`, `put/4`, `patch/4`, `request/5` takes either:

  - `binary` - Sends raw data
  - `{:form, [{key, value}]}` - Sends key-value data as x-www-form-urlencoded
  - `{:json, map}` - Converts map into JSON and sends as application/json
  - `{:file, path}` - Sends given file contents

  ## Options

  - `:timeout` - Timeout to establish a connection, in milliseconds. Default is `8000`.
  - `:recv_timeout` - Timeout used when receiving a response. Default is `5000`.
  - `:params` - An enumerable of 2-tuples that will be URL-encoded and appended to the URL as query string parameters.
  - `:cookie` - An enumerable of name-value pairs of cookies. `Httpc` automatically URL-encodes the given names/values for you.
  - `:basic_auth` - A pair of `{username, password}` tuple to be used for HTTP basic authentication.
  - `:proxy` - A proxy to be used for the request; it can be a regular URL or a `{host, port}` tuple.
  - `:proxy_auth` - Proxy authentication `{username, password}` tuple.
  - `:ssl` - SSL options supported by the `ssl` erlang module.
  - `:skip_ssl_verification` - Whether to verify server's SSL certificate or not. Defaults to `false`.
    Specify `skip_ssl_verification: true` when accessing insecure server with HTTPS.
  - `:max_body` - Maximum content-length of the response body (compressed size if it's compressed).
    Defaults to `#{@default_max_body}` (#{div(@default_max_body, 1024 * 1024)}MB) and must not exceed #{div(@maximum_max_body, 1024 * 1024)}MB.
    Responses having body larger than the specified size will be rejected with `{:error, :response_too_large}`.
  - `:follow_redirect` - A boolean that causes redirects to be followed. Defaults to `false`.
  - `:max_redirect` - An integer denoting the maximum number of redirects to follow if `follow_redirect: true` is given.
  - `:skip_body_decompression` - By default gzip-compressed body is automatically decompressed (i.e. defaults to `false`).
    Pass `skip_body_decompression: true` if compressed body is what you need.
  """

  alias Croma.Result, as: R
  alias SolomonLib.{MapUtil, Url}
  alias SolomonLib.Http.{Status, Method, Headers, SetCookie, SetCookiesMap}

  defmodule ReqBody do
    @moduledoc """
    Type for `SolomonLib.Httpc`'s request body.
    """

    @type json_obj :: %{(atom | String.t) => any}
    @type t        :: binary | {:form, [{term, term}]} | {:json, json_obj} | {:file, Path.t}

    defun valid?(t :: term) :: boolean do
      b          when is_binary(b) -> true
      {:form, l} when is_list(l)   -> true
      {:json, m} when is_map(m)    -> true
      {:file, b} when is_binary(b) -> true
      _otherwise                   -> false
    end

    def convert_body_and_headers_by_body_type(body, headers) do
      case body do
        {:json, map} ->
          Poison.encode(map)
          |> R.map(fn json ->
            {json, Map.put(headers, "content-type", "application/json")}
          end)
        other_body ->
          # {:form, l} and {:file, b} can be left as-is because hackney handles this internally
          {:ok, {other_body, headers}}
      end
    end
  end

  defmodule Response do
    @moduledoc """
    A struct to represent an HTTP response.

    Response headers are converted to a `SolomonLib.Http.Headers.t` and all header names are lower-cased.
    `set-cookie` response headers are handled separately and stored in `cookies` field as a `SolomonLib.Http.SetCookiesMap.t`.
    """

    use Croma.Struct, recursive_new?: true, fields: [
      status:  Status.Int,
      body:    Croma.Binary,
      headers: Headers,
      cookies: SetCookiesMap,
    ]
  end

  defun request(method :: v[Method.t], url :: v[Url.t], body :: v[ReqBody.t], headers :: v[Headers.t] \\ %{}, options :: Keyword.t \\ []) :: R.t(Response.t) do
    downcased_headers     = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
    headers_with_encoding = Map.put_new(downcased_headers, "accept-encoding", "gzip")
    options_map = normalize_options(options)
    url_with_params =
      case options_map[:params] do
        nil    -> url
        params ->
          uri = URI.parse(url)
          query_string =
            case uri.query do
              nil -> URI.encode_query(params)
              qs  -> qs <> "&" <> URI.encode_query(params)
            end
          %URI{uri | query: query_string} |> URI.to_string()
      end
    hackney_opts = hackney_options(options_map)
    ReqBody.convert_body_and_headers_by_body_type(body, headers_with_encoding)
    |> R.bind(fn {hackney_body, headers} ->
      request_impl(method, url_with_params, headers, hackney_body, hackney_opts, options_map)
    end)
  end
  defun request!(method :: Method.t, url :: Url.t, body :: ReqBody.t, headers :: Headers.t \\ %{}, options :: Keyword.t \\ []) :: Response.t do
    request(method, url, body, headers, options) |> R.get!()
  end

  Enum.each([:get, :delete, :options, :head], fn method ->
    defun unquote(method)(url :: Url.t, headers :: Headers.t \\ %{}, options :: Keyword.t \\ []) :: R.t(Response.t) do
      request(unquote(method), url, "", headers, options)
    end
    defun unquote(:"#{method}!")(url :: Url.t, headers :: Headers.t \\ %{}, options :: Keyword.t \\ []) :: Response.t do
      request!(unquote(method), url, "", headers, options)
    end
  end)

  Enum.each([:post, :put, :patch], fn method ->
    defun unquote(method)(url :: Url.t, body :: ReqBody.t, headers :: Headers.t, options :: Keyword.t \\ []) :: R.t(Response.t) do
      request(unquote(method), url, body, headers, options)
    end
    defun unquote(:"#{method}!")(url :: Url.t, body :: ReqBody.t, headers :: Headers.t, options :: Keyword.t \\ []) :: Response.t do
      request!(unquote(method), url, body, headers, options)
    end
  end)

  defp request_impl(method, url_with_params, headers, body, hackney_opts, options_map) do
    send_request_with_retry(method, url_with_params, Map.to_list(headers), body, hackney_opts, options_map, 0)
  end

  defp send_request_with_retry(method, url, headers_list, body, hackney_opts, options_map, attempts) do
    case send_request(method, url, headers_list, body, hackney_opts, options_map) do
      {:ok, _} = ok     -> ok
      {:error, :closed} -> # connection is closed on server side
        require AntikytheraCore.Logger, as: L
        L.info("{:error, :closed} returned by hackney: attempts=#{attempts} url=#{url}")
        attempts2 = attempts + 1
        if attempts2 < @max_retry_attempts do
          :timer.sleep(10) # Since hackney's socket pool may have not yet cleaned up the closed socket, we should wait for a moment
          send_request_with_retry(method, url, headers_list, body, hackney_opts, options_map, attempts2)
        else
          {:error, :closed}
        end
      {:error, _} = error -> error
    end
  end

  defp send_request(method, url, headers_list, body, hackney_opts, options_map) do
    case :hackney.request(method, url, headers_list, body, hackney_opts) do
      {:ok, resp_status, resp_headers}            -> make_response(resp_status, resp_headers, "", options_map) # HEAD method
      {:ok, resp_status, resp_headers, resp_body} -> make_response(resp_status, resp_headers, resp_body, options_map)
      {:error, reason}                            -> {:error, reason}
    end
  end

  defp make_response(status, headers_list, body1, options_map) do
    if byte_size(body1) <= options_map[:max_body] do
      headers_grouped1 = Enum.group_by(headers_list, fn {k, _} -> String.downcase(k) end, &elem(&1, 1))
      {cookie_strings, headers_grouped2} = Map.pop(headers_grouped1, "set-cookie", [])
      headers_map1 = MapUtil.map_values(headers_grouped2, fn {_, vs} -> Enum.join(vs, ", ") end)
      {body2, headers_map2} =
        if body1 != "" and !options_map[:skip_body_decompression] and headers_map1["content-encoding"] == "gzip" do
          uncompressed    = :zlib.gunzip(body1)
          content_length  = Integer.to_string(byte_size(uncompressed))
          new_headers_map = headers_map1 |> Map.delete("content-encoding") |> Map.put("content-length", content_length)
          {uncompressed, new_headers_map}
        else
          {body1, headers_map1}
        end
      cookies_map = Map.new(cookie_strings, &SetCookie.parse!/1)
      {:ok, %Response{status: status, body: body2, headers: headers_map2, cookies: cookies_map}}
    else
      # The returned body might be truncated and thus we can't reliably uncompress the body if it's compressed.
      # In this case we give up returning partial information and simply return an error.
      {:error, :response_too_large}
    end
  end

  defp normalize_options(options) do
    options_map = Map.new(options)
    case options_map[:max_body] do
      nil                                  -> Map.put(options_map, :max_body, @default_max_body)
      max when max in 0..@maximum_max_body -> options_map
    end
  end

  defp hackney_options(options_map) do
    max_body  = Map.fetch!(options_map, :max_body)
    base_opts = [{:path_encode_fun, &encode_path/1}, {:max_body, max_body}, {:with_body, true}]
    Enum.reduce(options_map, base_opts, fn({k, v}, opts) ->
      case convert_option(k, v) do
        nil -> opts
        opt -> [opt | opts]
      end
    end)
  end

  defunp convert_option(name, value) :: any do
    (:timeout              , value       ) -> {:connect_timeout, value}
    (:recv_timeout         , value       ) -> {:recv_timeout   , value}
    # :params are used in URL, not a hackney option
    (:cookie               , cs          ) -> {:cookie         , Enum.map(cs, fn {n, v} -> {URI.encode_www_form(n), URI.encode_www_form(v)} end)}
    (:basic_auth           , {_u, _p} = t) -> {:basic_auth     , t    }
    (:proxy                , proxy       ) -> {:proxy          , proxy}
    (:proxy_auth           , {_u, _p} = t) -> {:proxy_auth     , t    }
    (:ssl                  , ssl         ) -> {:ssl_options    , ssl  }
    (:skip_ssl_verification, true        ) -> :insecure
    # :max_body is treated differently as it has the default value
    (:follow_redirect      , true        ) -> {:follow_redirect, true }
    (:max_redirect         , max         ) -> {:max_redirect   , max  }
    # :skip_body_decompression is used in processing response body, not here
    (_                     , _           ) -> nil
  end

  defunpt encode_path(path :: String.t) :: String.t do
    encode_path_impl(path, "")
  end

  defp hex(n) when n <= 9, do: n + ?0
  defp hex(n)            , do: n + ?A - 10

  defmacrop is_hex(c) do
    quote do
      unquote(c) in ?0..?9 or unquote(c) in ?A..?F or unquote(c) in ?a..?f
    end
  end

  defunp encode_path_impl(path :: String.t, acc :: String.t) :: String.t do
    ("", acc) ->
      acc
    (<<?%, a :: 8, b :: 8, rest :: binary>>, acc) when is_hex(a) and is_hex(b) ->
      encode_path_impl(rest, <<acc :: binary, ?%, a, b>>)
    (<<c :: 8, rest :: binary>>, acc) ->
      import Bitwise
      case URI.char_unescaped?(c) do
        true  -> encode_path_impl(rest, <<acc :: binary, c>>)
        false -> encode_path_impl(rest, <<acc :: binary, ?%, hex(bsr(c, 4)), hex(band(c, 15))>>)
      end
  end
end

defmodule SolomonLib.Httpc.Mockable do
  @moduledoc """
  Just wrapping `Httpc` without any modification.
  Can be mocked with `:meck.expect(Httpc.Mockable, :request, ...)` without interfering other Httpc action.
  """

  defdelegate request( method, url, body, headers, options), to: SolomonLib.Httpc
  defdelegate request!(method, url, body, headers, options), to: SolomonLib.Httpc
  Enum.each([:get, :delete, :options, :head], fn method ->
    defdelegate unquote(method       )(url, headers, options), to: SolomonLib.Httpc
    defdelegate unquote(:"#{method}!")(url, headers, options), to: SolomonLib.Httpc
  end)
  Enum.each([:post, :put, :patch], fn method ->
    defdelegate unquote(method       )(url, body, headers, options), to: SolomonLib.Httpc
    defdelegate unquote(:"#{method}!")(url, body, headers, options), to: SolomonLib.Httpc
  end)
end
