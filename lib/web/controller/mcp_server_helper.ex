# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.McpServerHelper do
  @moduledoc """
  A simple helper module for creating MCP (Model Context Protocol) servers.

  This module provides utilities to handle a subset of MCP messages including
  initialize, tools/list, and tools/call methods automatically.

  ## Usage

      defmodule MyController do
        use Antikythera.Controller
        alias Antikythera.Controller.McpServerHelper

        use McpServerHelper,
          server_name: "my-server",
          server_version: "1.0.0",
          tools: [
            McpServerHelper.Tool.new!(%{
              name: "my_tool",
              description: "Description of my tool",
              inputSchema: %{
                type: "object",
                properties: %{
                  param: %{type: "string", description: "Parameter description"}
                }
              },
              outputSchema: %{
                type: "object",
                properties: %{
                  result: %{type: "string"}
                }
              },
              callback: &__MODULE__.handle_my_tool/2
            })
          ]

        def handle_my_tool(_conn, arguments) do
          param = arguments["param"] || "default"
          McpServerHelper.response_text("Result: \#{param}")
        end
      end
  """

  defmodule ToolCallback do
    @moduledoc """
    Type definition for a tool callback function.

    A callback function takes a connection and arguments map, and returns a result map.
    """

    @type t :: (Antikythera.Conn.t(), map() -> map())

    defun valid?(f :: any) :: boolean do
      is_function(f, 2)
    end

    defun default() :: nil do
      nil
    end
  end

  defmodule Tool do
    @moduledoc """
    Defines a tool that can be called via MCP (Model Context Protocol).

    ## Fields

    - `name` (required, string) - Unique identifier for the tool
    - `description` (required, string) - Human-readable description of what the tool does
    - `inputSchema` (required, map) - JSON Schema defining the input parameters
    - `outputSchema` (optional, map) - JSON Schema defining the output format
    - `callback` (required, function) - Function that handles the tool call, signature: `(conn, arguments) -> map`

    ## Example

        McpServerHelper.Tool.new!(%{
          name: "echo",
          description: "Echoes back the input text",
          inputSchema: %{
            type: "object",
            properties: %{
              text: %{type: "string", description: "Text to echo"}
            },
            required: ["text"]
          },
          callback: &MyController.handle_echo/2
        })
    """

    use Croma.Struct,
      fields: [
        name: Croma.String,
        description: Croma.String,
        inputSchema: Croma.Map,
        outputSchema: Croma.TypeGen.nilable(Croma.Map),
        callback: ToolCallback
      ]
  end

  defmacro __using__(opts) do
    server_name = Keyword.fetch!(opts, :server_name)
    server_version = Keyword.fetch!(opts, :server_version)
    tools = Keyword.fetch!(opts, :tools)

    quote do
      alias Antikythera.{Conn, G2gResponse}

      @mcp_server_name unquote(server_name)
      @mcp_server_version unquote(server_version)
      @mcp_tools unquote(tools)

      def handle_mcp_request(conn) do
        request_body = conn.request.body

        case request_body do
          %{"method" => "initialize"} ->
            handle_mcp_initialize(conn, request_body)

          %{"method" => "notifications/initialized"} ->
            handle_mcp_notification(conn)

          %{"method" => "tools/list"} ->
            handle_mcp_tools_list(conn, request_body)

          %{"method" => "tools/call"} ->
            handle_mcp_tools_call(conn, request_body)

          _ ->
            Conn.json(conn, 400, %{error: "Unknown method"})
        end
      end

      defp handle_mcp_initialize(conn, request) do
        id = request["id"]

        response = %{
          result: %{
            protocolVersion: "2025-03-26",
            capabilities: %{
              tools: %{
                listChanged: false
              }
            },
            serverInfo: %{
              name: @mcp_server_name,
              version: @mcp_server_version
            }
          },
          jsonrpc: "2.0",
          id: id
        }

        send_mcp_sse_response(conn, response)
      end

      defp handle_mcp_notification(conn) do
        Conn.put_status(conn, 204)
      end

      defp handle_mcp_tools_list(conn, request) do
        id = request["id"]

        tools =
          Enum.map(@mcp_tools, fn tool ->
            base = %{
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema
            }

            if tool.outputSchema do
              Map.put(base, :outputSchema, tool.outputSchema)
            else
              base
            end
          end)

        response = %{
          result: %{
            tools: tools
          },
          jsonrpc: "2.0",
          id: id
        }

        send_mcp_sse_response(conn, response)
      end

      defp handle_mcp_tools_call(conn, request) do
        id = request["id"]
        params = request["params"] || %{}
        tool_name = params["name"]
        arguments = params["arguments"] || %{}

        tool = Enum.find(@mcp_tools, fn t -> t.name == tool_name end)

        response =
          if tool do
            try do
              result = tool.callback.(conn, arguments)

              %{
                result: result,
                jsonrpc: "2.0",
                id: id
              }
            rescue
              error ->
                %{
                  jsonrpc: "2.0",
                  error: %{
                    code: -32_603,
                    message: "Internal error: #{Exception.message(error)}"
                  },
                  id: id
                }
            end
          else
            %{
              jsonrpc: "2.0",
              error: %{
                code: -32_601,
                message: "Tool not found: #{tool_name}"
              },
              id: id
            }
          end

        send_mcp_sse_response(conn, response)
      end

      defp send_mcp_sse_response(conn, response) do
        json_data = Jason.encode!(response)
        sse_message = "event: message\ndata: #{json_data}\n\n"

        conn
        |> Conn.send_chunked(200, %{"content-type" => "text/event-stream"})
        |> Conn.chunk(sse_message)
        |> Conn.end_chunked()
      end

      @doc """
      Returns a standard JSON-RPC 2.0 error response for method not allowed (405).

      This is useful for handling GET/DELETE requests on MCP endpoints that only support POST.

      ## Example

          def method_not_allowed(conn) do
            Antikythera.Controller.McpServerHelper.method_not_allowed(conn)
          end
      """
      def method_not_allowed(conn) do
        Antikythera.Controller.McpServerHelper.method_not_allowed(conn)
      end
    end
  end

  @doc false
  defun method_not_allowed(conn :: Antikythera.Conn.t()) :: Antikythera.Conn.t() do
    response = %{
      jsonrpc: "2.0",
      error: %{
        code: -32_000,
        message: "Method not allowed."
      },
      id: nil
    }

    Antikythera.Conn.json(conn, 405, response)
  end

  @doc """
  Creates a text response for MCP tool results.

  ## Example

      McpServerHelper.response_text("Hello, world!")

  Returns:

      %{
        content: [
          %{
            type: "text",
            text: "Hello, world!"
          }
        ]
      }
  """
  defun response_text(text :: String.t()) :: map do
    %{
      content: [
        %{
          type: "text",
          text: text
        }
      ]
    }
  end

  @doc """
  Creates a JSON response for MCP tool results with structured content.

  ## Example

      McpServerHelper.response_json(%{key: "value"})

  Returns:

      %{
        content: [
          %{
            type: "text",
            text: "{\\"key\\":\\"value\\"}"
          }
        ],
        structuredContent: %{key: "value"}
      }
  """
  defun response_json(data :: map) :: map do
    json_text = Jason.encode!(data)

    %{
      content: [
        %{
          type: "text",
          text: json_text
        }
      ],
      structuredContent: data
    }
  end
end
