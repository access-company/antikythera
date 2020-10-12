# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.Web do
  alias Croma.Result, as: R
  alias Antikythera.{GearName, PathInfo, Conn}
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

  # @behaviour :cowboy_handler # This line results in "conflicting behaviours - callback init/2 required by both 'cowboy_websocket' and 'cowboy_handler'"
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

      {entry_point, path_matches, ws?} <-
        find_route(req1, gear_name, method, path_info, helper_modules)

      routing_info = {gear_name, entry_point, method, path_info, path_matches}
      qparams <- CowboyReq.query_params(req1, routing_info)

      {req2, body_pair} <-
        CowboyReq.request_body_pair(req1, routing_info, qparams, helper_modules)

      pure(run_action_with_conn(req2, routing_info, qparams, body_pair, helper_modules, ws?))
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
         ) :: R.t({GearEntryPoint.t(), PathMatches.t(), boolean}) do
    case router.__web_route__(method, path_info) do
      {controller, action, path_matches, websocket?} ->
        {:ok, {{controller, action}, path_matches, websocket?}}

      nil ->
        {:error,
         CowboyReq.with_conn(
           req,
           {gear_name, nil, method, path_info, %{}},
           %{},
           &GearError.no_route/1
         )}
    end
  end

  defunp run_action_with_conn(
           req :: :cowboy_req.req(),
           routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()],
           websocket? :: v[boolean]
         ) :: :cowboy_req.req() | {:cowboy_req.req(), WebsocketState.t()} do
    case websocket? do
      true -> run_action_with_conn_ws(req, routing_info, qparams, body_pair, helper_modules)
      false -> run_action_with_conn_http(req, routing_info, qparams, body_pair, helper_modules)
    end
  end

  defunp run_action_with_conn_http(
           req :: :cowboy_req.req(),
           {gear_name, entry_point, _, _, _} = routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()]
         ) :: :cowboy_req.req() do
    CowboyReq.with_conn(req, routing_info, qparams, body_pair, fn conn ->
      GearAction.with_logging_and_metrics_reporting(conn, helper_modules, fn ->
        run_action_with_executor(conn, gear_name, entry_point, helper_modules)
      end)
    end)
  end

  defunp run_action_with_conn_ws(
           req :: :cowboy_req.req(),
           {gear_name, entry_point, _, _, _} = routing_info :: CowboyReq.routing_info(),
           qparams :: v[QueryParams.t()],
           body_pair :: {binary, Body.t()},
           helper_modules :: v[HelperModules.t()]
         ) :: :cowboy_req.req() | {:cowboy_req.req(), WebsocketState.t()} do
    conn1 = CoreConn.make_from_cowboy_req(req, routing_info, qparams, body_pair)
    ContextHelper.set(conn1)

    GearAction.with_logging_and_metrics_reporting(conn1, helper_modules, fn ->
      case run_action_with_executor(conn1, gear_name, entry_point, helper_modules) do
        # Fill the status code with "101 Upgrade" in order to correctly report response metrics
        conn2 = %Conn{status: nil} -> %Conn{conn2 | status: 101}
        conn2 -> conn2
      end
    end)
    |> case do
      %Conn{status: 101} = conn3 ->
        ExecutorPoolHelper.increment_ws_count(conn3, req, helper_modules, fn ->
          {req, WebsocketState.make(conn3, entry_point, helper_modules)}
        end)

      conn3 ->
        CoreConn.reply_as_cowboy_res(conn3, req)
    end
  end

  defunp run_action_with_executor(
           conn1 :: v[Conn.t()],
           gear_name :: v[GearName.t()],
           entry_point :: v[GearEntryPoint.t()],
           helper_modules :: v[HelperModules.t()]
         ) :: Conn.t() do
    ExecutorPoolHelper.with_executor(conn1, gear_name, helper_modules, fn pid, conn2 ->
      ActionRunner.run(pid, conn2, entry_point)
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
