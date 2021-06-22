# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Ets.ConfigCacheTest do
  use Croma.TestCase
  alias ConfigCache.Gear

  describe "ConfigCache.Gear.read/1" do
    # normal behaviors are tested in AntikytheraCore.Config.GearTest
    test "should return :error if :antikythera is given as gear name" do
      assert Gear.read(:antikythera) == :error
    end
  end
end
