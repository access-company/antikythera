# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.LoggerBackend do
  @moduledoc """
  Backend handler for `Logger`, which notifies `AntikytheraCore.Alert.Manager` of error events.
  """

  @behaviour :gen_event
  alias AntikytheraCore.Alert.Manager, as: CoreAlertManager

  @impl true
  def init(_) do
    {:ok, nil}
  end

  @impl true
  def handle_call({:configure, _opts}, state) do
    {:ok, :ok, state}
  end

  @impl true
  def handle_event({:error, gl, {Logger, message, {ymd, {h, min, s, ms}}, metadata}}, state)
      when node(gl) == node() do
    time = {Antikythera.Time, ymd, {h, min, s}, ms}
    CoreAlertManager.notify(CoreAlertManager, body(message, metadata), time)
    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  defunp body(message :: Logger.message(), metadata :: Keyword.t()) :: String.t() do
    # Just dump everything attached
    metadata_str =
      Enum.map_join(metadata, "\n", fn {key, value} ->
        "#{key}: #{inspect(value)}"
      end)

    "#{message}\n#{metadata_str}"
  end

  #
  # irrelevant gen_event callbacks
  #
  @impl true
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old, state, _extra) do
    {:ok, state}
  end
end
