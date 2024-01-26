# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.MetricsUploader do
  @moduledoc """
  A `GenServer` which buffers metrics data and periodically flushes the aggregated results to stable storage.
  """

  use GenServer
  alias Antikythera.{Time, Context}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias Antikythera.Metrics.DataList
  alias AntikytheraCore.Metrics.{Buffer, Results, AggregateStrategy}
  alias AntikytheraEal.MetricsStorage, as: Storage
  require AntikytheraCore.Logger, as: L

  @flush_interval_base 60_000
  @flush_interval_rand_max 5_000

  def start_link([otp_app_name, name_to_register]) do
    GenServer.start_link(__MODULE__, otp_app_name, name: name_to_register)
  end

  @impl true
  def init(otp_app_name) do
    arrange_next_data_flushing()
    {:ok, %{otp_app_name: otp_app_name, buffer: Buffer.new(), results_to_resend: Results.new()}}
  end

  @impl true
  def handle_cast({now, metrics_data_list, epool_id}, %{buffer: buffer} = state) do
    new_buffer = Buffer.add(buffer, now, metrics_data_list, epool_id)
    {:noreply, %{state | buffer: new_buffer}}
  end

  @impl true
  def handle_info(:flush_data, state) do
    arrange_next_data_flushing()
    {:noreply, flush_data(state, Time.now())}
  end

  def handle_info(msg, state) do
    # On rare occasions MetricsUploader receives a message by :ssl module due to timeout in hackney, and it shouldn't trigger alert.
    L.info("received an unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp arrange_next_data_flushing() do
    # Add slight randomness to prevent many MetricsUploader processes from sending metrics at the same time
    flush_interval = @flush_interval_base + :rand.uniform(@flush_interval_rand_max)
    Process.send_after(self(), :flush_data, flush_interval)
  end

  @impl true
  def terminate(_reason, state) do
    # use future time to flush all existing metrics data
    one_minute_after = Time.shift_minutes(Time.now(), 1)
    flush_data(state, one_minute_after)
  end

  defp flush_data(
         %{otp_app_name: otp_app_name, buffer: buffer, results_to_resend: results_to_resend} =
           state,
         now
       ) do
    {new_buffer, past_data} = Buffer.partition_ongoing_and_past(buffer, now)
    past_results = Results.compute_results(past_data)
    results_to_send = Results.merge(results_to_resend, past_results)
    new_results_to_resend = Storage.save(otp_app_name, results_to_send)

    if !Enum.empty?(new_results_to_resend) do
      L.info("app=#{otp_app_name} incomplete upload, will retry afterward")
    end

    %{state | buffer: new_buffer, results_to_resend: new_results_to_resend}
  end

  #
  # Public API
  #
  defun submit_with_time(
          worker_name :: GenServer.server(),
          now :: v[Time.t()],
          data_list :: v[DataList.t()],
          epool_id :: Buffer.epool_id()
        ) :: :ok do
    data_list2 =
      Enum.map(data_list, fn {n, s, v} -> {n, AggregateStrategy.name_to_module(s), v} end)

    GenServer.cast(worker_name, {now, data_list2, epool_id})
  end

  defun submit(
          worker_name :: GenServer.server(),
          data_list :: v[DataList.t()],
          epool_id :: Buffer.epool_id()
        ) :: :ok do
    submit_with_time(worker_name, Time.now(), data_list, epool_id)
  end

  defun submit_custom_metrics(
          worker_name :: GenServer.server(),
          data_list0 :: v[DataList.t()],
          context :: v[nil | Context.t()]
        ) :: :ok do
    data_list1 = add_prefix_to_labels(data_list0)

    case context do
      %Context{executor_pool_id: epool_id} when is_tuple(epool_id) ->
        submit(worker_name, data_list1, epool_id)

      _no_context_or_no_epool ->
        submit(worker_name, data_list1, EPoolId.nopool())
    end
  end

  defunp add_prefix_to_labels(data_list :: v[DataList.t()]) :: DataList.t() do
    Enum.map(data_list, fn {label, strategy, value} ->
      {"custom_#{label}", strategy, value}
    end)
  end
end
