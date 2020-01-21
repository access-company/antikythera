# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Session.Cookie do
  @moduledoc """
  Implementation of `Antikythera.Session.Store` that stores session info in cookie.
  """

  alias Antikythera.Session.Store
  @behaviour Store

  @impl true
  defun load(nil) :: {nil, Store.session_kv} do
    {nil, %{}}
  end
  defun load(cookie :: g[String.t]) :: {nil, Store.session_kv} do
    value = Poison.decode(cookie) |> Croma.Result.get(%{})
    {nil, value}
  end

  @impl true
  defun save(nil, value :: Store.session_kv) :: String.t do
    Poison.encode!(value)
  end

  @impl true
  defun delete(nil) :: :ok, do: :ok
end
