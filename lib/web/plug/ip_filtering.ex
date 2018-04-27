# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Plug.IpFiltering do
  @moduledoc """
  Plug to restrict access to controller action only from within specified IP ranges.

  ## Usage

  ### Static IP ranges specified as a plug argument

  The following lines reject requests from IP not within the 2 ranges, `"123.45.67.0/24", "135.79.135.0/24"`.

      ranges = Enum.map(["123.45.67.0/24", "135.79.135.0/24"], &SolomonLib.IpAddress.V4.parse!/1)
      plug SolomonLib.Plug.IpFiltering, :check_by_static_ranges, [ranges: ranges]

  Note that this plug accepts only parsed result and not string, in order to avoid parsing the given strings on every request.

  ### Dynamic IP ranges specified by gear config

  The following line uses `"ALLOWED_IP_RANGES"` field in the gear config as the list of allowed IP ranges.

      plug SolomonLib.Plug.IpFiltering, :check_by_gear_config, []

  The field name can be customized by giving `:field_name` option as follows:

      plug SolomonLib.Plug.IpFiltering, :check_by_gear_config, [field_name: "ALLOWED_IP_RANGES_2"]

  ## gear-to-gear requests

  Both plug functions explained above reject not only web requests from outside of the specified IP ranges but also gear-to-gear requests.
  If you want to restrict web requests and at the same time allow gear-to-gear requests, pass `:allow_g2g` option.

      plug SolomonLib.Plug.IpFiltering, :check_by_gear_config, [allow_g2g: true]
  """

  alias SolomonLib.{Conn, Request, Context, IpAddress}
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Config.Gear, as: GearConfig

  @type arg_static :: boolean | [:inet.ip_address]

  defun check_by_static_ranges(conn :: v[Conn.t], opts :: Keyword.t(arg_static)) :: Conn.t do
    allowed_ip_ranges = opts[:ranges]
    run_check_on_cloud(conn, opts, fn -> allowed_ip_ranges end)
  end

  @type arg_gear_config :: boolean | String.t

  defun check_by_gear_config(conn :: v[Conn.t], opts :: Keyword.t(arg_gear_config)) :: Conn.t do
    run_check_on_cloud(conn, opts, fn ->
      field_name = Keyword.get(opts, :field_name, "ALLOWED_IP_RANGES")
      %Conn{context: %Context{gear_name: gear_name}} = conn
      case ConfigCache.Gear.read(gear_name) do
        %GearConfig{kv: kv} -> Map.get(kv, field_name, []) |> Enum.map(&IpAddress.V4.parse_range!/1)
        nil                 -> []
      end
    end)
  end

  if SolomonLib.Env.compiling_for_cloud?() or Mix.env() == :test do
    defun run_check_on_cloud(conn :: v[Conn.t], opts :: Keyword.t, fun :: (() -> [:inet.ip4_address])) :: Conn.t do
      run_check(conn, opts, fun)
    end
  else
    defun run_check_on_cloud(conn :: v[Conn.t], _opts :: Keyword.t, _fun :: (() -> [:inet.ip4_address])) :: Conn.t do
      conn # Do nothing
    end
  end

  # The following should be `defunp` but is made public in order to suppress warning about "unused function"
  # (which then results in "spec for undefined function" error) when not `compiling_for_cloud?`.
  @doc false
  defun run_check(%Conn{request: %Request{sender: sender}} = conn,
                  opts          :: Keyword.t(term),
                  ip_ranges_fun :: (() -> [:inet.ip_address])) :: Conn.t do
    case sender do
      {:web, ip_str} ->
        case IpAddress.V4.parse(ip_str) do
          {:ok, ip} ->
            if Enum.any?(ip_ranges_fun.(), &IpAddress.V4.range_include?(&1, ip)) do
              conn
            else
              reject(conn)
            end
          {:error, _} -> reject(conn)
        end
      {:gear, _} -> if Keyword.get(opts, :allow_g2g, false), do: conn, else: reject(conn)
    end
  end

  defp reject(conn) do
    Conn.put_status(conn, 401) |> Conn.put_resp_body("Access denied.")
  end
end
