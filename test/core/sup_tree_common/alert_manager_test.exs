# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.ManagerTest do
  use Croma.TestCase, alias_as: CoreAlertManager
  alias Antikythera.Time
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Alert.Handler, as: AHandler
  alias AntikytheraCore.Alert.Handler.Email, as: EmailHandler
  alias AntikytheraCore.Alert.ErrorCountReporter
  alias AntikytheraEal.AlertMailer.{Mail, MemoryInbox}

  defp which_handlers() do
    :gen_event.which_handlers(CoreAlertManager)
  end

  setup do
    :meck.new(ConfigCache.Core, [:passthrough])

    on_exit(fn ->
      # reset
      CoreAlertManager.update_handler_installations(:antikythera, %{})
      MemoryInbox.clean()
      :meck.unload()
    end)
  end

  test "should spawn AntikytheraCore.Alert.Manager process on core startup" do
    assert is_pid(Process.whereis(CoreAlertManager))
  end

  test "should install/uninstall a handler, depending on the contents of config" do
    # Without any config
    assert which_handlers() == [ErrorCountReporter]

    # With sufficient config for Handler.Email
    valid_config = %{"email" => %{"to" => ["test@example.com"]}}
    update_handler_installations_and_mock_core_config_cache(valid_config)
    assert which_handlers() == [{AHandler, EmailHandler}, ErrorCountReporter]

    # When the config for Handler.Email becomes/is invalid
    invalid_config1 = %{"email" => %{"without" => "to"}}
    update_handler_installations_and_mock_core_config_cache(invalid_config1)
    assert which_handlers() == [ErrorCountReporter]
    invalid_config2 = %{"email" => %{"to" => ["invalid-email-address"]}}
    update_handler_installations_and_mock_core_config_cache(invalid_config2)
    assert which_handlers() == [ErrorCountReporter]

    # When the config for Handler.Email is deleted
    update_handler_installations_and_mock_core_config_cache(valid_config)
    assert which_handlers() == [{AHandler, EmailHandler}, ErrorCountReporter]
    update_handler_installations_and_mock_core_config_cache(%{})
    assert which_handlers() == [ErrorCountReporter]
  end

  test "should buffer a message and start fast-then-delayed alert chain when notified" do
    valid_config = %{
      "email" => %{
        "to" => ["test@example.com"],
        "fast_interval" => 1,
        "delayed_interval" => 2,
        "errors_per_body" => 1
      }
    }

    update_handler_installations_and_mock_core_config_cache(valid_config)
    assert which_handlers() == [{AHandler, EmailHandler}, ErrorCountReporter]
    assert %{message_buffer: [], busy?: false} = get_handler_state(EmailHandler)
    assert MemoryInbox.get() == []

    # Message incoming -> start buffering
    assert CoreAlertManager.notify(CoreAlertManager, "test_body1\nsecond line1") == :ok
    assert %{message_buffer: buffer1, busy?: true} = get_handler_state(EmailHandler)
    assert [{time1, "test_body1\nsecond line1"}] = buffer1
    assert MemoryInbox.get() == []

    # After first `fast_interval` -> alert sent
    :timer.sleep(1_100)
    assert %{message_buffer: [], busy?: true} = get_handler_state(EmailHandler)
    assert [%Mail{to: ["test@example.com"], subject: subject1, body: body1}] = MemoryInbox.get()
    assert String.ends_with?(subject1, "test_body1")

    assert body1 ==
             """
             [#{Time.to_iso_timestamp(time1)}] test_body1
             second line1


             """

    # After another `fast_interval` -> throttled; messages buffered
    assert CoreAlertManager.notify(CoreAlertManager, "test_body2\nsecond line2") == :ok
    assert CoreAlertManager.notify(CoreAlertManager, "test_body3\nsecond line3") == :ok
    assert CoreAlertManager.notify(CoreAlertManager, "test_body4\nsecond line4") == :ok
    :timer.sleep(1_000)
    assert %{message_buffer: buffer2, busy?: true} = get_handler_state(EmailHandler)

    assert [
             {time4, "test_body4\nsecond line4"},
             {time3, "test_body3\nsecond line3"},
             {time2, "test_body2\nsecond line2"}
           ] = buffer2

    assert [%Mail{to: ["test@example.com"], subject: ^subject1, body: ^body1}] = MemoryInbox.get()

    # After `delayed_interval` -> alert sent (with summarized message), and still "busy"
    :timer.sleep(1_000)
    assert %{message_buffer: [], busy?: true} = get_handler_state(EmailHandler)

    assert [
             %Mail{to: ["test@example.com"], subject: subject2, body: body2},
             %Mail{to: ["test@example.com"], subject: ^subject1, body: ^body1}
           ] = MemoryInbox.get()

    assert String.ends_with?(subject2, "test_body2 [and other 2 error(s)]")

    assert body2 ==
             """
             [#{Time.to_iso_timestamp(time2)}] test_body2
             second line2


             [#{Time.to_iso_timestamp(time3)}] test_body3
             [#{Time.to_iso_timestamp(time4)}] test_body4
             """

    # After another `delayed_interval` without messages -> back to "not busy"
    :timer.sleep(2_000)
    assert %{message_buffer: [], busy?: false} = get_handler_state(EmailHandler)
  end

  test "should ignore alerts if the message pattern matches any of the specified patterns" do
    ignore_patterns = [
      "\\(MatchError\\) no match of right hand side value:",
      "(*CRLF)\\A\\*\\* \\(ArithmeticError\\) bad argument in arithmetic expression:.*second line3"
    ]

    valid_config = %{
      "email" => %{
        "to" => ["test@example.com"],
        "fast_interval" => 1,
        "ignore_patterns" => ignore_patterns
      }
    }

    update_handler_installations_and_mock_core_config_cache(valid_config)
    assert which_handlers() == [{AHandler, EmailHandler}, ErrorCountReporter]
    assert %{message_buffer: [], busy?: false} = get_handler_state(EmailHandler)
    assert MemoryInbox.get() == []

    # to be ignored
    assert CoreAlertManager.notify(
             CoreAlertManager,
             "** (MatchError) no match of right hand side value: 1\nsecond line1"
           ) == :ok

    assert %{message_buffer: [], busy?: false} = get_handler_state(EmailHandler)
    assert MemoryInbox.get() == []

    # not to be ignored
    assert CoreAlertManager.notify(
             CoreAlertManager,
             "** (UndefinedFunctionError) function Hoge.foo/0 is undefined (module Hoge is not available)\nsecond line2"
           ) == :ok

    assert %{message_buffer: buffer1, busy?: true} = get_handler_state(EmailHandler)

    assert [
             {time1,
              "** (UndefinedFunctionError) function Hoge.foo/0 is undefined (module Hoge is not available)\nsecond line2"}
           ] = buffer1

    assert MemoryInbox.get() == []

    # to be ignored
    assert CoreAlertManager.notify(
             CoreAlertManager,
             "** (ArithmeticError) bad argument in arithmetic expression: 1 / 0\nsecond line3"
           ) == :ok

    assert %{message_buffer: buffer1, busy?: true} = get_handler_state(EmailHandler)
    assert MemoryInbox.get() == []

    # not to be ignored
    assert CoreAlertManager.notify(
             CoreAlertManager,
             "** (ArithmeticError) bad argument in arithmetic expression: 1 / 0\nsecond line4"
           ) == :ok

    assert %{message_buffer: buffer2, busy?: true} = get_handler_state(EmailHandler)

    assert [
             {time2,
              "** (ArithmeticError) bad argument in arithmetic expression: 1 / 0\nsecond line4"},
             {time1,
              "** (UndefinedFunctionError) function Hoge.foo/0 is undefined (module Hoge is not available)\nsecond line2"}
           ] = buffer2

    assert MemoryInbox.get() == []

    # After `fast_interval`, an alert that is not ignored is sent
    :timer.sleep(1_100)
    assert %{message_buffer: [], busy?: true} = get_handler_state(EmailHandler)
    assert [%Mail{to: ["test@example.com"], subject: subject1, body: body1}] = MemoryInbox.get()

    assert String.ends_with?(
             subject1,
             "** (UndefinedFunctionError) function Hoge.foo/0 is... [and other 1 error(s)]"
           )

    assert body1 ==
             """
             [#{Time.to_iso_timestamp(time1)}] ** (UndefinedFunctionError) function Hoge.foo/0 is undefined (module Hoge is not available)
             second line2


             [#{Time.to_iso_timestamp(time2)}] ** (ArithmeticError) bad argument in arithmetic expression: 1 / 0
             second line4


             """
  end

  defp update_handler_installations_and_mock_core_config_cache(alert_config) do
    assert CoreAlertManager.update_handler_installations(:antikythera, alert_config) == :ok
    :meck.expect(ConfigCache.Core, :read, fn -> %{alerts: alert_config} end)
  end

  defp get_handler_state(handler) do
    :sys.get_state(CoreAlertManager)
    |> Enum.find(&match?({_, ^handler, _}, &1))
    |> elem(2)
  end
end
