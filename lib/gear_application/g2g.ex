# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.G2g do
  @moduledoc """
  Helper module to define each gear's `G2g` module that contains interface for gear-to-gear communication.
  """

  alias Antikythera.{Conn, Context, G2gRequest, G2gResponse}

  defmacro __using__(_) do
    quote do
      defmodule G2g do
        @gear_name Mix.Project.config()[:app]

        defun send_without_decoding(req :: v[G2gRequest.t()], context :: v[Context.t()]) ::
                G2gResponse.t() do
          AntikytheraCore.Handler.GearAction.G2g.handle(req, context, @gear_name)
        end

        defun send_without_decoding(%Conn{request: web_req, context: context}) :: G2gResponse.t() do
          g2g_req = G2gRequest.from_web_request(web_req)
          __MODULE__.send_without_decoding(g2g_req, context)
        end

        defun send(req :: v[G2gRequest.t()], context :: v[Context.t()]) :: G2gResponse.t() do
          __MODULE__.send_without_decoding(req, context) |> G2gResponse.decode_body()
        end

        defun send(%Conn{request: web_req, context: context}) :: G2gResponse.t() do
          g2g_req = G2gRequest.from_web_request(web_req)
          __MODULE__.send(g2g_req, context)
        end
      end
    end
  end
end
