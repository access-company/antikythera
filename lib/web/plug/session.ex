# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Plug.Session do
  @moduledoc """
  Plug to automatically load/store session information using a specific session store.
  Uses cookie store by default.

  ## Usage

  Adding the following line in a controller module enables this plug:

      plug Antikythera.Plug.Session, :load, [key: "12345678"]

  Then,
  - session values are loaded from cookie before controller action is executed, and
  - session values are stored into cookie after controller action is executed.
  """

  alias Antikythera.Conn
  alias Antikythera.Session
  alias Antikythera.Http

  @type load_option_t ::
          {:key, String.t()} | {:store, atom} | {:set_cookie, Http.SetCookie.options_t()}

  defun load(conn :: v[Conn.t()], opts :: v[list(load_option_t)]) :: Conn.t() do
    key = opts[:key]
    set_cookie_opts = Keyword.get(opts, :set_cookie, %{})
    store_name = Keyword.get(opts, :store, :cookie) |> Atom.to_string() |> Macro.camelize()
    store_module = Module.safe_concat("Antikythera.Session", store_name)
    {session_id, data} = store_module.load(Conn.get_req_cookie(conn, key))

    session = %Session{
      state: :update,
      id: session_id,
      data: data
    }

    conn
    |> Conn.register_before_send(make_before_send(store_module, key, set_cookie_opts))
    |> Conn.assign(:session, session)
  end

  defunp make_before_send(store :: module, key :: String.t(), set_cookie_opts :: map) ::
           (Conn.t() -> Conn.t()) do
    fn %Conn{assigns: %{session: session}} = conn ->
      %Session{state: state, id: id, data: data} = session

      case state do
        :update ->
          new_id = store.save(id, data)
          Conn.put_resp_cookie(conn, key, new_id, set_cookie_opts)

        :renew ->
          store.delete(id)
          new_id = store.save(nil, data)
          Conn.put_resp_cookie(conn, key, new_id, set_cookie_opts)

        :destroy ->
          store.delete(id)
          Conn.put_resp_cookie_to_revoke(conn, key)
      end
    end
  end
end
