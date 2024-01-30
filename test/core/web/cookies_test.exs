# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.CookiesTest do
  use Croma.TestCase
  alias Antikythera.Http.SetCookie

  test "convert_to_cowboy_cookie_opts" do
    base_cookie = %SetCookie{value: "", path: "/"}

    [
      {%{value: "value"}, %{path: "/"}},
      {%{value: "value", path: "/path"}, %{path: "/path"}},
      {%{value: "value", domain: "x.com"}, %{path: "/", domain: "x.com"}},
      {%{value: "value", secure: true}, %{path: "/", secure: true}},
      {%{value: "value", secure: false}, %{path: "/", secure: false}},
      {%{value: "value", http_only: true}, %{path: "/", http_only: true}},
      {%{value: "value", http_only: false}, %{path: "/", http_only: false}},
      {%{value: "value", max_age: 10}, %{path: "/", max_age: 10}},
      {%{value: "value", http_only: nil}, %{path: "/"}}
    ]
    |> Enum.each(fn {additional, expected} ->
      cookie = SetCookie.update!(base_cookie, additional)
      assert Cookies.convert_to_cowboy_cookie_opts(cookie) == expected
    end)
  end
end
