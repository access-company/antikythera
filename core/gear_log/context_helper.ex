# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.ContextHelper do
  @moduledoc """
  Helpers to get/set context ID.

  Context IDs are mainly to be used for logging.
  In order to keep `Logger`'s interface clean (i.e. not to make `context_id` trump data solely for logging purpose),
  context ID is stored in each process's process dictionary and fetched when a process emits a log message.
  """

  alias Antikythera.{Conn, Context, ContextId}

  @key :antikythera_context_id

  defun set(conn_or_context_or_id :: Conn.t() | Context.t() | ContextId.t()) :: :ok do
    %Conn{context: context} ->
      set(context)

    %Context{context_id: context_id} ->
      set(context_id)

    context_id ->
      _previous_value = Process.put(@key, context_id)
      :ok
  end

  defun get!() :: ContextId.t() do
    case Process.get(@key) do
      nil -> raise "No context ID found!"
      context_id -> context_id
    end
  end
end
