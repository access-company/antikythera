# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.AsyncJob.RaftedValueConfigMaker do
  @behaviour RaftFleet.RaftedValueConfigMaker

  @options [
    heartbeat_timeout:                   1_000,
    election_timeout:                    5_000,
    election_timeout_clock_drift_margin:   500,
  ]
  defun options() :: Keyword.t, do: @options

  @impl true
  defun make(name :: v[atom]) :: RaftedValue.Config.t do
    case name do
      RaftFleet.Cluster -> RaftFleet.Cluster.make_rv_config(@options)
      _job_queue_name   -> AntikytheraCore.AsyncJob.Queue.make_rv_config(@options)
    end
  end
end
