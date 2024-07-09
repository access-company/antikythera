defmodule <%= gear_name_camel %>.Controller.Api.HelloTest do
  use ExUnit.Case

  @api_schema OpenApiAssert.find_api("hello")

  describe "POST /api/hello" do
    test "should return a JSON response" do
      response = OpenApiAssert.post_json_for_success(@api_schema, "/api/hello", %{"name" => "John"})
      assert response.status == 200
      body = response.body
      assert %{"message" => "Hello, John!"} = Jason.decode!(body)
    end

    test "should respond with 400 if the name is invalid" do
      [
        %{"name" => ""},
        %{"name" => "!Invalid"}
      ]
      |> Enum.each(fn body ->
        assert %{status: 400} = Req.post_json("/api/hello", body)
      end)
    end

    test "should respond with 400 if the name is missing" do
      assert %{status: 400} = Req.post_json("/api/hello", %{})
    end
  end
end
