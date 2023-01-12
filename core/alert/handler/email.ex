# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.Handler.Email do
  @default_errors_per_body 3

  @moduledoc """
  Alert handler implementation that sends an email.

  This is considered the default alert backend (and also used for testing of `AntikytheraCore.Alert.Manager`).
  Email delivery method is provided by a callback module of `AntikytheraEal.AlertMailer.Behaviour`.

  ## Handler config

  - `to` - Required. List of email addresses to be sent. Must not be an empty list.
  - `errors_per_body` - Optional. Integer number of errors printed in body of an alert mail.
    Details of errors beyond this threshold will be omitted.
    Defaults to #{@default_errors_per_body}.
  """

  alias Antikythera.{Email, Time, Env}
  alias AntikytheraCore.Cluster.NodeId
  alias AntikytheraCore.Alert.HandlerConfig
  alias AntikytheraEal.AlertMailer, as: AM

  @behaviour AntikytheraCore.Alert.Handler

  @from Application.fetch_env!(:antikythera, :alert) |> get_in([:email, :from])
  if !Email.valid?(@from) do
    raise "please set a valid email address in application config (as nested keyword list of `[:alert, :email, :from]`)"
  end

  @impl true
  def send_alerts([], _, _) do
    []
  end

  def send_alerts(messages, %{"to" => to} = handler_config, otp_app_name) do
    epb =
      case Map.get(handler_config, "errors_per_body") do
        int when is_integer(int) -> int
        _anything_else -> @default_errors_per_body
      end

    mail = %AM.Mail{
      from: @from,
      to: to,
      subject: subject(messages, otp_app_name),
      body: body(messages, epb)
    }

    # just spawn and forget, since async/await handling in :gen_event handler is cumbersome
    _ = spawn(AM, :deliver, [mail])
    []
  end

  defp subject([{_time, body}], otp_app_name), do: tag(otp_app_name) <> headline(body)

  defp subject(messages, otp_app_name) do
    [{_time, body} | tl] = messages
    "#{tag(otp_app_name)}#{headline(body)} [and other #{length(tl)} error(s)]"
  end

  defp tag(otp_app_name) do
    "<ALERT>[#{otp_app_name}][#{Env.runtime_env()}][#{NodeId.get()}] "
  end

  defp body(messages, errors_per_body) do
    {messages_with_full_body, messages_without_full_body} = Enum.split(messages, errors_per_body)

    Enum.join([
      Enum.map(messages_with_full_body, fn {t, b} -> time_body(t, b) end),
      Enum.map(messages_without_full_body, fn {t, b} -> time_headline(t, b) end)
    ])
  end

  defp time_headline(time, body), do: "[#{Time.to_iso_timestamp(time)}] #{headline(body)}\n"

  defp time_body(time, body), do: "[#{Time.to_iso_timestamp(time)}] #{body}\n\n\n"

  defp headline(body) do
    body
    |> truncate_by_length(50)
    |> String.split("\n", parts: 2)
    |> hd()
  end

  defp truncate_by_length(str, length) do
    case String.split_at(str, length) do
      {head_str, ""} -> head_str
      {head_str, _tail_str} -> head_str <> "..."
    end
  end

  @impl true
  defun validate_config(config :: HandlerConfig.t()) :: boolean do
    %{"to" => [_ | _] = addresses} -> addresses_valid?(addresses)
    _ -> false
  end

  defp addresses_valid?(addresses) do
    Enum.all?(addresses, &Email.valid?/1)
  end
end
