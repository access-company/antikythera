# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.StringTypesTest do
  use ExUnit.Case
  alias Antikythera.VersionStr
  alias Antikythera.Domain
  alias Antikythera.CowboyWildcardSubdomain
  alias Antikythera.EncodedPath
  alias Antikythera.UnencodedPath
  alias Antikythera.Email
  alias Antikythera.Url
  alias Antikythera.ContextId
  alias Antikythera.TenantId

  test "validate VersionStr" do
    valid_version_str = "0.0.1-20180501235959+0123456789abcdef0123456789abcdef01234567"
    assert VersionStr.valid?(valid_version_str)

    # It is also valid as a standard semantic version string
    {:ok, v} = Version.parse(valid_version_str)

    assert v == %Version{
             major: 0,
             minor: 0,
             patch: 1,
             pre: [20_180_501_235_959],
             build: "0123456789abcdef0123456789abcdef01234567"
           }

    # Multi-digit numbers in major/minor/patch part are currently not allowed
    refute VersionStr.valid?("0.0.10-20180501235959+0123456789abcdef0123456789abcdef01234567")
  end

  test "validate Domain" do
    assert Domain.valid?("jp.access-company.com")
    assert Domain.valid?("localhost")
    # It does not exist nor reserved, though acceptable as domain name.
    assert Domain.valid?("with-hyphen")

    refute Domain.valid?("with_invalid.char")
    refute Domain.valid?(String.duplicate("a", 64) <> ".com")
    refute Domain.valid?(String.duplicate("a", 64))
    refute Domain.valid?("-starting.with.hyphen")
    refute Domain.valid?("end-with-.hyphen")
    refute Domain.valid?("-starting-with-hyphen")
    refute Domain.valid?("end-with-hyphen-")
    refute Domain.valid?("-" <> String.duplicate("a", 63))
    refute Domain.valid?(String.duplicate("a", 63) <> "-")
    # should be disjoint from CowboyWildcardSubdomain
    refute Domain.valid?(":_.example.com")
  end

  test "validate CowboyWildcardSubdomain" do
    assert CowboyWildcardSubdomain.valid?(":_.example.com")

    refute CowboyWildcardSubdomain.valid?(":_.")
    refute CowboyWildcardSubdomain.valid?("*.example.com")
    refute CowboyWildcardSubdomain.valid?(":subdomain.example.com")
    refute CowboyWildcardSubdomain.valid?("subdomain.:_.example.com")
    refute CowboyWildcardSubdomain.valid?(":_.:_.example.com")
    # should be disjoint from Domain
    refute CowboyWildcardSubdomain.valid?("jp.access-company.com")
    refute CowboyWildcardSubdomain.valid?("localhost")
    refute CowboyWildcardSubdomain.valid?("with-hyphen")
  end

  test "validate EncodedPath" do
    assert EncodedPath.valid?("/hoge")
    assert EncodedPath.valid?("/hoge/")
    assert EncodedPath.valid?("/hoge/bar/foo")
    assert EncodedPath.valid?("/")

    refute EncodedPath.valid?("/あ/い/う/え/お")
    refute EncodedPath.valid?("without_slash")
    refute EncodedPath.valid?("/double//slash")
  end

  test "validate UnencodedPath" do
    assert UnencodedPath.valid?("/hoge")
    assert UnencodedPath.valid?("/hoge/")
    assert UnencodedPath.valid?("/hoge/bar/foo")
    assert UnencodedPath.valid?("/")
    assert UnencodedPath.valid?("/あ/い/う/え/お")

    refute UnencodedPath.valid?("without_slash")
    refute UnencodedPath.valid?("/double//slash")
  end

  test "validate URL" do
    [
      "http://example.com",
      "http://localhost",
      "http://127.0.0.1",
      "http://0.0.0.0",
      "http://255.255.255.255",
      # Valid as both 32-bit IPv4 address and all-numeric TLD
      "http://2130706433",
      # Invalid as IPv4 address, but valid as domain name
      "http://0.0.0.0.1",
      "http://with-port.com:8080",
      "http://127.0.0.1:8080",
      "https://sub-domain.example.com",
      "http://username@example.com",
      "http://username@127.0.0.1",
      "http://username:password@example.com",
      "http://username:password@127.0.0.1",
      "http://example.com?query=params",
      "http://127.0.0.1?query=params",
      "http://example.com/#and-fragment",
      "http://127.0.0.1/#and-fragment",
      "http://username:password@sub-domain.example.com/with/path?query=params#and-fragment",
      "http://username:password@127.0.0.1/with/path?query=params#and-fragment"
    ]
    |> Enum.each(fn url ->
      assert Url.valid?(url)
    end)

    [
      "",
      "noscheme.com",
      "ftp://unsupported.scheme.com",
      "http://domain.with space.com",
      "http://example.com/path/has space",
      "http://example.com?space=not encoded",
      "http://example.com#fragment-with space",
      "http://domain.with\nline\nbreak.com",
      "http://example.com/path/has\nline\nbreak",
      "http://example.com?line_break=not\nencoded",
      "http://example.com#fragment-with\nline\nbreak",
      "http://doubleslash.com//",
      "http://too:many:colons@example.com",
      "http://0.0.0.256",
      "http://127_0_0_1",
      # IPv6 not supported
      "http://[0123:4567:89AB:CDEF:0123:4567:89AB:CDEF]"
    ]
    |> Enum.each(fn invalid_url ->
      refute Url.valid?(invalid_url)
    end)
  end

  test "validate Email address" do
    [
      "username@localhost",
      "username@example.com",
      "!#$%&'*+-/=?^_`.{|}~@example.com",
      String.duplicate("a", 64) <> "@exapmle.com",
      # Invalid in original RFCs, but allowed
      ".leading-dots@example.com",
      # Invalid in original RFCs, but allowed
      "trailing-dots.@example.com",
      # Invalid in original RFCs, but allowed
      "consecutive..dots@example.com"
    ]
    |> Enum.each(fn address ->
      assert Email.valid?(address)
    end)

    [
      "",
      "no-at-mark.example.com",
      "nodomain@",
      "@nolocal.com",
      "username@-start-with-hyphen.com",
      "username@end-with-hyphen-.com",
      "username@" <> String.duplicate("a", 64) <> ".com",
      "username@" <> String.duplicate("a", 64),
      "username@invalid_char.com",
      # Valid in original RFCs, but disallowed
      "username@[127.0.0.1]",
      # Valid in original RFCs, but disallowed
      "\"quoted string\"@exapmle.com",
      String.duplicate("a", 65) <> "@exapmle.com"
    ]
    |> Enum.each(fn invalid_address ->
      refute Email.valid?(invalid_address)
    end)
  end

  test "validate ContextId" do
    [
      "20160126-004022.557_ip-172-31-5-176_0.684.0",
      "antikythera_system"
    ]
    |> Enum.each(fn id ->
      assert ContextId.valid?(id)
    end)

    [
      "",
      "abc",
      "マルチバイト文字"
    ]
    |> Enum.each(fn id ->
      refute ContextId.valid?(id)
    end)
  end

  test "validate TenantId" do
    [
      "abc",
      "abcdefghijklmnopqrstuvwxyz123456",
      "_1_2_3_",
      "g_12345678",
      "notenanta",
      "anotenant"
    ]
    |> Enum.each(fn tenant_id ->
      assert TenantId.valid?(tenant_id)
    end)

    [
      "",
      "ab",
      "abcdefghijklmnopqrstuvwxyz1234567",
      "has-hyphen",
      "white space",
      "マルチバイト文字",
      "notenant"
    ]
    |> Enum.each(fn tenant_id ->
      refute TenantId.valid?(tenant_id)
    end)
  end
end
