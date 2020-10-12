# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.IpAddressTest do
  use Croma.TestCase
  alias IpAddress.V4

  test "Antikythera.IpAddress.V4.range_include?" do
    range = V4.parse_range!("127.0.0.1/28")

    [
      {"126.255.255.255", false},
      {"127.0.0.0", true},
      {"127.0.0.1", true},
      {"127.0.0.5", true},
      {"127.0.0.15", true},
      {"127.0.0.16", false},
      {"61.200.20.128", false}
    ]
    |> Enum.each(fn {addr_str, result} ->
      assert V4.range_include?(range, V4.parse!(addr_str)) == result
    end)
  end
end
