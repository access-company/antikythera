defmodule <%= gear_name_camel %>.Controller.Hello do
  use SolomonLib.Controller

  def hello(conn) do
    <%= gear_name_camel %>.Gettext.put_locale(conn.request.query_params["locale"] || "en")
    Conn.render(conn, 200, "hello", [gear_name: :<%= gear_name %>])
  end
end
