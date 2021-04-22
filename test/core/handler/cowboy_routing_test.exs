# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Handler.CowboyRoutingTest do
  use Croma.TestCase

  describe "base_domain/1" do
    test "should return the pre-configured domain based on the given environment" do
      assert CowboyRouting.base_domain(:dev) == "antikytheradev.example.com"
      assert CowboyRouting.base_domain(:prod) == "antikythera.example.com"
    end
  end
end
