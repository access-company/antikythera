# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.TimedJobStarter do
  @moduledoc """
  A `GenServer` to periodically send command to the leader process of the corresponding async job queue.

  Purposes of the command are twofold:
  - to trigger executions of scheduled jobs that have become runnable, and
  - to get metrics from the queue.

  The interaction between this `GenServer` and the leader is meaningful only when the leader resides in the same node.
  """

  use GenServer
  alias Antikythera.Metrics.DataList
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.AsyncJob.Queue
  alias AntikytheraCore.MetricsUploader

  # Although async jobs are scheduled in minutes, we use a time interval shorter than 60s
  # in order not to skip job executions in an undesirable manner.
  # As an example, suppose a job is scheduled with "* * * * *" (every minute).
  # If we'd use 60s interval, an execution of the job for 00:00:00 could start at around 00:00:59.
  # Then if the execution finished at 00:01:00, the next execution time would be 00:02:00, missing an execution for 00:01:00.
  # We use 30s here instead of 60s; an execution for 00:00:00 is started by 00:00:30 at the latest
  # (as long as there are available worker processes in the cluster).
  @interval 30_000

  def child_spec(args) do
    %{
      id:    __MODULE__,
      start: {__MODULE__, :start_link, args},
    }
  end

  defun start_link(queue_name :: v[atom], uploader_name :: v[atom | pid], epool_id :: v[EPoolId.t]) :: GenServer.on_start do
    GenServer.start_link(__MODULE__, {queue_name, uploader_name, epool_id})
  end

  @impl true
  def init({queue_name, uploader_name, epool_id}) do
    {:ok, %{queue_name: queue_name, uploader_name: uploader_name, epool_id: epool_id}, 0}
  end

  @impl true
  def handle_info(:timeout, state) do
    send_command(state)
    {:noreply, state, @interval}
  end
  def handle_info(_, state) do
    # neglect other message (possibly a delayed reply from the queue)
    {:noreply, state, @interval}
  end

  defunp send_command(%{queue_name: queue_name} = state) :: :ok do
    case Process.whereis(queue_name) do
      nil -> :ok
      pid ->
        case Queue.start_jobs_and_get_metrics(pid) do
          nil     -> :ok
          metrics -> report_metrics(state, metrics)
        end
    end
  end

  defunp report_metrics(%{uploader_name: uploader_name, epool_id: epool_id}, metrics :: v[tuple]) :: :ok do
    # We are sending the metrics data multiple times a minute.
    # Within each minute, based on the `:gauge` strategy, only the last-received numbers are used
    # and the others are discarded by `MetricsUploader`.
    # Currently we always send metrics data regardless of whether the data will be discarded or not.
    MetricsUploader.submit(uploader_name, construct_metrics_data_list(metrics), epool_id)
  end

  defunp construct_metrics_data_list({n_jobs_waiting, n_jobs_runnable, n_jobs_running, n_brokers_waiting}) :: DataList.t do
    [
      {"epool_waiting_job_count"   , :gauge, n_jobs_waiting   },
      {"epool_runnable_job_count"  , :gauge, n_jobs_runnable  },
      {"epool_running_job_count"   , :gauge, n_jobs_running   },
      {"epool_waiting_broker_count", :gauge, n_brokers_waiting},
    ]
  end
end
