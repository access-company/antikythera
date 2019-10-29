# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Version.GearTest do
  use Croma.TestCase, alias_as: V

  defp all_messages_in_mailbox(acc \\ []) do
    receive do
      x -> all_messages_in_mailbox([x | acc])
    after
      0 -> acc
    end
  end

  defp set(l) do
    MapSet.new(l)
  end

  test "install_gears_whose_deps_met/3 should appropriately reorder gear installations according to their gear dependencies" do
    %{
      []                                                                         => [],
      [gear_a: set([]), gear_b: set([])]                                         => [],
      [gear_a: set([:gear_b]), gear_b: set([])]                                  => [],
      [gear_a: set([:gear_b, :gear_c]), gear_b: set([:gear_c]), gear_c: set([])] => [],
      [gear_a: set([:gear_b])]                                                   => [:gear_a],
      [gear_a: set([:gear_c]), gear_b: set([])]                                  => [:gear_a],
      [gear_a: set([:gear_b]), gear_b: set([:gear_c]), gear_c: set([:gear_a])]   => [:gear_a, :gear_b, :gear_c],
    } |> Enum.each(fn {pairs, gears_to_be_rejected} ->
      pairs_to_be_rejected = Enum.filter(pairs, fn {g, _} -> g in gears_to_be_rejected end)
      ret = V.install_gears_whose_deps_met(pairs, MapSet.new, fn g -> send(self(), g) end)
      assert set(ret)                       == set(pairs_to_be_rejected)
      assert set(all_messages_in_mailbox()) == set(Keyword.keys(pairs) -- gears_to_be_rejected)
    end)
  end

  test "auto_generated_module?" do
    refute V.auto_generated_module?(Antikythera.Time)
    assert V.auto_generated_module?(Croma.TypeGen.Nilable.Antikythera.Time)
  end
end
