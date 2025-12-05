# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Controller.McpServerHelperTest do
  use Croma.TestCase
  alias Antikythera.Test.ConnHelper

  describe "response_text/1" do
    test "should create a text response" do
      result = McpServerHelper.response_text("Hello, world!")

      assert result == %{
               content: [
                 %{
                   type: "text",
                   text: "Hello, world!"
                 }
               ]
             }
    end

    test "should handle empty string" do
      result = McpServerHelper.response_text("")

      assert result == %{
               content: [
                 %{
                   type: "text",
                   text: ""
                 }
               ]
             }
    end
  end

  describe "response_json/1" do
    test "should create a JSON response with structured content" do
      result = McpServerHelper.response_json(%{key: "value"})

      assert result == %{
               content: [
                 %{
                   type: "text",
                   text: ~s({"key":"value"})
                 }
               ],
               structuredContent: %{key: "value"}
             }
    end

    test "should handle complex nested data" do
      data = %{users: [%{name: "Alice"}, %{name: "Bob"}], count: 2}
      result = McpServerHelper.response_json(data)

      assert result.structuredContent == data
      assert is_binary(result.content |> hd() |> Map.get(:text))
    end

    test "should handle empty map" do
      result = McpServerHelper.response_json(%{})

      assert result == %{
               content: [
                 %{
                   type: "text",
                   text: "{}"
                 }
               ],
               structuredContent: %{}
             }
    end
  end

  describe "method_not_allowed/1" do
    test "should return 405 status with JSON-RPC error response" do
      conn = ConnHelper.make_conn()
      result = McpServerHelper.method_not_allowed(conn)

      assert result.status == 405
      assert result.resp_headers["content-type"] == "application/json"

      body = Jason.decode!(result.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["error"]["code"] == -32_000
      assert body["error"]["message"] == "Method not allowed."
      assert body["id"] == nil
    end
  end

  # Test module that uses McpServerHelper
  defmodule TestMcpController do
    alias Antikythera.Controller.McpServerHelper

    use McpServerHelper,
      server_name: "test-server",
      server_version: "1.0.0",
      tools: [
        McpServerHelper.Tool.new!(%{
          name: "echo",
          description: "Echoes input",
          inputSchema: %{
            type: "object",
            properties: %{
              text: %{type: "string"}
            }
          },
          callback: &__MODULE__.handle_echo/2
        }),
        McpServerHelper.Tool.new!(%{
          name: "with_output_schema",
          description: "Tool with output schema",
          inputSchema: %{type: "object"},
          outputSchema: %{type: "object", properties: %{result: %{type: "string"}}},
          callback: &__MODULE__.handle_with_output_schema/2
        }),
        McpServerHelper.Tool.new!(%{
          name: "failing_tool",
          description: "A tool that raises an error",
          inputSchema: %{type: "object"},
          callback: &__MODULE__.handle_failing_tool/2
        })
      ]

    def handle_echo(_conn, args) do
      text = args["text"] || ""
      McpServerHelper.response_text("Echo: #{text}")
    end

    def handle_with_output_schema(_conn, _args) do
      McpServerHelper.response_json(%{result: "success"})
    end

    def handle_failing_tool(_conn, _args) do
      raise "Intentional error"
    end
  end

  describe "handle_mcp_request/1" do
    test "should handle initialize method" do
      conn =
        ConnHelper.make_conn(%{
          body: %{"method" => "initialize", "id" => 1}
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200
      assert result.chunked.enabled == true
      assert result.chunked.finished == true

      # Check SSE response format
      [chunk] = result.chunked.chunks
      assert String.starts_with?(chunk, "event: message\ndata: ")

      # Parse the JSON from SSE data
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2025-03-26"
      assert response["result"]["serverInfo"]["name"] == "test-server"
      assert response["result"]["serverInfo"]["version"] == "1.0.0"
      assert response["result"]["capabilities"]["tools"]["listChanged"] == false
    end

    test "should handle notifications/initialized method" do
      conn =
        ConnHelper.make_conn(%{
          body: %{"method" => "notifications/initialized"}
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 202
    end

    test "should handle tools/list method" do
      conn =
        ConnHelper.make_conn(%{
          body: %{"method" => "tools/list", "id" => 2}
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200

      [chunk] = result.chunked.chunks
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2
      assert length(response["result"]["tools"]) == 3

      # Check tool without outputSchema
      echo_tool = Enum.find(response["result"]["tools"], &(&1["name"] == "echo"))
      assert echo_tool["description"] == "Echoes input"
      assert echo_tool["inputSchema"]["type"] == "object"
      refute Map.has_key?(echo_tool, "outputSchema")

      # Check tool with outputSchema
      output_tool = Enum.find(response["result"]["tools"], &(&1["name"] == "with_output_schema"))
      assert output_tool["outputSchema"]["type"] == "object"
    end

    test "should handle tools/call method successfully" do
      conn =
        ConnHelper.make_conn(%{
          body: %{
            "method" => "tools/call",
            "id" => 3,
            "params" => %{
              "name" => "echo",
              "arguments" => %{"text" => "hello"}
            }
          }
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200

      [chunk] = result.chunked.chunks
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 3
      assert response["result"]["content"] |> hd() |> Map.get("text") == "Echo: hello"
    end

    test "should return error for tools/call with unknown tool" do
      conn =
        ConnHelper.make_conn(%{
          body: %{
            "method" => "tools/call",
            "id" => 4,
            "params" => %{
              "name" => "unknown_tool",
              "arguments" => %{}
            }
          }
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200

      [chunk] = result.chunked.chunks
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 4
      assert response["error"]["code"] == -32_602
      assert response["error"]["message"] == "MCP error -32602: Tool unknown_tool not found"
    end

    test "should return error for tools/call with tool that raises error" do
      conn =
        ConnHelper.make_conn(%{
          body: %{
            "method" => "tools/call",
            "id" => 5,
            "params" => %{
              "name" => "failing_tool",
              "arguments" => %{}
            }
          }
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200

      [chunk] = result.chunked.chunks
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 5
      assert response["error"]["code"] == -32_603
      assert String.contains?(response["error"]["message"], "Internal error:")
    end

    test "should return JSON-RPC method not found error for unknown method" do
      conn =
        ConnHelper.make_conn(%{
          body: %{"method" => "unknown/method", "id" => 6}
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200
      body = Jason.decode!(result.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["error"]["code"] == -32_601
      assert body["error"]["message"] == "Method not found"
      assert body["id"] == 6
    end

    test "should return JSON-RPC parse error for invalid JSON body" do
      conn =
        ConnHelper.make_conn(%{
          body: "invalid json"
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 400
      body = Jason.decode!(result.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["error"]["code"] == -32_700
      assert body["error"]["message"] == "Parse error: Invalid JSON"
      assert body["id"] == nil
    end

    test "should return JSON-RPC invalid params error for missing method" do
      conn =
        ConnHelper.make_conn(%{
          body: %{"id" => 8}
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 400
      body = Jason.decode!(result.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["error"]["code"] == -32_602
      assert body["error"]["message"] == "Invalid params: Missing method"
      assert body["id"] == 8
    end

    test "should return error for tools/call with missing params" do
      conn =
        ConnHelper.make_conn(%{
          body: %{
            "method" => "tools/call",
            "id" => 7
          }
        })

      result = TestMcpController.handle_mcp_request(conn)

      assert result.status == 200

      [chunk] = result.chunked.chunks
      json_str = chunk |> String.replace("event: message\ndata: ", "") |> String.trim()
      response = Jason.decode!(json_str)

      # Should return tool not found error since tool_name is nil
      assert response["error"]["code"] == -32_602
    end
  end

  describe "__using__ macro - method_not_allowed/1" do
    test "should delegate to McpServerHelper.method_not_allowed/1" do
      conn = ConnHelper.make_conn()
      result = TestMcpController.method_not_allowed(conn)

      assert result.status == 405
      body = Jason.decode!(result.resp_body)
      assert body["error"]["code"] == -32_000
    end
  end
end
