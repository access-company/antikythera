use Croma

defmodule <%= gear_name_camel %>.Controller.Api.Hello do
  use Antikythera.Controller

  defmodule Body do
    defmodule UserName do
      use Croma.SubtypeOfString, pattern: ~r/\A[A-Za-z0-9_]+\z/
    end

    use Antikythera.BodyJsonStruct,
      fields: [
        name: UserName
      ]
  end

  plug Antikythera.Plug.ParamsValidator, :validate, body: Body

  defun hello(%Conn{assigns: %{validated: validated}} = conn) :: v[Conn.t()] do
    Conn.json(conn, 200, %{message: "Hello, #{validated.body.name}!"})
  end
end
