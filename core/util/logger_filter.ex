# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.LoggerFilter do
  @moduledoc """
  `:logger` primary filters that drop noisy OTP/SASL reports:

  - SASL progress reports (handled by the built-in `:logger_filters.progress/2`)
  - error log emitted by `:syn` about a mnesia down event (when a cluster node is terminated)
  - supervisor report on brutal kill of a worker process in `PoolSup`
    (when a too-long-running worker is stopped)

  Each filter returns `:stop` to drop the matching event and `:ignore` otherwise.
  """

  @doc "Drop the mnesia-down error spam emitted by `:syn` on node termination."
  def reject_mnesia_down(%{level: :error, msg: {format, _args}}, _extra) when is_list(format) do
    if List.starts_with?(format, ~c"Received a MNESIA down event"), do: :stop, else: :ignore
  end

  def reject_mnesia_down(_event, _extra), do: :ignore

  @doc "Drop supervisor `child_terminated` reports caused by PoolSup brutal kills."
  def reject_poolsup_kill(
        %{
          level: :error,
          msg: {:report, %{label: {:supervisor, :child_terminated}, report: report}}
        },
        _extra
      ) do
    case Keyword.get(report, :supervisor) do
      {_pid, PoolSup.Callback} -> :stop
      _otherwise -> :ignore
    end
  end

  def reject_poolsup_kill(_event, _extra), do: :ignore
end
