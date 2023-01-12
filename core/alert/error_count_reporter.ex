# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Alert.ErrorCountReporter do
  @buffering_interval 60_000

  @moduledoc """
  `:gen_event` callback module that reports number of errors to `AntikytheraCore.ErrorCountsAccumulator` process.

  This event handler module is installed in all `AntikytheraCore.Alert.Manager` processes.
  The received alerts are buffered for #{@buffering_interval} milliseconds and then reported in one batch.
  """

  @behaviour :gen_event
  alias AntikytheraCore.ErrorCountsAccumulator

  @impl true
  def init(otp_app_name) do
    {:ok, %{otp_app_name: otp_app_name, count: 0, timer: nil}}
  end

  @impl true
  def handle_event(_message, %{count: count, timer: timer} = state) do
    new_state =
      case timer do
        nil -> %{state | count: count + 1, timer: start_timer()}
        _ -> %{state | count: count + 1}
      end

    {:ok, new_state}
  end

  @impl true
  def handle_info(
        :error_count_reporter_timeout,
        %{otp_app_name: otp_app_name, count: count} = state
      ) do
    ErrorCountsAccumulator.submit(otp_app_name, count)
    {:ok, %{state | count: 0, timer: nil}}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  defunp start_timer() :: reference do
    Process.send_after(self(), :error_count_reporter_timeout, @buffering_interval)
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
