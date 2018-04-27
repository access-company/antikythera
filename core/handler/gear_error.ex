# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearError do
  alias SolomonLib.{Conn, Request, Http.Method, ErrorReason}
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.GearModule

  @typep reason     :: ErrorReason.gear_action_error_reason
  @typep stacktrace :: ErrorReason.stacktrace

  defun error(conn :: v[Conn.t], reason :: reason, stacktrace :: stacktrace) :: Conn.t do
    output_error_to_log(conn, reason, stacktrace)
    case CoreConn.gear_name(conn) |> GearModule.error_handler() do
      nil -> %Conn{conn | status: 500, resp_body: internal_error_body(conn, reason, stacktrace)}
      mod -> mod.error(conn, reason)
    end
  end

  defun no_route(conn :: v[Conn.t]) :: Conn.t do
    case CoreConn.gear_name(conn) |> GearModule.error_handler() do
      nil -> %Conn{conn | status: 400, resp_body: "NoRouteFound"}
      mod -> mod.no_route(conn)
    end
  end

  defun bad_request(conn :: v[Conn.t]) :: Conn.t do
    case CoreConn.gear_name(conn) |> GearModule.error_handler() do
      nil -> %Conn{conn | status: 400, resp_body: "BadRequest"}
      mod -> mod.bad_request(conn)
    end
  end

  defun ws_too_many_connections(conn :: v[Conn.t]) :: Conn.t do
    case CoreConn.gear_name(conn) |> GearModule.error_handler() do
      nil -> %Conn{conn | status: 503, resp_body: "TooManyWebsocketConnections"}
      mod ->
        try do
          mod.ws_too_many_connections(conn)
        rescue
          UndefinedFunctionError -> %Conn{conn | status: 503, resp_body: "TooManyWebsocketConnections"}
        end
    end
  end

  defunp output_error_to_log(%Conn{request: request} = conn, reason :: reason, stacktrace :: stacktrace) :: :ok do
    %Request{method: method, path_info: path_info} = request
    path = "/" <> Enum.join(path_info, "/")
    gear_logger_module = CoreConn.gear_name(conn) |> GearModule.logger()
    log_message = "#{Method.to_string(method)} #{path} #{ErrorReason.format(reason, stacktrace)}"
    gear_logger_module.error(log_message)
  end

  if Application.fetch_env!(:solomon, :return_detailed_info_on_error?) do
    defun internal_error_body(conn :: Conn.t, reason :: reason, stacktrace :: stacktrace) :: String.t do
      [
        "InternalError",
        "",
        "Error reason: #{inspect(reason)}",
        "",
        "Conn:",
        inspect(conn, pretty: true),
        "",
        "Stacktrace (list of {module, function, arity, location}):",
        "[",
        Enum.map(stacktrace, fn s -> "  #{inspect(s)}" end) |> Enum.join("\n"),
        "]",
      ] |> Enum.join("\n")
    end
  else
    defun internal_error_body(_conn :: Conn.t, _reason :: reason, _stacktrace :: stacktrace) :: String.t do
      "InternalError"
    end
  end
end
