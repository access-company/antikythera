# Implementing Controller

**Note:** This page is being updated for OSS release. Please be patient.

- Controller action must receives a `Antikythera.Conn` struct and returns a `Antikythera.Conn`.
  In other words, type signature of a controller action must be `acion(Antikythera.Conn.t) :: Antikythera.Conn.t`.
- What controller action should do is, based on the request information in `Conn` struct,
  to construct a new `Conn` filled with response information (HTTP status code, body, headers, etc.).
  Antikythera picks up the response information from the returned `Conn` and sends back to the request sender.
- For this purpose many utility functions are defined in `Antikythera.Controller`.
  Those functions are auto-imported when you `use Antikythera.Controller` in your controller module.
- Controller action must return a response within 10 seconds.
    - It is recommended that you set the client timeout value to 15 seconds or more. This is because the [executor pool](https://hexdocs.pm/antikythera/executor_pool.html) waits up to 5 seconds and the controller takes up to 10 seconds.
- Gzip compression of responses is done transparently when a request contains `accept-encoding: gzip` header.

## Handling errors

- By default antikythera returns a simple error response to request sender in the following situations:
    - An error occurs during execution of controller action.
    - No controller action matches the request's method/path.
    - Format of the request body does not conform to the value of `content-type` header.
    - Websocket connections limit is reached.
- To customize response on error, you can define your gear's custom error handlers by:
    - Add `YourGear.Controller.Error` module.
    - Inside the module define the following functions:
        - `error/2`
        - `no_route/1`
        - `bad_request/1`
        - `bad_executor_pool_id/2` (optional)
        - `ws_too_many_connections/1` (optional)
        - `parameter_validation_error/3` (optional)
    - These functions must return a `Antikythera.Conn.t` as in regular controller actions.
- Note that custom error handlers should do as little task as possible to avoid further troubles.

## Response headers

- Before returning an HTTP response antikythera automatically adds the following response headers for security reasons:
    - `x-frame-options` : `DENY`
    - `x-xss-protection` : `1; mode=block`
    - `x-content-type-options` : `nosniff`
    - `strict-transport-security` : `max-age=31536000`
- Gear implementations can explicitly set these headers;
  in this case antikythera respects the value and don't overwrite it.
