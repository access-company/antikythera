# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.Web do
  alias Croma.Result, as: R
  alias Antikythera.{GearName, PathInfo, Conn, GearActionTimeout, VersionStr}
  alias Antikythera.Http.{Method, QueryParams, Body}
  alias Antikythera.Request.PathMatches
  alias Antikythera.Context.GearEntryPoint
  alias AntikytheraCore.Handler.GearAction
  alias AntikytheraCore.Handler.GearError
  alias AntikytheraCore.Handler.HelperModules
  alias AntikytheraCore.Handler.CowboyReq
  alias AntikytheraCore.Handler.ExecutorPoolHelper
  alias AntikytheraCore.Handler.WebsocketState
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.GearModule
  alias AntikytheraCore.ExecutorPool.ActionRunner
  alias AntikytheraCore.GearLog.ContextHelper

  # This line results in "conflicting behaviours - callback init/2 required by both 'cowboy_websocket' and 'cowboy_handler'"
  # @behaviour :cowboy_handler
  @behaviour :cowboy_websocket

  @type http_reply :: {:ok, :cowboy_req.req(), nil}
  @type ws_upgrade :: {:cowboy_websocket, :cowboy_req.req(), Conn.t(), timeout}

  # (Should we make this a mix config item?)
  max_frame_size = 5_000_000
  @ws_upgrade_options %{idle_timeout: 60_000, compress: true, max_frame_size: max_frame_size}

  @impl true
  defun init(req1 :: :cowboy_req.req(), gear_name :: v[GearName.t()]) :: http_reply | ws_upgrade do
    R.m do
      method <- CowboyReq.method(req1)
      path_info = CowboyReq.path_info(req1)
      helper_modules = GearModule.request_helper_modules(gear_name)

      {entry_point, path_matches, ws?, http_streaming?, timeout} <-
        find_route(req1, gear_name, method, path_info, helper_modules)

      routing_info = {gear_name, entry_point, method, path_info, path_matches}
      qparams <- CowboyReq.query_params(req1, routing_info)

      {req2, body_pair} <-
        CowboyReq.request_body_pair(req1, routing_info, qparams, helper_modules)

      pure(
        run_action_with_conn(
          req2,
          routing_info,
          qparams,
          body_pair,
          helper_modules,
          ws?,
          http_streaming?,
          timeout
        )
      )
    end
    |> case do
      # protocol upgrade to websocket
      {:ok, {req3, state}} -> {:cowboy_websocket, req3, state, @ws_upgrade_options}
      # normal response
      {:ok, req_reply} -> {:ok, req_reply, nil}
      # error response
      {:error, req_reply} -> {:ok, req_reply, nil}
    end
  end

  defunp find_route(
           req :: :cowboy_req.req(),
           gear_name :: v[GearName.t()],
           method :: v[Method.t()],
           path_info :: v[PathInfo.t()],
           %HelperModules{router: router}
         ) :: R.t({GearEntryPoint.t(), PathMatches.t(), boolean, boolean, GearActionTimeout.t()}) do
    case router.__web_route__(method, path_info) do
      # New format (6-tuple) with http_streaming flag
      {controller, action, path_matches, websocket?, http_streaming?, timeout} ->
        {:ok, {{controller, action}, path_matches, websocket?, http_streaming?, timeout}}

      # Old format (5-tuple) without http_streaming flag - for backward compatibility
      {controller, action, path_matches, websocket?, timeout} ->
        {:ok, {{controller, action}, path_matches, websocket?, false, timeout}}

      nil ->
        {:error,
         CowboyReq.with_conn(
           req,
           {gear_name, nil, method, path_info, %{}},
           %{},
           fn conn, _context -> GearError.no_route(conn) end
         )}
    end
  end

  defunp run_action_with_conn(
           req :: :cowboy_req.req(),
           routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()],
           websocket? :: v[boolean],
           http_streaming? :: v[boolean],
           timeout :: v[GearActionTimeout.t()]
         ) :: :cowboy_req.req() | {:cowboy_req.req(), WebsocketState.t()} do
    cond do
      websocket? ->
        run_action_with_conn_ws(req, routing_info, qparams, body_pair, helper_modules, timeout)

      http_streaming? ->
        run_action_with_conn_http_streaming(
          req,
          routing_info,
          qparams,
          body_pair,
          helper_modules,
          timeout
        )

      true ->
        run_action_with_conn_http(req, routing_info, qparams, body_pair, helper_modules, timeout)
    end
  end

  defunp run_action_with_conn_http(
           req :: :cowboy_req.req(),
           {gear_name, entry_point, _, _, _} = routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()],
           timeout :: v[GearActionTimeout.t()]
         ) :: :cowboy_req.req() do
    CowboyReq.with_conn(req, routing_info, qparams, body_pair, fn conn, context ->
      GearAction.with_logging_and_metrics_reporting(conn, context, helper_modules, fn ->
        run_action_with_executor(conn, gear_name, entry_point, helper_modules, timeout)
      end)
    end)
  end

  defunp run_action_with_conn_http_streaming(
           req :: :cowboy_req.req(),
           {gear_name, entry_point, _, _, _} = routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()],
           timeout :: v[GearActionTimeout.t()]
         ) :: :cowboy_req.req() do
    :cowboy_req.cast({:set_options, %{idle_timeout: :infinity}}, req)
    context = GearAction.Context.make()
    conn1 = CoreConn.make_from_cowboy_req(req, routing_info, qparams, body_pair)
    ContextHelper.set(conn1)

    # Capture initial versions to detect module updates
    initial_core_version =
      AntikytheraCore.Version.current_version(Antikythera.Env.antikythera_instance_name())

    initial_gear_version = AntikytheraCore.Version.current_version(gear_name)

    # For HTTP streaming, we call the gear callback in an infinite loop until end_chunked is called
    final_conn =
      GearAction.with_logging_and_metrics_reporting(conn1, context, helper_modules, fn ->
        http_streaming_infinite_loop(
          conn1,
          gear_name,
          entry_point,
          helper_modules,
          timeout,
          req,
          nil,
          initial_core_version,
          initial_gear_version
        )
      end)

    # Send final chunk to close the stream if req2 exists (meaning stream was started)
    case Map.get(final_conn.chunked, :cowboy_req) do
      nil -> CoreConn.reply_as_cowboy_res(final_conn, req)
      req2 -> :cowboy_req.stream_body("", :fin, req2)
    end
  end

  defunp http_streaming_infinite_loop(
           conn :: v[Conn.t()],
           gear_name :: v[GearName.t()],
           entry_point :: v[GearEntryPoint.t()],
           helper_modules :: v[HelperModules.t()],
           timeout :: v[GearActionTimeout.t()],
           req :: :cowboy_req.req(),
           req2 :: nil | :cowboy_req.req(),
           initial_core_version :: nil | VersionStr.t(),
           initial_gear_version :: nil | VersionStr.t()
         ) :: Conn.t() do
    conn_after_action =
      run_action_with_executor_for_http_streaming(
        conn,
        gear_name,
        entry_point,
        helper_modules,
        timeout
      )

    # Initialize streaming on first iteration if chunked is enabled
    req2_updated =
      if req2 == nil and Map.get(conn_after_action.chunked, :enabled) do
        # Prepare headers (lowercase and add defaults)
        headers_downcased =
          Map.new(conn_after_action.resp_headers, fn {key, value} ->
            {String.downcase(key), value}
          end)

        headers_without_cl = Map.delete(headers_downcased, "content-length")

        headers_with_defaults =
          Map.merge(
            %{
              "x-frame-options" => "DENY",
              "x-xss-protection" => "1; mode=block",
              "x-content-type-options" => "nosniff",
              "strict-transport-security" => "max-age=31536000"
            },
            headers_without_cl
          )

        :cowboy_req.stream_reply(conn_after_action.status, headers_with_defaults, req)
      else
        req2
      end

    # Send any accumulated chunks immediately
    if req2_updated != nil do
      chunks = Map.get(conn_after_action.chunked, :chunks, [])

      Enum.each(Enum.reverse(chunks), fn chunk_body ->
        :cowboy_req.stream_body(chunk_body, :nofin, req2_updated)
      end)
    end

    # Clear chunks after sending and store the cowboy_req for final close
    conn_cleared =
      %Conn{
        conn_after_action
        | chunked:
            conn_after_action.chunked
            |> Map.put(:chunks, [])
            |> Map.put(:cowboy_req, req2_updated)
      }

    # Check if end_chunked was called
    case Map.get(conn_cleared.chunked, :finished) do
      true ->
        conn_cleared

      _ ->
        # Check for module updates after action runs and before continuing loop
        current_core_version =
          AntikytheraCore.Version.current_version(Antikythera.Env.antikythera_instance_name())

        current_gear_version = AntikytheraCore.Version.current_version(gear_name)

        version_changed? =
          current_core_version != initial_core_version or
            current_gear_version != initial_gear_version

        if version_changed? do
          message =
            "Stopping HTTP streaming loop due to module update (core: #{initial_core_version} -> #{current_core_version}, gear: #{initial_gear_version} -> #{current_gear_version})"

          AntikytheraCore.GearLog.Writer.info(
            AntikytheraCore.GearModule.logger(gear_name),
            AntikytheraCore.GearLog.Time.now(),
            conn_cleared.context.context_id,
            message
          )

          conn_cleared
        else
          http_streaming_infinite_loop(
            conn_cleared,
            gear_name,
            entry_point,
            helper_modules,
            timeout,
            req,
            req2_updated,
            initial_core_version,
            initial_gear_version
          )
        end
    end
  end

  defunp run_action_with_conn_ws(
           req :: :cowboy_req.req(),
           {gear_name, entry_point, _, _, _} = routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()],
           timeout :: v[GearActionTimeout.t()]
         ) :: :cowboy_req.req() | {:cowboy_req.req(), WebsocketState.t()} do
    context = GearAction.Context.make()
    conn1 = CoreConn.make_from_cowboy_req(req, routing_info, qparams, body_pair)
    ContextHelper.set(conn1)

    GearAction.with_logging_and_metrics_reporting(conn1, context, helper_modules, fn ->
      case run_action_with_executor(conn1, gear_name, entry_point, helper_modules, timeout) do
        # Fill the status code with "101 Upgrade" in order to correctly report response metrics
        conn2 = %Conn{status: nil} -> %Conn{conn2 | status: 101}
        conn2 -> conn2
      end
    end)
    |> case do
      %Conn{status: 101} = conn3 ->
        ExecutorPoolHelper.increment_ws_count(
          conn3,
          context.start_time_for_log,
          req,
          helper_modules,
          fn ->
            {req,
             WebsocketState.make(conn3, context.start_time_for_log, entry_point, helper_modules)}
          end
        )

      conn3 ->
        CoreConn.reply_as_cowboy_res(conn3, req)
    end
  end

  defunp run_action_with_executor(
           conn1 :: v[Conn.t()],
           gear_name :: v[GearName.t()],
           entry_point :: v[GearEntryPoint.t()],
           helper_modules :: v[HelperModules.t()],
           timeout :: v[GearActionTimeout.t()]
         ) :: Conn.t() do
    ExecutorPoolHelper.with_executor(conn1, gear_name, helper_modules, fn pid, conn2 ->
      ActionRunner.run(pid, conn2, entry_point, timeout)
    end)
  end

  defunp run_action_with_executor_for_http_streaming(
           conn1 :: v[Conn.t()],
           gear_name :: v[GearName.t()],
           entry_point :: v[GearEntryPoint.t()],
           helper_modules :: v[HelperModules.t()],
           _timeout :: v[GearActionTimeout.t()]
         ) :: Conn.t() do
    ExecutorPoolHelper.with_executor_for_http_streaming(conn1, gear_name, helper_modules, fn pid,
                                                                                             conn2 ->
      ActionRunner.run(pid, conn2, entry_point, :infinity)
    end)
  end

  #
  # callback implementations for cowboy_websocket
  #
  @impl true
  defun websocket_init(ws_state :: v[WebsocketState.t()]) :: WebsocketState.callback_result() do
    WebsocketState.init(ws_state)
  end

  @impl true
  defun websocket_handle(frame :: :cow_ws.frame(), ws_state :: v[WebsocketState.t()]) ::
          WebsocketState.callback_result() do
    case frame do
      :ping -> {:ok, ws_state}
      :pong -> {:ok, ws_state}
      {ping_or_pong, _payload} when ping_or_pong in [:ping, :pong] -> {:ok, ws_state}
      _ -> WebsocketState.handle_client_message(ws_state, frame)
    end
  end

  @impl true
  defun websocket_info(message :: any, ws_state :: v[WebsocketState.t()]) ::
          WebsocketState.callback_result() do
    case message do
      {:EXIT, _, _} ->
        # In rare conditions, websocket connection process receives an EXIT message
        # about death of the original handler (i.e. the process that executed the `init/2` callback).
        # Just neglect the message.
        {:ok, ws_state}

      {:antikythera_internal, :close} ->
        close_frame = {:close, 1001, "server shutting down; please reconnect"}
        {:reply, [close_frame], ws_state}

      _ ->
        WebsocketState.handle_server_message(ws_state, message)
    end
  end

  @impl true
  def terminate(reason, _maybe_req, %WebsocketState{} = ws_state) do
    WebsocketState.terminate(ws_state, reason)
  end

  def terminate(_reason, _maybe_req, _state) do
    # normal HTTP request, do nothing
    :ok
  end
end
