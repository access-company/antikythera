# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.UsageReporter do
  @moduledoc """
  A `GenServer` that periodically fetches usage of executor pool and submits it.

  Depends on
  - `AntikytheraCore.MetricsUploader` process for antikythera
  - `PoolSup.Multi` process for action runners in the same executor pool
  - `PoolSup` process for async job runners in the same executor pool
  - `AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter` process in the same executor pool
  """

  use GenServer
  alias Antikythera.Metrics.DataList
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.MetricsUploader
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName
  alias AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter

  @interval 60_000

  @typep usage_rational :: {non_neg_integer, non_neg_integer}

  def start_link([uploader_name, epool_id]) do
    GenServer.start_link(__MODULE__, {uploader_name, epool_id}, [])
  end

  @impl true
  def init({uploader_name, epool_id}) do
    {:ok, %{uploader_name: uploader_name, epool_id: epool_id}, @interval}
  end

  @impl true
  def handle_info(:timeout, %{uploader_name: uploader_name, epool_id: epool_id} = state) do
    MetricsUploader.submit(uploader_name, make_metrics_list(epool_id), epool_id)
    {:noreply, state, @interval}
  end

  defunp make_metrics_list(epool_id :: v[EPoolId.t()]) :: DataList.t() do
    {working_a, max_a} = fetch_usage_action(epool_id)
    {working_j, max_j} = fetch_usage_job(epool_id)

    %{count: count_ws, max: max_ws, rejected: rejected_ws} =
      WebsocketConnectionsCounter.stats(epool_id)

    List.flatten([
      count_and_ratio("epool_working_action_runner", working_a, max_a),
      count_and_ratio("epool_working_job_runner", working_j, max_j),
      count_and_ratio("epool_websocket_connections", count_ws, max_ws),
      {"epool_websocket_rejected_count", :gauge, rejected_ws}
    ])
  end

  defunp fetch_usage_action(epool_id :: v[EPoolId.t()]) :: usage_rational do
    name_action = RegName.action_runner_pool_multi(epool_id)

    picked_pool =
      Supervisor.which_children(name_action)
      |> Enum.map(fn {_, pid, _, _} -> pid end)
      |> Enum.random()

    PoolSup.status(picked_pool) |> extract()
  end

  defunp fetch_usage_job(epool_id :: v[EPoolId.t()]) :: usage_rational do
    name_job = RegName.async_job_runner_pool(epool_id)
    PoolSup.status(name_job) |> extract()
  end

  defunp extract(%{reserved: r, ondemand: o, working: w}) :: usage_rational do
    {w, r + o}
  end

  defp count_and_ratio(label, n, 0), do: [{label <> "_count", :gauge, n}]

  defp count_and_ratio(label, n, d),
    do: [{label <> "_count", :gauge, n}, {label <> "_%", :gauge, 100 * n / d}]
end
