# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Test.GearLogHelper do
  @moduledoc """
  Helpers to work with gear logs within tests.
  """

  alias Antikythera.{Context, Conn}
  alias Antikythera.Test.ConnHelper
  alias AntikytheraCore.GearLog.ContextHelper

  @doc """
  Sets a context ID (which is included in gear logs) to process dictionary so that logs can be emitted during test executions.

  If no argument is given, generates a new context ID and sets it.
  """
  defun set_context_id(conn_or_context_or_nil :: nil | Context.t() | Conn.t() \\ nil) :: :ok do
    nil -> set_context_id(ConnHelper.make_conn())
    %Context{} = context -> ContextHelper.set(context)
    %Conn{} = conn -> ContextHelper.set(conn)
  end
end
