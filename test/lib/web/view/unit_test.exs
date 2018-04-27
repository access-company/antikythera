# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.View.UnitTest do
  use Croma.TestCase

  test "bytes should convert integers to readable format" do
    assert Unit.bytes(                0) == "0 B"
    assert Unit.bytes(              999) == "999 B"
    assert Unit.bytes(            1_000) == "1.0 KB"
    assert Unit.bytes(            9_999) == "10.0 KB"
    assert Unit.bytes(           99_999) == "100 KB"
    assert Unit.bytes(          999_999) == "1000 KB"
    assert Unit.bytes(        1_234_567) == "1.2 MB"
    assert Unit.bytes(    1_000_000_000) == "1.0 GB"
    assert Unit.bytes(1_000_000_000_000) == "1.0 TB"
  end
end
