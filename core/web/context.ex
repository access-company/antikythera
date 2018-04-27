# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Context do
  alias SolomonLib.{Time, GearName}
  alias SolomonLib.Context, as: LContext
  alias SolomonLib.Context.GearEntryPoint
  alias SolomonLib.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Cluster.NodeId

  defun make(gear_name   :: v[GearName.t],
             entry_point :: v[nil | GearEntryPoint.t],
             context_id  :: v[nil | String.t] \\ nil,
             epool_id    :: v[nil | EPoolId.t] \\ nil) :: LContext.t do
    now = Time.now()
    %LContext{
      start_time:       now,
      context_id:       context_id || make_context_id(now),
      gear_name:        gear_name,
      executor_pool_id: epool_id,
      gear_entry_point: entry_point,
    }
  end

  defun make_context_id(t :: v[Time.t]) :: String.t do
    [
      timestamp(t),
      NodeId.get(),
      :erlang.pid_to_list(self()) |> tl() |> List.to_string() |> String.trim_trailing(">"),
    ] |> Enum.join("_")
  end

  defunp timestamp({_, {y, mon, d}, {h, minute, s}, ms} :: Time.t) :: String.t do
    import SolomonLib.StringFormat
    "#{y}#{pad2(mon)}#{pad2(d)}-#{pad2(h)}#{pad2(minute)}#{pad2(s)}.#{pad3(ms)}"
  end
end
