# Websocket

- [Websocket](https://en.wikipedia.org/wiki/WebSocket) is an extension to HTTP that emulates TCP connections.
  By using websocket, communication pattern between server and client is no longer restricted to plain HTTP's request-response model.
- Antikythera supports the websocket protocol to enable gears to interactively communicate with their clients.

## Implementing websocket-enabled gear

- To use websocket in your gear you need to
    1. declare a websocket route in `web/router.ex`
        - The route is for handshake; GET requests that match the path pattern are processed as websocket handshake requests.
        - See [reference of `Antikythera.Router`](https://hexdocs.pm/antikythera/Antikythera.Router.html).
    2. implement a callback module of `Antikythera.Websocket` behaviour in `web/websocket.ex`
        - For detailed explanations of specifications of `Antikythera.Websocket` callbacks
          see the [ExDoc document](https://hexdocs.pm/antikythera/Antikythera.Websocket.html) of the module.

## Websocket connection process

- Once a websocket connection is established between antikythera and a client,
  antikythera allocates a dedicated process for the connection.
    - Note that the connection process is created on the node that received the handshake request in the cluster.
    - This connection process handles all incoming/outgoing frames between the server and the client.
        - To push a frame to the client, you must first send an Erlang message to the connection process.
          You can use `Antikythera.Registry.Unique` and/or `Antikythera.Registry.Group` for this purpose.

### Connections limit

- In order to prevent a specific gear from monopolizing resources in the cluster,
  antikythera imposes an upper limit on number of websocket connections per [executor pool](./executor_pool.md).
    - During handshake, antikythera calls `YourGear.executor_pool_for_web_request/1` to ask which executor pool this client belongs to.
    - Trying to connect more than the limit results in an HTTP 503 (Service Unavailable) error.
        - The error can be customized as you wish; see [handling errors](./controller.md#handling-errors).

### Idle timeout

- A websocket connection established between an antikythera gear and a client is automatically closed after 60 seconds of idle time.
- If you want to keep websocket connections during idle time it's recommended that clients periodically send ping frames.
    - It's also possible that the server sends periodic pings but in most cases
      it's better to distribute computational costs associated with the timers for large number of clients.
- You don't have to implement the server to reply with pong frame; ping frames are automatically handled by antikythera.

### Disconnection from soon-to-be-terminated server

- For maintenance reason, a subset of antikythera servers in the cluster may be shut down at any time.
  Before it is actually terminated, each target server will automatically send a `close` frame with status code `1001`
  to all the connected websocket clients.
  Client implementations should be prepared with these situations by properly reconnecting to other working servers in the cluster.
