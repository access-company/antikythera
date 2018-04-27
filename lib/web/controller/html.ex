# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Controller.Html do
  @moduledoc """
  [DEPRECATED] Defines `SolomonLib.Controller.Html.render/5`.
  """

  defdelegate render(conn, status, template_name, render_params, opts \\ [layout: :application]), to: SolomonLib.Conn
end
