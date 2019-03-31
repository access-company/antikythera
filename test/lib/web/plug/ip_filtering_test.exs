# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Plug.IpFilteringTest do
  use Croma.TestCase
  alias Antikythera.IpAddress
  alias Antikythera.Test.{ConnHelper, GearConfigHelper}

  @range_strings ["10.5.134.56/32", "10.5.136.0/24"]
  @patterns [
    {"10.5.134.55" , false},
    {"10.5.134.56" , true },
    {"10.5.134.57" , false},
    {"10.5.135.255", false},
    {"10.5.135.255", false},
    {"10.5.136.0"  , true },
    {"10.5.136.255", true },
    {"10.5.137.0"  , false},
  ]

  defp run_check_and_assert(f) do
    Enum.each(@patterns, fn {addr_str, result} ->
      conn1 = ConnHelper.make_conn(%{sender: {:web, addr_str}, status: nil})
      conn2 = f.(conn1)
      assert conn2.status == (if result, do: nil, else: 401)
    end)
  end

  test "check_by_static_ranges should accept/reject request" do
    ranges = Enum.map(@range_strings, &IpAddress.V4.parse_range!/1)
    run_check_and_assert(fn conn ->
      IpFiltering.check_by_static_ranges(conn, [ranges: ranges])
    end)
  end

  test "check_by_gear_config should accept/reject request" do
    GearConfigHelper.set_config(:testgear, %{"ALLOWED_IP_RANGES" => @range_strings})
    run_check_and_assert(fn conn ->
      IpFiltering.check_by_gear_config(conn, [])
    end)
    GearConfigHelper.set_config(:testgear, %{"CUSTOM_FIELD" => @range_strings})
    run_check_and_assert(fn conn ->
      IpFiltering.check_by_gear_config(conn, [field_name: "CUSTOM_FIELD"])
    end)
    GearConfigHelper.set_config(:testgear, %{})
  end

  test "check_by_static_ranges and check_by_gear_config should respect allow_g2g option" do
    [
      fn(conn, opts) -> IpFiltering.check_by_static_ranges(conn, [ranges: []] ++ opts) end,
      fn(conn, opts) -> IpFiltering.check_by_gear_config(conn, opts) end,
    ] |> Enum.each(fn f ->
      [
        {[]                , 401},
        {[allow_g2g: false], 401},
        {[allow_g2g: true ], nil},
      ] |> Enum.each(fn {opts, expected_status} ->
        conn = ConnHelper.make_conn(%{sender: {:gear, :sender_gear}, status: nil})
        conn2 = f.(conn, opts)
        assert conn2.status == expected_status
      end)
    end)
  end
end
