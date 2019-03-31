# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Plug.BasicAuthentication do
  @moduledoc """
  Plug to restrict access to controller action by basic authentication.

  ## Usage

  ### Static username/password: using gear config

  The following line installs a plug that checks username/password in incoming requests against
  `"BASIC_AUTHENTICATION_ID"` and `"BASIC_AUTHENTICATION_PW"` in your gear's gear config.

      plug Antikythera.Plug.BasicAuthentication, :check_with_config, []

  ### Dynamic username/password: using module-function pair.

  In the following case you can check the username/password pair with arbitrary logic by the specified function.

      plug Antikythera.Plug.BasicAuthentication, :check_with_fun, [mod: YourGear.AuthModule, fun: :function_name]

  The given function (`YourGear.AuthModule.function_name/3` in this case) must have the following type signature:

  - receives (1) a `Antikythera.Conn.t`, (2) username, and (3) password
  - returns (1) `{:ok, Antikythera.Conn.t}` if successfully authenticated, (2) `:error` otherwise
  """

  alias Antikythera.{Conn, Crypto}
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Config.Gear, as: GearConfig

  defun check_with_config(conn :: v[Conn.t], _opts :: any) :: Conn.t do
    %GearConfig{kv: %{"BASIC_AUTHENTICATION_ID" => id, "BASIC_AUTHENTICATION_PW" => pw}} =
      ConfigCache.Gear.read(conn.context.gear_name)
    check_impl(conn, fn(input_id, input_pw) ->
      if Crypto.secure_compare(input_id, id) and Crypto.secure_compare(input_pw, pw) do
        {:ok, conn}
      else
        :error
      end
    end)
  end

  defun check_with_fun(conn :: v[Conn.t], opts :: [{:mod | :fun, atom}]) :: Conn.t do
    m = Keyword.fetch!(opts, :mod)
    f = Keyword.fetch!(opts, :fun)
    check_impl(conn, fn(id, pw) -> apply(m, f, [conn, id, pw]) end)
  end

  defp check_impl(conn1, f) do
    with {id, pw}     <- Conn.get_req_header(conn1, "authorization") |> decode_auth_header(),
         {:ok, conn2} <- f.(id, pw) do
      conn2
    else
      _ -> halt_with_401(conn1)
    end
  end

  defp decode_auth_header("Basic " <> encoded_cred) do
    case Base.decode64(encoded_cred) do
      {:ok, name_and_pass} ->
        case :binary.split(name_and_pass, ":") do
          [n, p] -> {n, p}
          _      -> nil
        end
      :error -> nil
    end
  end
  defp decode_auth_header(_), do: nil

  defp halt_with_401(conn) do
    gear_name = conn.context.gear_name
    Conn.put_resp_header(conn, "www-authenticate", "Basic realm=\"#{gear_name}\"")
    |> Conn.put_status(401)
    |> Conn.put_resp_body("Access denied.")
  end
end
