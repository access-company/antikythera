# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.Message do
  use Croma.SubtypeOfTuple, elem_modules: [Antikythera.Time, Croma.String]
end

defmodule AntikytheraCore.Alert.HandlerState do
  alias AntikytheraCore.Alert.Message

  use Croma.Struct,
    recursive_new?: true,
    fields: [
      handler_module: Croma.Atom,
      otp_app_name: Croma.Atom,
      # Newest first
      message_buffer: Croma.TypeGen.list_of(Message),
      busy?: Croma.Boolean
    ]
end

defmodule AntikytheraCore.Alert.Handler do
  @default_fast_interval 60
  @default_delayed_interval 1_800
  @fast_interval_key "fast_interval"
  @delayed_interval_key "delayed_interval"
  @ignore_patterns_key "ignore_patterns"

  @moduledoc """
  Behaviour module for alert handlers.

  Implementations must be prefixed with `AntikytheraCore.Alert.Handler`, e.g. `AntikytheraCore.Alert.Handler.Email`.
  This module also implements `:gen_event` behaviour and installed as handlers for `AntikytheraCore.Alert.Manager` processes.
  Each installed handlers will call callbacks of their corresponding implementation modules (references to those modules are held in handler states).

  A simple buffering/throttling mechanism is built in.

  - Messages received by handlers will be sent out in "fast-then-delayed" pattern:
      - Occasional messages will be flushed from the buffer and sent out in `fast_interval`.
      - Messages arriving too frequently will be buffered for `delayed_interval` until they are sent out.
  - By default, `fast_interval` is #{@default_fast_interval} seconds
    and `delayed_interval` is #{@default_delayed_interval} seconds.
      - They can be customized via core/gear configs.
        Specify #{@fast_interval_key} or #{@delayed_interval_key} for the handler.

  ## Customization and installation of handlers

  Through `validate_config/1` callback, `handler_config` will be validated
  whether it includes sufficient information required for the implementation.
  If the validation passed, a handler, with a reference to the implementation module, will be installed for that OTP application.
  If the validation failed, the handler will not be installed, and will be uninstalled if it is installed already.

  This means, customization and installation are purely done via core/gear config.
  """

  @behaviour :gen_event
  alias Antikythera.GearName
  alias AntikytheraCore.Alert.{Manager, Message, HandlerState, HandlerConfig}

  @doc """
  Send alert(s) for messages in the buffer, using `handler_config`. Summarize messages if needed.
  Must return messages which could not be sent for whatever reason for retry.
  Oldest message comes first in `messages`, same goes for returned messages.

  Note: If the handler is trying to perform alerts which can take some time to finish (e.g. send email),
  consider dispatching them to a temporary process.
  In that case though, results of alerts cannot be received (`[]` should always be returned).
  """
  @callback send_alerts(
              messages :: [Message.t()],
              handler_config :: HandlerConfig.t(),
              otp_app_name :: :antikythera | GearName.t()
            ) :: [Message.t()]

  @doc """
  Validate `handler_config` whether it includes sufficient configurations for the handler.
  Return `true` when it is valid.
  """
  @callback validate_config(handler_config :: HandlerConfig.t()) :: boolean

  @impl true
  def init({otp_app_name, handler}) do
    {:ok,
     %HandlerState{
       handler_module: handler,
       otp_app_name: otp_app_name,
       message_buffer: [],
       busy?: false
     }}
  end

  @impl true
  def handle_event(
        message,
        %HandlerState{
          busy?: busy?,
          message_buffer: buffer,
          otp_app_name: otp_app_name,
          handler_module: handler
        } = handler_state
      ) do
    handler_config = HandlerConfig.get(handler, otp_app_name)
    ignore_patterns = ignore_patterns(handler_config)
    ignore_message? = ignore_message?(message, ignore_patterns)
    new_buffer = if ignore_message?, do: buffer, else: [message | buffer]

    if busy? or ignore_message? do
      {:ok, %HandlerState{handler_state | message_buffer: new_buffer}}
    else
      schedule_handler_timeout(handler, handler_config, %{
        handler_state
        | message_buffer: new_buffer
      })
    end
  end

  @impl true
  def handle_info(
        {:handler_timeout, handler},
        %HandlerState{
          handler_module: handler,
          otp_app_name: otp_app_name,
          message_buffer: buffer0
        } = handler_state
      ) do
    case buffer0 do
      [] ->
        {:ok, %{handler_state | busy?: false}}

      messages ->
        handler_config = HandlerConfig.get(handler, otp_app_name)

        buffer1 =
          messages
          |> Enum.reverse()
          |> handler.send_alerts(handler_config, otp_app_name)
          |> Enum.reverse()

        schedule_handler_timeout(handler, handler_config, %{
          handler_state
          | message_buffer: buffer1
        })
    end
  end

  def handle_info(_msg, handler_state) do
    {:ok, handler_state}
  end

  defunp schedule_handler_timeout(
           handler :: v[atom],
           handler_config :: v[map],
           %HandlerState{busy?: busy?} = handler_state
         ) :: {:ok, HandlerState.t()} do
    if busy? do
      Manager.schedule_handler_timeout(handler, delayed_interval(handler_config))
      {:ok, handler_state}
    else
      Manager.schedule_handler_timeout(handler, fast_interval(handler_config))
      {:ok, %HandlerState{handler_state | busy?: true}}
    end
  end

  defp ignore_message?({_time, body}, ignore_patterns) do
    Enum.map(ignore_patterns, &Regex.compile!/1)
    |> Enum.any?(&Regex.match?(&1, body))
  end

  defp fast_interval(handler_config) do
    case Map.get(handler_config, @fast_interval_key) do
      num when is_integer(num) and num > 0 -> num
      _ -> @default_fast_interval
    end
  end

  defp delayed_interval(handler_config) do
    case Map.get(handler_config, @delayed_interval_key) do
      num when is_integer(num) and num > 0 -> num
      _ -> @default_delayed_interval
    end
  end

  defp ignore_patterns(handler_config) do
    case Map.get(handler_config, @ignore_patterns_key) do
      patterns when is_list(patterns) -> patterns
      _ -> []
    end
  end

  #
  # irrelevant gen_event callbacks
  #
  @impl true
  def handle_call(_msg, state) do
    {:ok, {:error, :unexpected_call}, state}
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
