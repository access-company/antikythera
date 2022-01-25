# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Handler.CowboyRoutingTest do
  use Croma.TestCase

  describe "conflicts_with_default_domain?/2" do
    test "should return true when the given domain possibly conflicts with gear's default domain" do
      [
        dev: "antikytheradev.example.com",
        prod: "antikythera.example.com"
      ]
      |> Enum.each(fn {env, base_domain} ->
        assert CowboyRouting.conflicts_with_default_domain?("somegear.#{base_domain}", env)
        assert CowboyRouting.conflicts_with_default_domain?(":_.#{base_domain}", env)
      end)
    end

    test "should return false when the given domain won't conflict with gear's default domain" do
      refute CowboyRouting.conflicts_with_default_domain?("example.com", :dev)
      refute CowboyRouting.conflicts_with_default_domain?("somegear.example.com", :dev)
      refute CowboyRouting.conflicts_with_default_domain?(":_.example.com", :dev)
    end
  end
end
