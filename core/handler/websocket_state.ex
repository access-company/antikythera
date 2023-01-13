# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.WebsocketState do
  alias Antikythera.{Time, Conn, Context, ErrorReason}
  alias Antikythera.Websocket
  alias Antikythera.Websocket.{Frame, FrameList}
  alias Antikythera.Context.GearEntryPoint
  alias AntikytheraCore.Handler.HelperModules
  alias AntikytheraCore.GearLog.{Writer, ContextHelper}
  alias AntikytheraCore.{MetricsUploader, GearProcess}

  use Croma.Struct,
    recursive_new?: true,
    fields: [
      conn: Conn,
      ws_module: Croma.Atom,
      gear_impl_state: Croma.Any,
      helper_modules: HelperModules,
      frames_received: Croma.NonNegInteger,
      frames_sent: Croma.NonNegInteger,
      error_reason: Croma.TypeGen.nilable(ErrorReason)
    ]

  defun make(
          conn :: v[Conn.t()],
          {ws_module, _action} :: GearEntryPoint.t(),
          helper_modules :: v[HelperModules.t()]
        ) :: t do
    %__MODULE__{
      conn: conn,
      ws_module: ws_module,
      gear_impl_state: nil,
      helper_modules: helper_modules,
      frames_received: 0,
      frames_sent: 0,
      error_reason: nil
    }
  end

  @type callback_result :: {:ok, t} | {:reply, FrameList.t(), t}

  # taken from :cowboy_websocket.terminate_reason/0, which is not exported
  @type cowboy_ws_terminate_reason ::
          :normal
          | :stop
          | :timeout
          | :remote
          | {:remote, :cow_ws.close_code(), binary}
          | {:error, :badencoding | :badframe | :closed | atom}
          | {:crash, :error | :exit | :throw, any}

  defun init(%__MODULE__{conn: conn, ws_module: ws_module} = state) :: callback_result do
    GearProcess.set_max_heap_size()
    ContextHelper.set(conn)
    %Conn{context: %Context{start_time: start_time}} = conn
    log_info(state, start_time, "CONNECTED")
    run_callback_and_reply(state, 0, fn -> ws_module.init(conn) end)
  end

  defun handle_client_message(
          %__MODULE__{conn: conn, ws_module: ws_module, gear_impl_state: gear_impl_state} = state,
          frame :: v[Frame.t()]
        ) :: callback_result do
    run_callback_and_reply(state, 1, fn ->
      ws_module.handle_client_message(gear_impl_state, conn, frame)
    end)
  end

  defun handle_server_message(
          %__MODULE__{conn: conn, ws_module: ws_module, gear_impl_state: gear_impl_state} = state,
          message :: any
        ) :: callback_result do
    run_callback_and_reply(state, 0, fn ->
      ws_module.handle_server_message(gear_impl_state, conn, message)
    end)
  end

  defunp run_callback_and_reply(
           state :: v[t],
           n_received :: v[non_neg_integer],
           f :: (() -> callback_result)
         ) :: callback_result do
    try do
      {:ok, f.()}
    catch
      error_kind, reason -> {{error_kind, reason}, __STACKTRACE__}
    end
    |> case do
      {:ok, {new_gear_impl_state, frames_to_send}} ->
        n_sent = length(frames_to_send)

        new_state =
          increment_frames_count(
            %__MODULE__{state | gear_impl_state: new_gear_impl_state},
            n_received,
            n_sent
          )

        case n_sent do
          0 -> {:ok, new_state}
          _ -> {:reply, frames_to_send, new_state}
        end

      {error_tuple, stacktrace} ->
        log_error(state, Time.now(), ErrorReason.format(error_tuple, stacktrace))
        state_with_error_reason = %__MODULE__{state | error_reason: error_tuple}
        {:reply, [:close], state_with_error_reason}
    end
  end

  defun terminate(
          %__MODULE__{conn: conn, ws_module: ws_module, gear_impl_state: gear_impl_state} = state,
          cowboy_terminate_reason :: cowboy_ws_terminate_reason
        ) :: any do
    now = Time.now()
    reason = terminate_reason(state, cowboy_terminate_reason)
    log_info(state, now, build_disconnected_log_message(state, reason))

    try do
      ws_module.terminate(gear_impl_state, conn, reason)
    catch
      :error, error ->
        log_error(state, now, ErrorReason.format({:error, error}, __STACKTRACE__))

      :throw, value ->
        log_error(state, now, ErrorReason.format({:throw, value}, __STACKTRACE__))

      :exit, reason ->
        log_error(state, now, ErrorReason.format({:error, reason}, __STACKTRACE__))
    end
  end

  defunp terminate_reason(
           %__MODULE__{error_reason: error_reason},
           cowboy_terminate_reason :: cowboy_ws_terminate_reason
         ) :: Websocket.terminate_reason() do
    case error_reason do
      nil ->
        case cowboy_terminate_reason do
          {:crash, _kind, reason} -> {:error, reason}
          other -> other
        end

      {_kind, reason} ->
        {:error, reason}
    end
  end

  defunp build_disconnected_log_message(
           %__MODULE__{
             conn: %Conn{context: %Context{start_time: start_time}},
             frames_received: frames_received,
             frames_sent: frames_sent
           },
           reason :: Websocket.terminate_reason()
         ) :: String.t() do
    "DISCONNECTED connected_at=#{Time.to_iso_timestamp(start_time)} frames_received=#{
      frames_received
    } frames_sent=#{frames_sent} reason=#{inspect(reason)}"
  end

  for level <- [:info, :error] do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    defunp unquote(:"log_#{level}")(
             %__MODULE__{
               conn: %Conn{context: %Context{context_id: context_id}},
               helper_modules: %HelperModules{logger: logger}
             },
             time :: v[Time.t()],
             message :: v[String.t()]
           ) :: :ok do
      Writer.unquote(level)(logger, time, context_id, "<websocket> " <> message)
    end
  end

  defunp increment_frames_count(
           %__MODULE__{frames_received: frames_received, frames_sent: frames_sent} = state,
           n_received :: v[non_neg_integer],
           n_sent :: v[non_neg_integer]
         ) :: t do
    submit_metrics_if_any(state, n_received, n_sent)

    %__MODULE__{
      state
      | frames_received: frames_received + n_received,
        frames_sent: frames_sent + n_sent
    }
  end

  defunp submit_metrics_if_any(
           %__MODULE__{
             conn: %Conn{context: %Context{executor_pool_id: epool_id}},
             helper_modules: %HelperModules{metrics_uploader: uploader}
           },
           n_received :: v[non_neg_integer],
           n_sent :: v[non_neg_integer]
         ) :: :ok do
    case build_metrics(n_received, n_sent) do
      [] -> :ok
      list -> MetricsUploader.submit(uploader, list, epool_id)
    end
  end

  defp build_metrics(0, 0), do: []
  defp build_metrics(0, n_s), do: [{"websocket_frames_sent", :sum, n_s}]
  defp build_metrics(n_r, 0), do: [{"websocket_frames_received", :sum, n_r}]

  defp build_metrics(n_r, n_s),
    do: [{"websocket_frames_received", :sum, n_r}, {"websocket_frames_sent", :sum, n_s}]
end
