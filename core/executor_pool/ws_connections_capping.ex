# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.WsConnectionsCapping do
  alias AntikytheraCore.OsUtil
  alias AntikytheraCore.ExecutorPool.{Setting, TenantSetting}

  # The following constants are heuristic values, not rigorously determined ones.
  # (Should we make them mix config items?)
  @ratio_of_max_memory_occupation_by_ws_connections_in_1_epool 0.7
  @ws_connections_per_megabytes 5

  defun cap_based_on_available_memory(setting :: setting) :: setting
        when setting: Setting.t() | TenantSetting.t() do
    connections = min(setting.ws_max_connections, upper_limit())
    %{setting | ws_max_connections: connections}
  end

  defpt upper_limit() do
    usable_bytes =
      trunc(
        OsUtil.total_memory_size_in_bytes() *
          @ratio_of_max_memory_occupation_by_ws_connections_in_1_epool
      )

    div(usable_bytes, 1_000_000) * @ws_connections_per_megabytes
  end
end
