# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.ExecutorPool.SettingTest do
  use Croma.TestCase
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.Config.Core, as: CoreConfig
  alias AntikytheraCore.Ets.ConfigCache.Core, as: CoreConfigCache
  alias AntikytheraCore.CoreConfigPoller
  alias AntikytheraCore.ExecutorPool.WsConnectionsCapping

  defp with_modified_core_config(conf, f) do
    orig = CoreConfigCache.read()
    CoreConfig.write(conf)
    GenServerHelper.send_message_and_wait(CoreConfigPoller, :timeout)
    try do
      f.()
    after
      CoreConfig.write(orig)
      GenServerHelper.send_message_and_wait(CoreConfigPoller, :timeout)
    end
  end

  test "should cap ws_max_connections based on available memory" do
    limit = WsConnectionsCapping.upper_limit()
    conf = %{gears: %{testgear: %{executor_pool: %{ws_max_connections: limit + 1}}}}
    with_modified_core_config(conf, fn ->
      s = Setting.of_gear(:testgear)
      assert s.ws_max_connections == limit
    end)
  end
end
