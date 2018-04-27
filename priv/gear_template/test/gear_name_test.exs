defmodule <%= gear_name_camel %>Test do
  use ExUnit.Case

  test "hello should render HAML template as HTML" do
    response = Req.get("/hello", %{}, [params: %{"locale" => "ja"}])
    assert response.status == 200
    assert response.headers["content-type"] == "text/html; charset=utf-8"
    body = response.body
    assert String.starts_with?(body, "<!DOCTYPE html>")
    assert String.contains?(body, "Message from <%= gear_name %>: こんにちは")
  end
end
