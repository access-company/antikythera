defmodule <%= gear_name_camel %>.Controller.HelloTest do
  use ExUnit.Case

  describe "GET /hello" do
    test "should render HAML template as HTML" do
      response = Req.get("/hello", %{}, [params: %{"locale" => "ja"}])
      assert response.status == 200
      assert response.headers["content-type"] == "text/html; charset=utf-8"
      body = response.body
      assert String.starts_with?(body, "<!DOCTYPE html>")
    end

    test "should change the message according to the query parameter" do
      [
        {%{"locale" => "en"}, "Hello"},
        {%{"locale" => "ja"}, "こんにちは"},
        {%{}, "Hello"}
      ]
      |> Enum.each(fn {params, message} ->
        assert %{status: 200, body: body} = Req.get("/hello", %{}, [params: params])
        assert String.contains?(body, "Message from <%= gear_name %>: #{message}")
      end)
    end

    test "should respond with 400 if the locale is invalid" do
      [
        %{"locale" => ""},
        %{"locale" => "en-x-tooLong"},
        %{"locale" => "!invalid"}
      ]
      |> Enum.each(fn params ->
        assert %{status: 400} = Req.get("/hello", %{}, [params: params])
      end)
    end
  end
end
