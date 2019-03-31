# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Version.HistoryTest do
  use Croma.TestCase
  alias Antikythera.Time
  alias AntikytheraCore.Version.History.Entry
  alias AntikytheraCore.Cluster

  @v1   "0.0.1-20180501235959+0123456789abcdef0123456789abcdef01234567"
  @v2   Version.parse!(@v1) |> Map.update!(:patch, &(&1 + 1)) |> to_string()
  @v3   Version.parse!(@v2) |> Map.update!(:patch, &(&1 + 1)) |> to_string()
  @v4   Version.parse!(@v3) |> Map.update!(:patch, &(&1 + 1)) |> to_string()
  @host Cluster.node_to_host(Node.self())

  defp make_line_patterns(v) do
    now = Time.now()
    t1  = now |> Time.shift_minutes(-1) |> Time.to_iso_timestamp()
    t2  = now |> Time.shift_minutes( 1) |> Time.to_iso_timestamp()
    [
      {v                            , true , true , false},
      {"#{v} canary=#{@host}"       , false, true , true },
      {"#{v} canary=other.host"     , false, false, true },
      {"#{v} noupgrade"             , true , false, false},
      {"#{v} noupgrade_canary=#{t1}", false, false, true },
      {"#{v} noupgrade_canary=#{t2}", true , false, true },
    ]
  end

  test "Entry should recognize the format of line" do
    make_line_patterns(@v1) |> Enum.each(fn {line, installable?, upgradable?, canary?} ->
      e = Entry.from_line(line)
      assert e.version             == @v1
      assert Entry.installable?(e) == installable?
      assert Entry.upgradable?(e)  == upgradable?
      assert Entry.canary?(e)      == canary?
    end)
  end

  test "find_latest_installable_version/1 should pick up correct version (if any) from 3-line history" do
    for l1 <- make_line_patterns(@v1), l2 <- make_line_patterns(@v2), l3 <- make_line_patterns(@v3) do
      content = Enum.map_join([l1, l2, l3], "\n", &elem(&1, 0))
      version = History.find_latest_installable_version(content)
      expected = Enum.find([l3, l2, l1], fn {_, installable?, _, _} -> installable? end)
      case expected do
        nil          -> assert version == nil
        {l, _, _, _} -> assert String.starts_with?(l, version)
      end
    end
  end

  test "find_next_upgradable_version/3 should pick up correct version (if any) from history" do
    t = Time.now() |> Time.to_iso_timestamp()
    ps1 = make_line_patterns(@v1) |> Enum.map(&elem(&1, 0))
    ps2 = make_line_patterns(@v2) |> Enum.map(&elem(&1, 0))
    prev_version_lines = [
      [],
      Enum.take_random(ps1, 1),
      Enum.take_random(ps1, 2),
    ]
    current_version_lines = [
      Enum.take_random(ps2, 1),
      Enum.take_random(ps2, 2),
    ]
    next_version_lines = [
      {[]                                   , nil},
      {[@v3]                                , @v3},
      {["#{@v3} canary=#{@host}"]           , @v3},
      {["#{@v3} canary=other.host"]         , nil},
      {["#{@v3} noupgrade"]                 , nil},
      {["#{@v3} noupgrade_canary=#{t}"]     , nil},
      {[@v3                           , @v4], @v3},
      {["#{@v3} canary=#{@host}"      , @v4], @v3},
      {["#{@v3} canary=other.host"    , @v4], @v4},
      {["#{@v3} noupgrade"            , @v4], nil},
      {["#{@v3} noupgrade_canary=#{t}", @v4], @v4},
    ]

    # should raise if current_version is not found
    for ls1 <- prev_version_lines, {ls3, _} <- next_version_lines do
      content = List.flatten([ls1, ls3]) |> Enum.join("\n")
      catch_error History.find_next_upgradable_version(:testgear, content, @v2)
    end

    # otherwise find next
    for ls1 <- prev_version_lines, ls2 <- current_version_lines, {ls3, expected} <- next_version_lines do
      content = List.flatten([ls1, ls2, ls3]) |> Enum.join("\n")
      assert History.find_next_upgradable_version(:testgear, content, @v2) == expected
    end
  end
end
