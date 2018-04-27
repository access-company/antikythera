# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Cookies do
  alias SolomonLib.Http.SetCookie

  def make_from_cowboy_req(req) do
    :cowboy_req.parse_cookies(req)
    |> Map.new(fn {k, v} -> {URI.decode_www_form(k), URI.decode_www_form(v)} end)
  end

  def merge_cookies_to_cowboy_req(cookies, req0) do
    Enum.reduce(cookies, req0, fn({key, %SetCookie{value: value} = cookie}, req) ->
      :cowboy_req.set_resp_cookie(URI.encode_www_form(key), URI.encode_www_form(value), req, convert_to_cowboy_cookie_opts(cookie))
    end)
  end

  defpt convert_to_cowboy_cookie_opts(cookie) do
    Map.from_struct(cookie)
    |> Map.delete(:value)
    |> Enum.reject(&match?({_, nil}, &1))
    |> Map.new()
  end
end
