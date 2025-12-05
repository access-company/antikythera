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

        defun handle_my_tool(_conn :: Conn.t(), arguments :: map) :: map do
          param = arguments["param"] || "default"
          McpServerHelper.response_text("Result: \#{param}")
        end
      end
  """

  alias Antikythera.Conn

  # JSON-RPC 2.0 error codes
  # https://www.jsonrpc.org/specification#error_object
  @error_code_method_not_found -32_601
  @error_code_invalid_params -32_602
  @error_code_internal_error -32_603
  @error_code_server_error -32_000

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
    helper = __MODULE__

    quote do
      @mcp_server_name unquote(server_name)
      @mcp_server_version unquote(server_version)
      @mcp_tools unquote(tools)

      def handle_mcp_request(conn) do
        unquote(helper).dispatch_method(
          conn,
          conn.request.body,
          @mcp_server_name,
          @mcp_server_version,
          @mcp_tools
        )
      end

      def method_not_allowed(conn) do
        unquote(helper).method_not_allowed(conn)
      end
    end
  end

  # Helper functions called from generated code

  @doc false
  defun dispatch_method(
          conn :: Conn.t(),
          request :: map,
          server_name :: String.t(),
          server_version :: String.t(),
          tools :: [Tool.t()]
        ) :: Conn.t() do
    case request do
      %{"method" => "initialize"} ->
        handle_initialize(conn, request, server_name, server_version)

      %{"method" => "notifications/initialized"} ->
        handle_notification(conn)

      %{"method" => "tools/list"} ->
        handle_tools_list(conn, request, tools)

      %{"method" => "tools/call"} ->
        handle_tools_call(conn, request, tools)

      %{"method" => _method} ->
        handle_method_not_found(conn, request)

      _ ->
        handle_invalid_params(conn, request)
    end
  end

  @doc false
  defun handle_invalid_params(conn :: Conn.t(), request :: map) :: Conn.t() do
    id = request["id"]

    response = %{
      jsonrpc: "2.0",
      error: %{
        code: @error_code_invalid_params,
        message: "Invalid params: Missing method"
      },
      id: id
    }

    Conn.json(conn, 400, response)
  end

  @doc false
  defun handle_method_not_found(conn :: Conn.t(), request :: map) :: Conn.t() do
    id = request["id"]

    response = %{
      jsonrpc: "2.0",
      error: %{
        code: @error_code_method_not_found,
        message: "Method not found"
      },
      id: id
    }

    Conn.json(conn, 200, response)
  end

  @doc false
  defun handle_notification(conn :: Conn.t()) :: Conn.t() do
    Conn.put_status(conn, 202)
  end

  @doc false
  defun handle_initialize(
          conn :: Conn.t(),
          request :: map,
          server_name :: String.t(),
          server_version :: String.t()
        ) :: Conn.t() do
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
          name: server_name,
          version: server_version
        }
      },
      jsonrpc: "2.0",
      id: id
    }

    send_sse_response(conn, response)
  end

  @doc false
  defun handle_tools_list(conn :: Conn.t(), request :: map, tools :: [Tool.t()]) :: Conn.t() do
    id = request["id"]

    tool_list =
      Enum.map(tools, fn tool ->
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
        tools: tool_list
      },
      jsonrpc: "2.0",
      id: id
    }

    send_sse_response(conn, response)
  end

  @doc false
  defun handle_tools_call(conn :: Conn.t(), request :: map, tools :: [Tool.t()]) :: Conn.t() do
    id = request["id"]
    params = request["params"] || %{}
    tool_name = params["name"]
    arguments = params["arguments"] || %{}

    tool = Enum.find(tools, fn t -> t.name == tool_name end)

    response =
      if tool do
        execute_tool_callback(conn, tool, arguments, id)
      else
        tool_not_found_response(tool_name, id)
      end

    send_sse_response(conn, response)
  end

  defunp execute_tool_callback(conn :: Conn.t(), tool :: Tool.t(), arguments :: map, id :: any) ::
           map do
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
            code: @error_code_internal_error,
            message: "Internal error: #{Exception.message(error)}"
          },
          id: id
        }
    end
  end

  defunp tool_not_found_response(tool_name :: any, id :: any) :: map do
    %{
      jsonrpc: "2.0",
      error: %{
        code: @error_code_invalid_params,
        message: "MCP error #{@error_code_invalid_params}: Tool #{tool_name} not found"
      },
      id: id
    }
  end

  defunp send_sse_response(conn :: Conn.t(), response :: map) :: Conn.t() do
    json_data = Jason.encode!(response)
    sse_message = "event: message\ndata: #{json_data}\n\n"

    conn
    |> Conn.send_chunked(200, %{"content-type" => "text/event-stream"})
    |> Conn.chunk(sse_message)
    |> Conn.end_chunked()
  end

  @doc false
  defun method_not_allowed(conn :: Antikythera.Conn.t()) :: Antikythera.Conn.t() do
    response = %{
      jsonrpc: "2.0",
      error: %{
        code: @error_code_server_error,
        message: "Method not allowed."
      },
      id: nil
    }

    Conn.json(conn, 405, response)
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
