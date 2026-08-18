# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.LoggerBackendTest do
  use Croma.TestCase
  require Logger
  alias AntikytheraCore.Alert.Manager, as: CoreAlertManager
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraEal.AlertMailer.{Mail, MemoryInbox}

  setup do
    :meck.new(ConfigCache.Core, [:passthrough])
    alert_config = %{"email" => %{"to" => ["test@example.com"], "fast_interval" => 1}}
    assert CoreAlertManager.update_handler_installations(:antikythera, alert_config) == :ok
    :meck.expect(ConfigCache.Core, :read, fn -> %{alerts: alert_config} end)
    MemoryInbox.clean()

    on_exit(fn ->
      CoreAlertManager.update_handler_installations(:antikythera, %{})
      MemoryInbox.clean()
      :meck.unload()
    end)
  end

  test "an :error log is forwarded to Alert.Manager and delivered as an alert" do
    message = "logger backend alert integration #{:erlang.unique_integer([:positive])}"

    Logger.error(message)
    Logger.flush()

    # After `fast_interval` the buffered error is delivered as an alert mail, exercising the whole
    # path Logger -> logger_backends -> `AntikytheraCore.Alert.LoggerBackend` -> `Alert.Manager`.
    :timer.sleep(1_100)

    assert Enum.any?(MemoryInbox.get(), fn %Mail{to: to, body: body} ->
             to == ["test@example.com"] and String.contains?(body, message)
           end)
  end
end
