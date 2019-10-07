# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma
alias Antikythera.Http

defmodule Antikythera.Request do
  @moduledoc """
  Definition of `Antikythera.Request` struct.
  """

  defmodule PathMatches do
    use Croma.SubtypeOfMap, key_module: Croma.Atom, value_module: Croma.String
  end

  defmodule Sender do
    alias Antikythera.GearName
    @type sender_ip :: String.t
    @type t         :: {:web, sender_ip} | {:gear, GearName.t}

    defun valid?(v :: term) :: boolean do
      {:web, s} when is_binary(s) -> true
      {:gear, n}                  -> GearName.valid?(n)
      _                           -> false
    end
  end

  use Croma.Struct, recursive_new?: true, fields: [
    method:       Http.Method,
    path_info:    Antikythera.PathInfo,
    path_matches: PathMatches,
    query_params: Http.QueryParams,
    headers:      Http.Headers,
    cookies:      Http.ReqCookiesMap,
    raw_body:     Http.RawBody, # can be used to e.g. check HMAC of body
    body:         Http.Body,
    sender:       Sender,
  ]
end

defmodule Antikythera.Conn do
  @moduledoc """
  Definition of `Antikythera.Conn` struct, which represents a client-server connection.

  This module also defines many functions to work with `Antikythera.Conn`.
  """

  alias Antikythera.{Request, Context}
  alias Antikythera.Session
  alias Antikythera.FastJasonEncoder

  defmodule BeforeSend do
    use Croma.SubtypeOfList, elem_module: Croma.Function, default: []
  end

  defmodule Assigns do
    use Croma.SubtypeOfMap, key_module: Croma.Atom, value_module: Croma.Any, default: %{}
  end

  use Croma.Struct, recursive_new?: true, fields: [
    request:      Request,
    context:      Context,
    status:       Croma.TypeGen.nilable(Http.Status.Int),
    resp_headers: Http.Headers,
    resp_cookies: Http.SetCookiesMap,
    resp_body:    Http.RawBody,
    before_send:  BeforeSend,
    assigns:      Assigns,
  ]

  #
  # Lower-level interfaces to manipulate `Conn.t`.
  #
  defun get_req_header(%__MODULE__{request: request}, key :: v[String.t]) :: nil | String.t do
    request.headers[key]
  end

  defun get_req_query(%__MODULE__{request: request}, key :: v[String.t]) :: nil | String.t do
    request.query_params[key]
  end

  defun put_status(conn :: v[t], status :: v[Http.Status.t]) :: t do
    %__MODULE__{conn | status: Http.Status.code(status)}
  end

  defun put_resp_header(%__MODULE__{resp_headers: resp_headers} = conn, key :: v[String.t], value :: v[String.t]) :: t do
    %__MODULE__{conn | resp_headers: Map.put(resp_headers, key, value)}
  end

  defun put_resp_headers(%__MODULE__{resp_headers: resp_headers} = conn, headers :: v[%{String.t => String.t}]) :: t do
    %__MODULE__{conn | resp_headers: Map.merge(resp_headers, headers)}
  end

  defun put_resp_body(conn :: v[t], body :: v[String.t]) :: t do
    %__MODULE__{conn | resp_body: body}
  end

  @doc """
  Returns all request cookies.
  """
  defun get_req_cookies(%__MODULE__{request: %Request{cookies: cookies}}) :: Http.ReqCookiesMap.t do
    cookies
  end

  @doc """
  Returns a request cookie specified by `name`.
  """
  defun get_req_cookie(conn :: v[t], name :: v[String.t]) :: nil | String.t do
    get_req_cookies(conn)[name]
  end

  @default_cookie_opts (if Antikythera.Env.compiling_for_cloud?(), do: %{path: "/", secure: true}, else: %{path: "/"})

  @doc """
  Adds a `set-cookie` response header to the given `Antikythera.Conn.t`.

  `path` directive of `set-cookie` header is automatically filled with `"/"` if not explicitly given.
  Also `secure` directive is filled by default in the cloud environments (assuming that it's serving with HTTPS).

  Note that response cookies are stored separately from the other response headers,
  as cookies require special treatment according to the HTTP specs.
  """
  defun put_resp_cookie(%__MODULE__{resp_cookies: resp_cookies} = conn,
                        name  :: v[String.t],
                        value :: v[String.t],
                        opts0 :: Http.SetCookie.options_t \\ %{}) :: t do
    opts = Map.merge(@default_cookie_opts, opts0)
    set_cookie = %Http.SetCookie{value: value} |> Http.SetCookie.update!(opts)
    %__MODULE__{conn | resp_cookies: Map.put(resp_cookies, name, set_cookie)}
  end

  @doc """
  Tells the client to delete an existing cookie specified by `name`.

  This is a wrapper around `put_resp_cookie/4` that sets an immediately expiring cookie (whose value is an empty string).
  """
  defun put_resp_cookie_to_revoke(conn :: v[t], name :: v[String.t]) :: t do
    put_resp_cookie(conn, name, "", %{max_age: 0})
  end

  defun register_before_send(%__MODULE__{before_send: before_send} = conn, callback :: (t -> t)) :: t do
    %__MODULE__{conn | before_send: [callback | before_send]}
  end

  # These session-related functions assume that the `conn` is processed by `Antikythera.Plug.Session`
  # and thus it contains `:session` field in `:assigns`.
  defun get_session(%__MODULE__{assigns: %{session: session}}, key :: v[String.t]) :: any do
    Session.get(session, key)
  end

  defun put_session(%__MODULE__{assigns: %{session: session}} = conn, key :: v[String.t], value :: any) :: t do
    assign(conn, :session, Session.put(session, key, value))
  end

  defun delete_session(%__MODULE__{assigns: %{session: session}} = conn, key :: v[String.t]) :: t do
    assign(conn, :session, Session.delete(session, key))
  end

  defun clear_session(%__MODULE__{assigns: %{session: session}} = conn) :: t do
    assign(conn, :session, Session.clear(session))
  end

  defun renew_session(%__MODULE__{assigns: %{session: session}} = conn) :: t do
    assign(conn, :session, Session.renew(session))
  end

  defun destroy_session(%__MODULE__{assigns: %{session: session}} = conn) :: t do
    assign(conn, :session, Session.destroy(session))
  end

  defun assign(%__MODULE__{assigns: assigns} = conn, key :: v[atom], value :: any) :: t do
    %__MODULE__{conn | assigns: Map.put(assigns, key, value)}
  end

  #
  # Higher-level interfaces: Conveniences for common operations on `Conn.t`,
  # (implemented using the lower-level interfaces defined above).
  #
  @doc """
  Put `cache-control` response header for responses that must not be cached.

  The actual header value to be set is: `"private, no-cache, no-store, max-age=0"`.
  """
  defun no_cache(conn :: v[t]) :: t do
    put_resp_header(conn, "cache-control", "private, no-cache, no-store, max-age=0")
  end

  @doc """
  Returns an HTTP response that make the client redirect to the specified `url`.
  """
  defun redirect(conn :: v[t], url :: v[String.t], status :: v[Http.Status.t] \\ 302) :: t do
    conn
    |> put_resp_header("location", url)
    |> put_status(status)
  end

  @doc """
  Returns a JSON response.
  """
  defun json(%__MODULE__{resp_headers: resp_headers} = conn, status :: v[Http.Status.t], body :: v[%{(atom | String.t) => any} | [any]]) :: t do
    {:ok, json} = FastJasonEncoder.encode(body)
    %__MODULE__{conn |
      status:       Http.Status.code(status),
      resp_headers: Map.put(resp_headers, "content-type", "application/json"),
      resp_body:    json,
    }
  end

  @doc """
  Renders a HAML template file and returns the dynamic content as an HTML response.
  """
  defun render(%__MODULE__{context: context, resp_headers: resp_headers, assigns: assigns} = conn,
               status        :: v[Http.Status.t],
               template_name :: v[String.t],
               render_params :: Keyword.t(any),
               opts          :: Keyword.t(atom) \\ [layout: :application]) :: t do
    flash = Map.get(assigns, :flash, %{})
    template_module = AntikytheraCore.GearModule.template_module_from_context(context)
    %__MODULE__{conn |
      status:       Http.Status.code(status),
      resp_headers: Map.put(resp_headers, "content-type", "text/html; charset=utf-8"),
      resp_body:    html_content(template_module, template_name, [flash: flash] ++ render_params, opts[:layout]),
    }
  end

  defunp html_content(template_module :: v[module],
                      template_name   :: v[String.t],
                      render_params   :: Keyword.t(any),
                      layout_name     :: v[nil | atom]) :: String.t do
    content = template_module.content_for(template_name, render_params)
    {:safe, str} =
      case layout_name do
        nil    -> content
        layout ->
          params_with_internal_content = [yield: content] ++ render_params
          template_module.content_for("layout/#{layout}", params_with_internal_content)
      end
    str
  end

  @doc """
  Sends a file which resides in `priv/` directory as a response.

  `path` must be a file path relative to the `priv/` directory.
  content-type header is inferred from the file's extension.

  Don't use this function for sending large files; you should use CDN for large files (see `Antikythera.Asset`).
  Also, if all you need to do is just to return a file (i.e. you don't need any authentication),
  you should not use this function; just placing the file under `priv/static/` directory should suffice.
  """
  defun send_priv_file(%__MODULE__{context: context, resp_headers: resp_headers} = conn, status :: v[Http.Status.t], path :: Path.t) :: t do
    # Protect from directory traversal attack
    if String.contains?(path, "..") do
      raise "path must not contain `..`"
    end
    %__MODULE__{conn |
      status:       Http.Status.code(status),
      resp_headers: Map.put(resp_headers, "content-type", mimetype(path)),
      resp_body:    File.read!(filepath(context, path)),
    }
  end

  defunp mimetype(path :: Path.t) :: String.t do
    {top, sub, _} = :cow_mimetypes.all(path)
    "#{top}/#{sub}"
  end

  defunp filepath(%Context{gear_entry_point: {mod, _}}, path :: Path.t) :: Path.t do
    gear_name = Module.split(mod) |> hd() |> Macro.underscore() |> String.to_existing_atom()
    Path.join(:code.priv_dir(gear_name), path)
  end

  @doc """
  Gets a flash message stored in the given `t:Antikythera.Conn.t/0`.
  """
  defun get_flash(%__MODULE__{assigns: assigns}, key :: v[String.t]) :: nil | String.t do
    assigns.flash[key]
  end

  @doc """
  Stores the flash message into the current `t:Antikythera.Conn.t/0`.
  """
  defun put_flash(%__MODULE__{assigns: assigns} = conn, key :: v[String.t], value :: v[String.t]) :: t do
    assign(conn, :flash, Map.put(assigns.flash, key, value))
  end
end
