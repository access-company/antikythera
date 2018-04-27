# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Request do
  alias AntikytheraCore.Cookies, as: CoreCookies

  def make_from_cowboy_req(req, method, path_info, path_matches, qparams, {raw_body, body}) do
    headers = :cowboy_req.headers(req) |> Map.delete("cookie")
    %Antikythera.Request{
      method:       method,
      path_info:    path_info,
      path_matches: path_matches,
      query_params: qparams,
      headers:      headers,
      cookies:      CoreCookies.make_from_cowboy_req(req),
      raw_body:     raw_body,
      body:         body,
      sender:       {:web, sender_ip(req, headers)},
    }
  end

  defp sender_ip(req, headers) do
    case Map.get(headers, "x-forwarded-for") do
      nil ->
        {ip, _port} = :cowboy_req.peer(req)
        :inet.ntoa(ip) |> List.to_string()
      ip_str ->
        # Take the last IP address in "x-forwarded-for" as it is added by reliable component (upstream load balancer).
        String.split(ip_str, ~r/, */) |> List.last()
    end
  end
end
