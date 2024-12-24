# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

import Bitwise
use Croma

defmodule Antikythera.IpAddress do
  @moduledoc """
  Functions to parse/compare IP addresses.
  """

  defmodule V4 do
    @type u32 :: 0..0xFFFFFFFF
    @type range :: %Range{first: u32, last: u32}

    defun range_include?(r :: range, addr :: :inet.ip4_address()) :: boolean do
      to_integer(addr) in r
    end

    defun parse(s :: v[String.t()]) :: Croma.Result.t(:inet.ip4_address()) do
      String.to_charlist(s) |> :inet.parse_ipv4strict_address()
    end

    Croma.Result.define_bang_version_of(parse: 1)

    defun parse_range!(s :: v[String.t()]) :: range do
      [address, mask_str] = String.split(s, "/")
      int = parse!(address) |> to_integer
      mask = String.to_integer(mask_str)
      bitmask_lower = (1 <<< (32 - mask)) - 1
      bitmask_upper = 0xFFFFFFFF - bitmask_lower
      lowest = int &&& bitmask_upper
      highest = lowest + bitmask_lower
      Range.new(lowest, highest)
    end

    defunp to_integer(addr :: :inet.ip4_address()) :: u32 do
      {i1, i2, i3, i4} = addr
      (i1 <<< 24) + (i2 <<< 16) + (i3 <<< 8) + i4
    end
  end

  defmodule V6 do
    # Not implemented
  end
end
