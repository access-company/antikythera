# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Websocket do
  @moduledoc """
  Behaviour module for websocket handlers.

  Note the naming convention of the websocket-related modules; we use `Websocket`, `WebSocket` is not allowed.

  Websocket module of gears must `use` this module as in the example below.
  `use SolomonLib.Websocket` implicitly invokes `use SolomonLib.Controller`, for convenience in implementing `connect/1` callback.

  ## Example

  The following example simply echoes back messages from client:

      defmodule MyGear.Websocket do
        use SolomonLib.Websocket

        def init(_conn) do
          {%{}, []}
        end

        def handle_client_message(state, _conn, frame) do
          {state, [frame]}
        end

        def handle_server_message(state, _conn, _msg) do
          {state, []}
        end
      end

  ## Name registration

  Once a websocket connection is established, subsequent bidirectional communication is handled by a dedicated connection process.
  To send websocket frames to the connected client,
  you should first be able to send messages to the connection process when a particular event occurs somewhere in the cluster.
  To this end antikythera provides a process registry mechanism which makes connection processes accessible by "name"s.

  To register connection processes, call `SolomonLib.Registry.Unique.register/2` and/or `SolomonLib.Registry.Group.join/2`
  in your `init/1` implementation.
  Then, to notify events of connection processes, use `SolomonLib.Registry.Unique.send_message/3` or
  `SolomonLib.Registry.Group.publish/3`.
  Finally to send websocket message from a connection process to client, implement `handle_server_message/3` callback
  so that it returns an appropriate websocket frame using the message.

  See `SolomonLib.Registry.Unique` and `SolomonLib.Registry.Group` for more detail of the registry.
  """

  alias SolomonLib.Conn
  alias SolomonLib.Websocket.{Frame, FrameList}

  @type state            :: any
  @type terminate_reason :: :normal | :stop | :timeout | :remote | {:remote, Frame.close_code, Frame.close_payload} | {:error, any}

  @typedoc """
  Type of return value of `init/1`, `handle_client_message/3` and `handle_server_message/3` callbacks.
  The 1st element of the return value is used as the new state.
  The 2nd element of the return value is sent to the client.

  To close the connection, include a `:close` frame in the 2nd element of the return value.
  Note that the remaining frames after the close frame will not be sent.
  """
  @type callback_result :: {state, FrameList.t}

  @doc """
  Callback function to be used during websocket handshake request.

  This callback is implemented in basically the same way as ordinary controller actions.
  You can use plugs and controller helper functions.
  The only difference is that on success this function returns a `SolomonLib.Conn.t` without setting an HTTP status code.

  This callback is responsible for authenticating/authorizing the client.
  If the client is valid and it's OK to start websocket communication, implementation of this callback must return the given `SolomonLib.Conn.t`.
  On the other hand if the client is not allowed to open websocket connection, this function must return an error as a usual HTTP response.

  `use SolomonLib.Websocket` generates a default implementation of this callback, which just returns the given `SolomonLib.Conn.t`.
  Note that you can use plugs without overriding the default.
  """
  @callback connect(Conn.t) :: Conn.t

  @doc """
  Callback function to be called right after a connection is established.

  This callback is responsible for:

  1. initialize the process state (1st element of return value)
  2. send initial message to client (2nd element of return value)
  3. register the process to make it accessible from other processes in the system (see "Name registration" above)
  """
  @callback init(Conn.t) :: callback_result

  @doc """
  Callback function to be called on receipt of a client message.
  """
  @callback handle_client_message(state, Conn.t, Frame.t) :: callback_result

  @doc """
  Callback function to be called on receipt of a message from other process in the cluster.
  """
  @callback handle_server_message(state, Conn.t, any) :: callback_result

  @doc """
  Callback function to clean up resources used by the websocket connection.

  For typical use cases you don't need to implement this callback;
  `SolomonLib.Websocket` generates a default implementation (which does nothing) for you.
  """
  @callback terminate(state, Conn.t, terminate_reason) :: any

  defmacro __using__(_) do
    quote do
      expected = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize() |> Module.concat("Websocket")
      if __MODULE__ != expected do
        raise "invalid module name: expected=#{expected} actual=#{__MODULE__}"
      end

      @behaviour SolomonLib.Websocket
      use SolomonLib.Controller

      @impl true
      def connect(conn), do: conn

      @impl true
      def terminate(_state, _conn, _reason), do: :ok

      defoverridable [connect: 1, terminate: 3]
    end
  end
end
