# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.SystemMetricsReporter do
  @moduledoc """
  A `GenServer` that periodically submit metrics about the ErlangVM.

  Note that some values obtained from `:erlang.statistics/1` are cumulative; we have to take diff from the previous values.

  - reductions
  - bytes_in
  - bytes_out
  - gc_count
  - gc_words_reclaimed
  """

  use GenServer
  alias Antikythera.Metrics.DataList
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.MetricsUploader
  alias AntikytheraCore.Vm
  require AntikytheraCore.Logger, as: L

  @log_message_queue_length 100_000
  @interval 300_000
  @typep metrics_t :: [{String.t(), non_neg_integer}]

  def start_link([uploader_name]) do
    GenServer.start_link(__MODULE__, uploader_name, [])
  end

  @impl true
  def init(uploader_name) do
    state = %{uploader_name: uploader_name, prev_metrics: fetch_cumulative_metrics()}
    {:ok, state, @interval}
  end

  @impl true
  def handle_info(:timeout, %{uploader_name: uploader_name, prev_metrics: prev_metrics} = state) do
    new_metrics = fetch_cumulative_metrics()

    MetricsUploader.submit(
      uploader_name,
      calc_metrics_data(prev_metrics, new_metrics),
      EPoolId.nopool()
    )

    {:noreply, %{state | prev_metrics: new_metrics}, @interval}
  end

  defunp fetch_cumulative_metrics() :: metrics_t do
    # Although `:erlang.statistics(:reductions)` also returns a diff since last call, we don't use it
    # since remote_console activities can disturb the value.
    {reductions, _diff} = :erlang.statistics(:reductions)
    {{:input, bytes_in}, {:output, bytes_out}} = :erlang.statistics(:io)
    {gc_count, gc_words_reclaimed, _} = :erlang.statistics(:garbage_collection)

    [
      {"vm_reductions", reductions},
      {"vm_bytes_in", bytes_in},
      {"vm_bytes_out", bytes_out},
      {"vm_gc_count", gc_count},
      {"vm_gc_words_reclaimed", gc_words_reclaimed}
    ]
  end

  defunp calc_metrics_data(old_metrics :: metrics_t, new_metrics :: metrics_t) :: DataList.t() do
    memory_kw = :erlang.memory()
    log_too_many_messages_processes()

    absolute_values = [
      {"vm_messages_in_mailboxes", Vm.count_messages_in_all_mailboxes()},
      {"vm_process_count", :erlang.system_info(:process_count)},
      {"vm_total_run_queue_lengths", :erlang.statistics(:total_run_queue_lengths)},
      {"vm_total_active_tasks", :erlang.statistics(:total_active_tasks)},
      {"vm_memory_total", Keyword.fetch!(memory_kw, :total)},
      {"vm_memory_proc", Keyword.fetch!(memory_kw, :processes_used)},
      {"vm_memory_atom", Keyword.fetch!(memory_kw, :atom_used)},
      {"vm_memory_binary", Keyword.fetch!(memory_kw, :binary)},
      {"vm_memory_ets", Keyword.fetch!(memory_kw, :ets)}
    ]

    cumulative_values =
      Enum.zip(old_metrics, new_metrics)
      |> Enum.map(fn {{label, old_value}, {_label, new_value}} ->
        {label, new_value - old_value}
      end)

    Enum.map(absolute_values ++ cumulative_values, fn {label, value} -> {label, :gauge, value} end)
  end

  defp log_too_many_messages_processes() do
    ps = :recon.proc_count(:message_queue_len, 5)
    [{_pid, top_len, _info} | _] = ps

    if top_len >= @log_message_queue_length do
      L.error(
        "There are process(es) with more than or equal to #{@log_message_queue_length} messages."
      )

      Enum.each(ps, fn {pid, len, _info} ->
        if len >= @log_message_queue_length do
          pid |> :recon.info() |> inspect() |> L.error()
        end
      end)
    end
  end
end
