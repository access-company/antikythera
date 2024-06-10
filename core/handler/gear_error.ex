# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearError do
  alias Antikythera.{Conn, Request, Http.Method, ErrorReason, GearName}
  alias Antikythera.ExecutorPool.BadIdReason
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.GearModule

  @typep reason :: ErrorReason.gear_action_error_reason()
  @typep stacktrace :: ErrorReason.stacktrace()

  defun error(conn :: v[Conn.t()], reason :: reason, stacktrace :: stacktrace) :: Conn.t() do
    output_error_to_log(conn, reason, stacktrace)

    invoke_error_handler(
      conn,
      fn mod -> mod.error(conn, reason) end,
      fn ->
        %Conn{conn | status: 500, resp_body: internal_error_body(conn, reason, stacktrace)}
      end
    )
  end

  defun no_route(conn :: v[Conn.t()]) :: Conn.t() do
    invoke_error_handler(
      conn,
      fn mod -> mod.no_route(conn) end,
      fn -> %Conn{conn | status: 400, resp_body: "NoRouteFound"} end
    )
  end

  defun bad_request(conn :: v[Conn.t()]) :: Conn.t() do
    invoke_error_handler(
      conn,
      fn mod -> mod.bad_request(conn) end,
      fn -> %Conn{conn | status: 400, resp_body: "BadRequest"} end
    )
  end

  defun bad_executor_pool_id(conn :: v[Conn.t()], reason :: v[BadIdReason.t()]) :: Conn.t() do
    invoke_error_handler(
      conn,
      fn mod -> mod.bad_executor_pool_id(conn, reason) end,
      fn -> %Conn{conn | status: 404, resp_body: "InvalidExecutorPoolId"} end
    )
  end

  defun ws_too_many_connections(conn :: v[Conn.t()]) :: Conn.t() do
    invoke_error_handler(
      conn,
      fn mod -> mod.ws_too_many_connections(conn) end,
      fn -> %Conn{conn | status: 503, resp_body: "TooManyWebsocketConnections"} end
    )
  end

  defun parameter_validation_error(
          conn :: v[Conn.t()],
          parameter_type :: Antikythera.Plug.ParamsValidator.parameter_type_t(),
          reason :: Antikythera.BaseParamStruct.validate_error_t()
        ) :: Conn.t() do
    invoke_error_handler(
      conn,
      fn mod -> mod.parameter_validation_error(conn, parameter_type, reason) end,
      fn ->
        resp_body = create_default_parameter_validation_error_message(parameter_type, reason)
        %Conn{conn | status: 400, resp_body: resp_body}
      end
    )
  end

  defunp create_default_parameter_validation_error_message(
           parameter_type :: Antikythera.Plug.ParamsValidator.parameter_type_t(),
           {error_reason, mods} :: Antikythera.BaseParamStruct.validate_error_t()
         ) :: String.t() do
    field_path =
      Enum.flat_map(mods, fn
        {_mod, field_name} -> [field_name]
        _mod -> []
      end)
      |> Enum.join(".")

    error_reason_message =
      Atom.to_string(error_reason) |> String.capitalize() |> String.replace("_", " ")

    "ParameterValidationError: #{error_reason_message}#{if field_path != "", do: " at #{field_path}"} of #{parameter_type}"
  end

  defunp invoke_error_handler(
           conn :: v[Conn.t()],
           invoke_fn :: (module -> Conn.t()),
           default_fn :: (() -> Conn.t())
         ) :: Conn.t() do
    case CoreConn.gear_name(conn) |> GearModule.error_handler() do
      nil ->
        default_fn.()

      mod ->
        try do
          invoke_fn.(mod)
        rescue
          _ ->
            # The raised exception can be an `UndefinedFunctionError` in case of optional handler functions;
            # otherwise it can be an arbitrary exception due to bugs in handler implementations.
            # Anyway we fallback to `default_fn`.
            default_fn.()
        end
    end
  end

  defunp output_error_to_log(
           %Conn{request: request} = conn,
           reason :: reason,
           stacktrace :: stacktrace
         ) :: :ok do
    %Request{method: method, path_info: path_info} = request
    path = "/" <> Enum.join(path_info, "/")
    gear_name = CoreConn.gear_name(conn)
    log_message = "#{Method.to_string(method)} #{path} #{ErrorReason.format(reason, stacktrace)}"

    do_output_error_to_log(gear_name, log_message, reason)
  end

  if Antikythera.Env.compile_env() == :undefined do
    alias AntikytheraCore.GearLog.Writer, warn: false

    defunp do_output_error_to_log(
             gear_name :: v[GearName.t()],
             log_message :: v[String.t()],
             reason :: reason
           ) :: :ok do
      gear_logger_module = gear_name |> GearModule.logger()

      case reason do
        {:error, %ExUnit.AssertionError{}} ->
          :ok = Writer.set_write_to_terminal(gear_name, true)
          gear_logger_module.error(log_message)
          :ok = Writer.restore_write_to_terminal(gear_name)

        _ ->
          gear_logger_module.error(log_message)
      end
    end
  else
    defunp do_output_error_to_log(
             gear_name :: v[GearName.t()],
             log_message :: v[String.t()],
             _reason :: reason
           ) :: :ok do
      gear_logger_module = gear_name |> GearModule.logger()
      gear_logger_module.error(log_message)
    end
  end

  if Application.compile_env!(:antikythera, :return_detailed_info_on_error?) do
    defun internal_error_body(conn :: Conn.t(), reason :: reason, stacktrace :: stacktrace) ::
            String.t() do
      [
        "InternalError",
        "",
        "Error reason: #{inspect(reason, structs: false)}",
        "",
        "Conn:",
        inspect(conn, pretty: true, structs: false),
        "",
        "Stacktrace (list of {module, function, arity, location}):",
        "[",
        Enum.map_join(stacktrace, "\n", fn s -> "  #{inspect(s, structs: false)}" end),
        "]"
      ]
      |> Enum.join("\n")
    end
  else
    defun internal_error_body(_conn :: Conn.t(), _reason :: reason, _stacktrace :: stacktrace) ::
            String.t() do
      "InternalError"
    end
  end
end
