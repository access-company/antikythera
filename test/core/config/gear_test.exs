# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Config.GearTest do
  use Croma.TestCase
  alias Antikythera.Test.GenServerHelper
  alias AntikytheraCore.GearLog.Level
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Ets.ConfigCache.Gear, as: Cache

  @gear1_conf %Gear{
    kv: %{"foo" => "bar1"},
    domains: ["my.domain.com", ":_.wildcard.domain.com"],
    log_level: Level.default(),
    alerts: %{}
  }
  @gear2_conf %Gear{kv: %{"foo" => "bar2"}, domains: [], log_level: Level.default(), alerts: %{}}

  test "apply_changes/1 should put cache into ETS and return whether any domains changed" do
    assert Cache.read(:gear1) == nil
    assert Cache.read(:gear2) == nil
    refute Gear.apply_changes([])
    assert Cache.read(:gear1) == nil
    assert Cache.read(:gear2) == nil
    assert Gear.apply_changes(gear1: @gear1_conf)
    assert Cache.read(:gear1) == @gear1_conf
    assert Cache.read(:gear2) == nil
    refute Gear.apply_changes(gear1: @gear1_conf)
    assert Cache.read(:gear1) == @gear1_conf
    assert Cache.read(:gear2) == nil
    refute Gear.apply_changes(gear2: @gear2_conf)
    assert Cache.read(:gear1) == @gear1_conf
    assert Cache.read(:gear2) == @gear2_conf
    refute Gear.apply_changes(gear1: @gear1_conf, gear2: @gear2_conf)
    assert Cache.read(:gear1) == @gear1_conf
    assert Cache.read(:gear2) == @gear2_conf

    :ets.delete(ConfigCache.table_name(), :gear1)
    :ets.delete(ConfigCache.table_name(), :gear2)
  end

  test "apply_changes/1 should report change in log level to Logger" do
    fake_logger_name = Gear1.Logger
    Process.register(self(), fake_logger_name)

    conf = %Gear{Gear.default() | log_level: :error}
    refute Gear.apply_changes(gear1: conf)
    assert GenServerHelper.receive_cast_message() == {:set_min_level, :error}

    :ets.delete(ConfigCache.table_name(), :gear1)
    Process.unregister(fake_logger_name)
  end
end
