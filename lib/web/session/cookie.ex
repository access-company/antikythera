# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Session.Cookie do
  @moduledoc """
  Implementation of `Antikythera.Session.Store` that stores session info in cookie.
  """

  alias Antikythera.Session.Store
  @behaviour Store

  @impl true
  defun load(cookie :: nil | String.t()) :: {nil, Store.session_kv()} do
    nil ->
      {nil, %{}}

    cookie when is_binary(cookie) ->
      value = Poison.decode(cookie) |> Croma.Result.get(%{})
      {nil, value}
  end

  @impl true
  defun save(nil, value :: Store.session_kv()) :: String.t() do
    Poison.encode!(value)
  end

  @impl true
  defun delete(nil) :: :ok, do: :ok
end
