# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.Html do
  @moduledoc """
  [DEPRECATED] Defines `Antikythera.Controller.Html.render/5`.
  """

  defdelegate render(conn, status, template_name, render_params, opts \\ [layout: :application]), to: Antikythera.Conn
end
