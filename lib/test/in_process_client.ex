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
  alias Antikythera.Http.{Method, Headers, Body}
  alias Antikythera.Httpc.{Response, ReqBody}
  alias Antikythera.Http.SetCookie
  alias AntikytheraCore.Handler.GearAction
  alias AntikytheraCore.Handler.GearAction.Web

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
    path_info = GearAction.split_path_to_segments(path_only)
    {body_pair, body_headers} = make_body_pair(method, body)
    req_headers = Map.merge(body_headers, downcase_keys(headers))

    raw_body = elem(body_pair, 0)
    pid = self()
    streamid = 1

    fake_req = %{
      method: method |> Atom.to_string() |> String.upcase(),
      version: :"HTTP/1.1",
      scheme: uri.scheme || "http",
      host: uri.host || "localhost",
      port: uri.port || 80,
      path: path_only,
      qs: qs,
      headers: req_headers,
      peer: {{127, 0, 0, 1}, 0},
      sock: {{127, 0, 0, 1}, 0},
      cert: :undefined,
      ref: :fake_listener,
      pid: pid,
      streamid: streamid,
      has_body: raw_body != "",
      body_length: byte_size(raw_body),
      path_info: path_info,
      __body_pair__: body_pair
    }

    try do
      Process.put(:antikythera_in_process_test, true)
      Web.init(fake_req, gear_name)

      # :cowboy_req.reply sends {response, Status, Headers, Body} via cast to pid
      receive do
        {{^pid, ^streamid}, {:response, status, headers, body}} ->
          make_response(status, headers, body)
      after
        0 -> raise "no response from Web.init"
      end
    after
      Process.delete(:antikythera_in_process_test)
    end
  end

  # ---------------------------------------------------------------------------
  # Body pair construction — mirrors BodyParser.parse / parse_raw_body
  # ---------------------------------------------------------------------------

  defunp make_body_pair(method :: v[Method.t()], body :: ReqBody.t()) ::
           {{binary, Body.t()}, Headers.t()} do
    if method in [:get, :delete, :head, :options] do
      {{"", ""}, %{}}
    else
      case body do
        {:json, map} -> encode_json(map)
        {:form, params} -> encode_form(params)
        body when is_binary(body) and byte_size(body) > 0 -> encode_raw(body)
        body when is_binary(body) -> {{"", ""}, %{}}
        body when is_map(body) or is_list(body) -> encode_json(body)
      end
    end
  end

  defunp encode_json(data :: map | list) :: {{binary, Body.t()}, Headers.t()} do
    raw = Poison.encode!(data)
    parsed = Poison.decode!(raw)
    with_content_type(raw, parsed, "application/json")
  end

  defunp encode_form(params :: [{term, term}]) :: {{binary, Body.t()}, Headers.t()} do
    binary_params = Enum.map(params, fn {k, v} -> {to_string(k), to_string(v)} end)
    raw = :cow_qs.qs(binary_params)
    parsed = :cow_qs.parse_qs(raw) |> Map.new()
    with_content_type(raw, parsed, "application/x-www-form-urlencoded")
  end

  defunp encode_raw(raw :: v[binary]) :: {{binary, Body.t()}, Headers.t()} do
    {{raw, raw}, %{"content-length" => byte_size(raw) |> Integer.to_string()}}
  end

  defunp with_content_type(raw :: v[binary], parsed :: Body.t(), content_type :: v[String.t()]) ::
           {{binary, Body.t()}, Headers.t()} do
    len = byte_size(raw) |> Integer.to_string()
    {{raw, parsed}, %{"content-type" => content_type, "content-length" => len}}
  end

  # ---------------------------------------------------------------------------
  # Response construction from cowboy cast message
  # ---------------------------------------------------------------------------

  defunp make_response(status :: v[non_neg_integer], headers :: v[map], body :: v[binary]) ::
           v[Response.t()] do
    {cookie_values, rest_headers} = Map.pop(headers, "set-cookie", [])
    cookies = Map.new(List.wrap(cookie_values), &SetCookie.parse!/1)
    %Response{status: status, body: body, headers: rest_headers, cookies: cookies}
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
end
