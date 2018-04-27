# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.HttpcTest do
  use Croma.TestCase
  use ExUnitProperties

  test "encode_path/1 should percent-encode ascii chars as in URI.encode/1" do
    assert Httpc.encode_path("") == ""

    Enum.each(0..127, fn c ->
      s = <<c>>
      assert Httpc.encode_path(s) == URI.encode(s)
    end)
  end

  test "validate ReqBody" do
    assert Httpc.ReqBody.valid?("hoge")
    assert Httpc.ReqBody.valid?("*")
    assert Httpc.ReqBody.valid?({:form, ["foo": "bar", "hoge": "fuga"]})
    assert Httpc.ReqBody.valid?({:json, %{"str" => "foo", :atom => %{"bar" => "baz"}}})
    assert Httpc.ReqBody.valid?({:file, "/path/to/file"})
    refute Httpc.ReqBody.valid?(:not_string)
    refute Httpc.ReqBody.valid?({:form, :not_list})
    refute Httpc.ReqBody.valid?({:json, :not_map})
    refute Httpc.ReqBody.valid?({:file, :not_string})
  end

  property "encod_path/1 should percent-encode chars as in URI.encode/1" do
    check all s <- string(:printable) do
      assert Httpc.encode_path(s) == URI.encode(s)
    end
  end

  property "encod_path/1 should be idempotent so that it keeps already encoded chars" do
    check all s <- string(:printable) do
      encoded = Httpc.encode_path(s)
      assert Httpc.encode_path(encoded) == encoded
    end
  end
end
