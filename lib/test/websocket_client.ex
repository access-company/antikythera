# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.WebsocketClient do
  @moduledoc """
  Websocket client for gear tests.

  Prepare your client module with:

      defmodule YourGear.Socket do
        use Antikythera.Test.WebsocketClient
      end

  Then, call `YourGear.Socket.spawn_link("/ws")` to open Websocket connection at "ws(s)://<host_name>/ws" endpoint.
  It will return pid of Websocket connection handling process if successful.

  By default, it connects to the server specified by `Antikythera.Test.Config.base_url/0`,
  and redirects received frame to the caller (test running) process, in `{frame, handler_pid}` form.

  These default behavior can be overridable with two overridable functions:

  - `base_url/0`
  - `handle_received_frame/2`
  """

  defmacro __using__(_) do
    quote do
      @behaviour :websocket_client

      @default_base_url Antikythera.Test.Config.base_url()
                        |> String.replace_prefix("http://", "ws://")
                        |> String.replace_prefix("https://", "wss://")

      def spawn_link(path, timeout \\ 5_000) do
        url = String.to_charlist(base_url() <> path)
        {:ok, pid} = :websocket_client.start_link(url, __MODULE__, [self()])

        receive do
          :connected -> pid
          :disconnected -> raise "failed to establish websocket connection: disconnected"
        after
          timeout -> raise "failed to establish websocket connection: timeout"
        end
      end

      def send_frame(pid, frame) do
        :websocket_client.cast(pid, frame)
      end

      def send_json(pid, m) do
        send_frame(pid, {:text, Poison.encode!(m)})
      end

      #
      # callback implementations
      #
      @impl true
      def init([pid]) do
        {:once, %{caller: pid}}
      end

      @impl true
      def onconnect(_wsreq, %{caller: pid} = state) do
        send(pid, :connected)
        {:ok, state}
      end

      @impl true
      def ondisconnect(_reason, %{caller: pid} = state) do
        send(pid, :disconnected)
        {:close, :normal, state}
      end

      @impl true
      def websocket_handle(frame, _conn, %{caller: pid} = state) do
        handle_received_frame(frame, pid)
        {:ok, state}
      end

      # Workaround for ondisconnect/2 not being called in 1.5.0
      # See https://github.com/sanmiguel/websocket_client/pull/78
      @impl true
      def websocket_info({:tcp_closed, _pid}, _conn, %{caller: pid} = state) do
        send(pid, :disconnected)
        {:close, "", state}
      end

      # Workaround for ondisconnect/2 not being called in 1.5.0
      @impl true
      def websocket_info({:ssl_closed, _pid}, _conn, %{caller: pid} = state) do
        send(pid, :disconnected)
        {:close, "", state}
      end

      @impl true
      def websocket_info(_msg, _conn, state) do
        {:ok, state}
      end

      @impl true
      def websocket_terminate(_reason, _conn, _state) do
        :ok
      end

      #
      # user overridables
      #
      def base_url(), do: @default_base_url

      def handle_received_frame(frame, caller_pid), do: send(caller_pid, {frame, self()})

      defoverridable base_url: 0, handle_received_frame: 2
    end
  end
end
