use Croma

defmodule <%= gear_name_camel %>.Controller.Hello do
  use Antikythera.Controller

  defmodule QueryParams do
    defmodule LocaleString do
      use Croma.SubtypeOfString, pattern: ~r/\A[A-Za-z0-9-]{1,10}\z/, default: "en"
    end

    use Antikythera.ParamStringStruct,
      fields: [
        locale: LocaleString
      ]
  end

  plug Antikythera.Plug.ParamsValidator, :validate, query_params: QueryParams

  defun hello(%Conn{assigns: %{validated: validated}} = conn) :: v[Conn.t()] do
    <%= gear_name_camel %>.Gettext.put_locale(validated.query_params.locale)
    Conn.render(conn, 200, "hello", [gear_name: :<%= gear_name %>])
  end
end
