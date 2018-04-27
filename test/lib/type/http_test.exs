# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.HttpTest do
  use Croma.TestCase, alias_as: H
  alias H.{SetCookie, SetCookiesMap}

  test "validate Method" do
    assert H.Method.valid?(:get)

    refute H.Method.valid?(:nonexisting)
  end

  test "validate QueryParams" do
    assert H.QueryParams.valid?(%{"foo" => "bar"})

    refute H.QueryParams.valid?(%{not_string: "bar"})
    refute H.QueryParams.valid?(%{"foo" => :not_string})
    refute H.QueryParams.valid?(%{not_string: :not_string})
    refute H.QueryParams.valid?("not_map")
  end

  test "validate Headers" do
    assert H.Headers.valid?(%{"foo" => "bar"})
    assert H.Headers.valid?(%{"foo" => "*"})

    refute H.Headers.valid?(%{not_string: "bar"})
    refute H.Headers.valid?(%{"foo" => :not_string})
    refute H.Headers.valid?(%{not_string: :not_string})
    refute H.Headers.valid?("not_map")
  end

  test "validate SetCookie" do
    cookie = SetCookie.new!([value: "", domain: nil, http_only: nil, max_age: nil, path: nil, secure: nil])

    assert SetCookie.new([domain: nil, http_only: nil, max_age: nil, path: nil, secure: nil]) == {:error, {:value_missing, [SetCookie, {Croma.String, :value}]}}

    assert SetCookie.update(cookie, [value:     "bar"])           == {:ok, %SetCookie{value: "bar"}}
    assert SetCookie.update(cookie, [value:     :not_string])     == {:error, {:invalid_value, [SetCookie, {Croma.String                                , :value    }]}}
    assert SetCookie.update(cookie, [path:      "without_slash"]) == {:error, {:invalid_value, [SetCookie, {Croma.TypeGen.Nilable.Antikythera.EncodedPath, :path     }]}}
    assert SetCookie.update(cookie, [domain:    "invalid_char"])  == {:error, {:invalid_value, [SetCookie, {Croma.TypeGen.Nilable.Antikythera.Domain     , :domain   }]}}
    assert SetCookie.update(cookie, [secure:    "not_boolean"])   == {:error, {:invalid_value, [SetCookie, {Croma.TypeGen.Nilable.Croma.Boolean         , :secure   }]}}
    assert SetCookie.update(cookie, [http_only: "not_boolean"])   == {:error, {:invalid_value, [SetCookie, {Croma.TypeGen.Nilable.Croma.Boolean         , :http_only}]}}
    assert SetCookie.update(cookie, [max_age:   "not_integer"])   == {:error, {:invalid_value, [SetCookie, {Croma.TypeGen.Nilable.Croma.Integer         , :max_age  }]}}
  end

  test "parse set-cookie header value" do
    d = "example.com"
    [
      {"name=value"                                                   , %SetCookie{value: "value"}},
      {"name=value; Path=/"                                           , %SetCookie{value: "value", path: "/"}},
      {"name=value; Domain=#{d}"                                      , %SetCookie{value: "value", domain: d}},
      {"name=value; Secure"                                           , %SetCookie{value: "value", secure: true}},
      {"name=value; HttpOnly"                                         , %SetCookie{value: "value", http_only: true}},
      {"name=value; Max-Age=10"                                       , %SetCookie{value: "value", max_age: 10}},
      {"name=value; Path=/; Domain=#{d}; Secure; HttpOnly; Max-Age=10", %SetCookie{value: "value", path: "/", domain: d, secure: true, http_only: true, max_age: 10}},
      {"name=value; unknown=attr"                                     , %SetCookie{value: "value"}},
    ] |> Enum.each(fn {input, cookie} ->
      assert SetCookie.parse!(input) == {"name", cookie}
    end)
  end

  test "validate SetCookiesMap" do
    assert SetCookiesMap.valid?(%{"foo" => %SetCookie{value: "bar"}})

    refute SetCookiesMap.valid?(%{"foo" => "not_cookie"})
    refute SetCookiesMap.valid?("not_map")
  end

  test "validate Body" do
    assert H.Body.valid?(%{"foo" => "bar"})
    assert H.Body.valid?(%{"foo" => "*"})
    assert H.Body.valid?(%{"foo" => 1})
    assert H.Body.valid?(%{"foo" => %{"1" => "2"}})
    assert H.Body.valid?(%{"foo" => [1]})
    assert H.Body.valid?(%{"foo" => nil})
    assert H.Body.valid?([1, 2])
    assert H.Body.valid?([])
    assert H.Body.valid?("hoge")
    assert H.Body.valid?("*")

    refute H.Body.valid?(:not_string)
  end

  test "validate Status" do
    assert H.Status.Int.valid?(100)
    assert H.Status.Int.valid?(999)

    refute H.Status.Int.valid?(99)
    refute H.Status.Int.valid?(1000)
    refute H.Status.Int.valid?(:not_integer)
  end
end
