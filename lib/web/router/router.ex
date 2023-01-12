# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Router do
  @moduledoc """
  Defines the antikythera routing DSL.

  ## Routing macros

  This module defines macros to be used in each gear's Router module.
  The names of the macros are the same as the HTTP verbs: `get`, `post`, etc.

  The macros take the following 4 arguments (although you can omit the last and just pass 3 of them):

  - URL path pattern which consists of '/'-separated segments. The 1st character must be '/'.
    To match against incoming request path to a pattern you can use placeholders. See examples below for the usage.
  - Controller module.
    Antikythera expects that the module name given here does not contain `GearName.Controller.` as a prefix;
    it's automatically prepended by antikythera.
  - Name of the controller action as an atom.
  - Keyword list of options.
    Currently available options are `:from` and `:as`. See below for further explanations.

  ## Example

  If you define the following router module,

      defmodule MyGear.Router do
        use Antikythera.Router

        static_prefix "/static"

        websocket "/ws"

        get  "/foo"       , Hello, :exact_match
        post "/foo/:a/:b" , Hello, :placeholders
        put  "/foo/bar/*w", Hello, :wildcard
      end

  Then the following requests are routed as:

  - `GET  "/foo"`                 => `MyGear.Controller.Hello.exact_match/1`  is invoked with `path_matches`: `%{}`
  - `POST "/foo/bar/baz"`         => `MyGear.Controller.Hello.placeholders/1` is invoked with `path_matches`: `%{a: "bar", b: "baz"}`
  - `PUT  "/foo/bar/abc/def/ghi"` => `MyGear.Controller.Hello.wildcard/1`     is invoked with `path_matches`: `%{w: "abc/def/ghi"}`

  Note that

  - Each controller action is expected to receive a `Antikythera.Conn` struct and returns a `Antikythera.Conn` struct.
  - `Antikythera.Conn` struct has a field `request` which is a `Antikythera.Request` struct.
  - Matched segments are URL-decoded and stored in `path_matches` field in `Antikythera.Request`.
    If the result of URL-decoding is nonprintable binary, the request is rejected.

  ## Websocket endpoint

  To enable websocket interaction with clients, you must first define `MyGear.Websocket` module.
  See `Antikythera.Websocket` for more details about websocket handler module.
  Then invoke `websocket/1` macro in your router.

      websocket "/ws_path_pattern"

  The path pattern may have placeholders in the same way as normal routes.
  GET request with appropriate headers to this path will initialize a websocket connection using the HTTP 1.1 upgrade mechanism.

  If your gear does not interact with clients via websocket, simply don't invoke `websocket/1` macro in your router.

  ## Static file serving

  You can serve your static assets by placing them under `/priv/static` directory in your gear project.
  The endpoint to be used can be specified by `static_prefix/1` macro.
  For example, if you add

      static_prefix "/assets"

  to your router, you can download `/priv/static/html/index.html` file by sending GET request to the path `/assets/html/index.html`.

  If you don't need to serve static assets, just don't call `static_prefix/1` macro in your router.

  Currently, static assets served in this way are NOT automatically gzip compressed,
  even if `acceept-encoding: gzip` request header is set.
  It is recommended to use CDN to deliver large static assets in production.

  See also `Antikythera.Asset` for usage of CDN in delivery of static assets.

  ## Web requests and gear-to-gear (g2g) requests

  Antikythera treats both web requests and g2g requests in basically the same way.
  This means that if you define a route in your gear one can send request to the route using both HTTP and g2g communication.
  If you want to define a route that can be accessible only via g2g communication, specify `from: :gear` option.

      get  "/foo", Hello, :action1, from: :gear
      post "/bar", Hello, :action2, from: :gear

  Similarly passing `from: :web` makes the route accessible only from web request.

  When dealing with multiple routes, `only_from_web/1` and `only_from_gear/1` macros can be used.
  For example, the following routes definition is the same as above one.

      only_from_gear do
        get  "/foo", Hello, :action1
        post "/bar", Hello, :action2
      end

  ## Reverse routing

  To generate URL path of a route (e.g. a link in HTML), you will want to refer to the route's path.
  For this purpose you can specify `:as` option.
  For example, you have the following router module

      defmodule MyGear.Router do
        use Antikythera.Router

        get "/foo/:a/:b/*c", Hello, :placeholders, as: :myroute
      end

  By writing this the router automatically defines a function `myroute_path/4`,
  which receives segments that fill placeholders and an optional map for query parameters.

      MyGear.Router.myroute_path("segment_a", "segment_b", ["wildcard", "part"])
      => "/foo/segment_a/segment_b/wildcard/part
      MyGear.Router.myroute_path("segment_a", "segment_b", ["wildcard", "part"], %{"query" => "param"})
      => "/foo/segment_a/segment_b/wildcard/part?query=param

  Reverse routing helper functions automatically URI-encode all given arguments.

  If websocket endpoint is enabled, you can get its path with `MyGear.Router.websocket_path/0`.
  Also if static file serving is enabled, path prefix for static files can be obtained by `MyGear.Router.static_prefix/0`.
  """

  alias Antikythera.Router.Impl

  defmacro __using__(_) do
    quote do
      import Antikythera.Router
      Module.register_attribute(__MODULE__, :antikythera_web_routes, accumulate: true)
      Module.register_attribute(__MODULE__, :antikythera_gear_routes, accumulate: true)
      Module.put_attribute(__MODULE__, :from_option, nil)
      @before_compile Antikythera.Router
    end
  end

  defmacro __before_compile__(%Macro.Env{module: module}) do
    web_routing_source = Module.get_attribute(module, :antikythera_web_routes) |> Enum.reverse()
    gear_routing_source = Module.get_attribute(module, :antikythera_gear_routes) |> Enum.reverse()

    routing_quotes(module, web_routing_source, gear_routing_source) ++
      reverse_routing_quotes(web_routing_source, gear_routing_source)
  end

  defp routing_quotes(module, web_source, gear_source) do
    Impl.generate_route_function_clauses(module, :web, web_source) ++
      Impl.generate_route_function_clauses(module, :gear, gear_source)
  end

  defp reverse_routing_quotes(web_source, gear_source) do
    alias Antikythera.Router.Reverse

    Enum.uniq(web_source ++ gear_source)
    |> Enum.reject(fn {_verb, _path, _controller, _action, opts} -> is_nil(opts[:as]) end)
    |> Enum.map(fn {_verb, path, _controller, _action, opts} ->
      Reverse.define_path_helper(opts[:as], path)
    end)
  end

  for from <- [:web, :gear] do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    defmacro unquote(:"only_from_#{from}")(do: block) do
      current_from = unquote(from)

      quote do
        if @from_option, do: raise("nested invocation of `only_from_*` is not allowed")
        @from_option unquote(current_from)
        unquote(block)
        @from_option nil
      end
    end
  end

  for verb <- Antikythera.Http.Method.all() do
    defmacro unquote(verb)(path, controller, action, opts \\ []) do
      %Macro.Env{module: router_module} = __CALLER__
      add_route(router_module, unquote(verb), path, controller, action, opts)
    end
  end

  defp add_route(router_module, verb, path, controller_given, action, opts) do
    quote bind_quoted: [
            r_m: router_module,
            verb: verb,
            path: path,
            c_g: controller_given,
            action: action,
            opts: opts
          ] do
      controller = Antikythera.Router.fully_qualified_controller_module(r_m, c_g, opts)
      from_grouped = Module.get_attribute(__MODULE__, :from_option)
      from_per_route = opts[:from]

      if from_grouped && from_per_route,
        do: raise("using :from option within `only_from_*` block is not allowed")

      opts_without_from_option = Keyword.delete(opts, :from)
      routing_info = {verb, path, controller, action, opts_without_from_option}

      case from_grouped || from_per_route do
        :web ->
          @antikythera_web_routes routing_info

        :gear ->
          @antikythera_gear_routes routing_info

        nil ->
          @antikythera_web_routes routing_info
          @antikythera_gear_routes routing_info
      end
    end
  end

  def fully_qualified_controller_module(router_module, controller, opts) do
    if opts[:websocket?] do
      controller
    else
      [
        Module.split(router_module) |> hd(),
        "Controller",
        # `{:__aliases__, meta, atoms}` must be expanded
        Macro.expand(controller, __ENV__)
      ]
      # Executed during compilation; `Module.concat/1` causes no problem
      |> Module.concat()
    end
  end

  defmacro websocket(path, opts \\ []) do
    %Macro.Env{module: router_module} = __CALLER__
    # during compilation, it's safe to call `Module.concat/2`
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    ws_module = Module.split(router_module) |> hd() |> Module.concat("Websocket")

    quote do
      get(
        unquote(path),
        unquote(ws_module),
        :connect,
        [only_from: :web, websocket?: true] ++ unquote(opts)
      )
    end
  end

  defmacro static_prefix(prefix) do
    quote bind_quoted: [prefix: prefix] do
      if prefix =~ ~R|\A(/[0-9A-Za-z.~_-]+)+\z| do
        def static_prefix(), do: unquote(prefix)
      else
        raise "invalid path prefix given to `static_prefix/1`: #{prefix}"
      end
    end
  end
end
