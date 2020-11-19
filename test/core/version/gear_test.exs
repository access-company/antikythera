# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

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

  setup do
    on_exit(fn ->
      :meck.unload()
    end)
  end

  describe "install_gears_whose_deps_met/3" do
    test "should appropriately reorder gear installations according to their gear dependencies" do
      %{
        [] => [],
        [gear_a: set([]), gear_b: set([])] => [],
        [gear_a: set([:gear_b]), gear_b: set([])] => [],
        [gear_a: set([:gear_b, :gear_c]), gear_b: set([:gear_c]), gear_c: set([])] => [],
        [gear_a: set([:gear_b])] => [:gear_a],
        [gear_a: set([:gear_c]), gear_b: set([])] => [:gear_a],
        [gear_a: set([:gear_b]), gear_b: set([:gear_c]), gear_c: set([:gear_a])] => [
          :gear_a,
          :gear_b,
          :gear_c
        ]
      }
      |> Enum.each(fn {pairs, gears_to_be_rejected} ->
        pairs_to_be_rejected = Enum.filter(pairs, fn {g, _} -> g in gears_to_be_rejected end)

        {ret, num_failed_install} =
          V.install_gears_whose_deps_met(pairs, MapSet.new(), 0, fn g ->
            send(self(), g)
            :ok
          end)

        assert set(ret) == set(pairs_to_be_rejected)
        assert num_failed_install == 0
        assert set(all_messages_in_mailbox()) == set(Keyword.keys(pairs) -- gears_to_be_rejected)
      end)
    end

    test "should return number of failed to install gears" do
      pairs = [gear_a: set([]), gear_b: set([]), gear_c: set([])]
      failed_to_install_gear = :gear_b

      {ret, num_failed_install} =
        V.install_gears_whose_deps_met(pairs, MapSet.new(), 0, fn g ->
          if g == failed_to_install_gear do
            :error
          else
            :ok
          end
        end)

      assert Enum.empty?(ret)
      assert num_failed_install == 1
    end

    test "should reject if it failed to install depending gears" do
      pairs = [gear_a: set([:gear_b]), gear_b: set([]), gear_c: set([])]
      failed_to_install_gear = :gear_b
      gears_to_be_rejected = [:gear_a]
      pairs_to_be_rejected = Enum.filter(pairs, fn {g, _} -> g in gears_to_be_rejected end)

      {ret, num_failed_install} =
        V.install_gears_whose_deps_met(pairs, MapSet.new(), 0, fn g ->
          if g == failed_to_install_gear do
            :error
          else
            :ok
          end
        end)

      assert set(ret) == set(pairs_to_be_rejected)
      assert num_failed_install == 1
    end
  end

  test "auto_generated_module?" do
    refute V.auto_generated_module?(Antikythera.Time)
    assert V.auto_generated_module?(Croma.TypeGen.Nilable.Antikythera.Time)
  end

  describe "install_gears_at_startup/1" do
    test "should return :ok if most gears are installed" do
      gears = [:gear1, :gear2, :gear3]
      pairs_not_installed = []
      num_failed_to_install = 0

      :meck.expect(AntikytheraCore.Version.Gear, :gear_dependencies_from_app_file, fn _gear_name,
                                                                                      _known_gear_names ->
        MapSet.new()
      end)

      :meck.expect(
        AntikytheraCore.Version.Gear,
        :install_gears_whose_deps_met,
        fn _gear_and_deps_pairs, _installed_gears_set, _f, _num_failed_install ->
          {pairs_not_installed, num_failed_to_install}
        end
      )

      assert V.do_install_gears_at_startup(gears) == :ok
    end

    test "should return :error if most gears are not installed" do
      gears = [:gear1, :gear2, :gear3]
      pairs_not_installed = [gear1: set([]), gear2: set([])]
      num_failed_to_install = 0

      :meck.expect(AntikytheraCore.Version.Gear, :gear_dependencies_from_app_file, fn _gear_name,
                                                                                      _known_gear_names ->
        MapSet.new()
      end)

      :meck.expect(
        AntikytheraCore.Version.Gear,
        :install_gears_whose_deps_met,
        fn _gear_and_deps_pairs, _installed_gears_set, _f, _num_failed_install ->
          {pairs_not_installed, num_failed_to_install}
        end
      )

      assert V.do_install_gears_at_startup(gears) == :error
    end

    test "should return :error if most gears are failed to install" do
      gears = [:gear1, :gear2, :gear3]
      pairs_not_installed = []
      num_failed_to_install = 2

      :meck.expect(AntikytheraCore.Version.Gear, :gear_dependencies_from_app_file, fn _gear_name,
                                                                                      _known_gear_names ->
        MapSet.new()
      end)

      :meck.expect(
        AntikytheraCore.Version.Gear,
        :install_gears_whose_deps_met,
        fn _gear_and_deps_pairs, _installed_gears_set, _f, _num_failed_install ->
          {pairs_not_installed, num_failed_to_install}
        end
      )

      assert V.do_install_gears_at_startup(gears) == :error
    end

    test "should return :error if half of gears are not installed" do
      gears = [:gear1, :gear2, :gear3, :gear4]
      pairs_not_installed = [gear1: set([]), gear2: set([])]
      num_failed_to_install = 0

      :meck.expect(AntikytheraCore.Version.Gear, :gear_dependencies_from_app_file, fn _gear_name,
                                                                                      _known_gear_names ->
        MapSet.new()
      end)

      :meck.expect(
        AntikytheraCore.Version.Gear,
        :install_gears_whose_deps_met,
        fn _gear_and_deps_pairs, _installed_gears_set, _f, _num_failed_install ->
          {pairs_not_installed, num_failed_to_install}
        end
      )

      assert V.do_install_gears_at_startup(gears) == :error
    end

    test "should return :error if 0 gear is installable" do
      gears = []
      pairs_not_installed = []
      num_failed_to_install = 0

      :meck.expect(AntikytheraCore.Version.Gear, :gear_dependencies_from_app_file, fn _gear_name,
                                                                                      _known_gear_names ->
        MapSet.new()
      end)

      :meck.expect(
        AntikytheraCore.Version.Gear,
        :install_gears_whose_deps_met,
        fn _gear_and_deps_pairs, _installed_gears_set, _f, _num_failed_install ->
          {pairs_not_installed, num_failed_to_install}
        end
      )

      assert V.do_install_gears_at_startup(gears) == :error
    end
  end
end
