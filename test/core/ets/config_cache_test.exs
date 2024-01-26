# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Ets.ConfigCacheTest do
  use Croma.TestCase
  alias ConfigCache.Gear

  describe "ConfigCache.Gear.read/1" do
    # normal behaviors are tested in AntikytheraCore.Config.GearTest
    test "should raise CaseClauseError if :antikythera is given as gear name" do
      assert_raise CaseClauseError, fn ->
        Gear.read(:antikythera)
      end
    end
  end
end
