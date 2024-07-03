# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Test.OpenApiAssertHelper do
  @moduledoc """
  Generate wrapper functions for `Antikythera.Test.HttpClient`, which test their request and their response using OpenAPI documents.

  ## Usage

  In `test_helper.exs`

  ```elixir
  defmodule OpenApiAssert do
    use Antikythera.Test.OpenApiAssertHelper,
      yaml_files: ["doc/api/openapi_one.yaml", "doc/api/openapi_two.yaml"],
      json_files: ["doc/api/openapi_json.json"]
  end
  ```

  In your test files

  ```elixir
  @api_schema OpenApiAssert.find_api("MyOperationId")
  test "my test" do
    res = OpenApiAssert.post_json_for_success(@api_schema, "/path", %{"key" => "value"})
  end
  ```

  ## Arguments

  - `:yaml_files`: OpenAPI YAML files
  - `:json_files`: OpenAPI JSON files
  - `:allows_null_for_optional`: Optional request body keys allow null. Defaults to `true`

  ## Description

  Functions in this module check the followings in the request parameter:
  - whether required parameters exist in `query`/`header`/`cookie`
  - whether parameters in `query`/`header`/`cookie` exist in the OpenAPI documents

  **Note that `path` isn't supported.**
  **Note that these won't check schema in the parameters.**

  Functions for `POST` and `PUT` in this module check request body using schema.

  Functions in this module check response body using schema.

  You can check function docs by checking your module which `use`s this module.
  However, since this module is used by testing code, you can't use `mix docs`.
  You can check them in `MIX_ENV=test iex -S mix` like the following:

  ```
  iex(1)> c("test/test_helper.exs", ".")
  iex(2)> h MyOpenApiAssert.find_api
  ```

  You should delete `Elixir.*.beam` in the current directory before running other commands.
  """

  alias __MODULE__, as: Impl

  defmacro __using__(opts) do
    yaml_files = opts[:yaml_files] || []
    json_files = opts[:json_files] || []
    allows_null_for_optional = Keyword.get(opts, :allows_null_for_optional, true)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote do
      use Antikythera.Test.HttpClient
      alias Antikythera.Http.Headers
      alias Antikythera.Httpc.Response
      alias Antikythera.Test.OpenApiAssertHelper.{Normalizer, SchemaAsserter}
      import ExUnit.Assertions

      @assert_option_keys [:ignore_req_fields]

      @doc """
      Send a GET request which should be success.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`

      Other parameters should be same as `Antikythera.Test.HttpClient.get/3`
      """
      defun get_for_success(
              api_schema :: v[map],
              path :: v[String.t()],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        SchemaAsserter.assert_request(asserter, path, nil, headers, [])
        res = get(path, headers, options)
        SchemaAsserter.assert_success_response_schema(asserter, res)
        res
      end

      @doc """
      Send a PUT request which should be success.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`
      - `options`: In addition to `options` for `Antikythera.Test.HttpClient.put_json/4`, you can specify the following:
        - `:ignore_req_fields`: Specifies keys in request body which will not be validated.

      Other parameters should be same as `Antikythera.Test.HttpClient.put_json/4`
      """
      defun put_json_for_success(
              api_schema :: v[map],
              path :: v[String.t()],
              body :: v[map],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        {assert_options, req_options} = Keyword.split(options, @assert_option_keys)
        SchemaAsserter.assert_request(asserter, path, body, headers, assert_options)
        res = put_json(path, body, headers, req_options)
        SchemaAsserter.assert_success_response_schema(asserter, res)
        res
      end

      @doc """
      Send a POST request which should be success.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`
      - `options`: In addition to `options` for `Antikythera.Test.HttpClient.post_json/4`, you can specify the following:
        - `:ignore_req_fields`: Specifies keys in request body which will not be validated.

      Other parameters should be same as `Antikythera.Test.HttpClient.post_json/4`
      """
      defun post_json_for_success(
              api_schema :: v[map],
              path :: v[String.t()],
              body :: v[map],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        {assert_options, req_options} = Keyword.split(options, @assert_option_keys)
        SchemaAsserter.assert_request(asserter, path, body, headers, assert_options)
        res = post_json(path, body, headers, req_options)
        SchemaAsserter.assert_success_response_schema(asserter, res)
        res
      end

      @doc """
      Send a DELETE request which should be success.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`

      Other parameters should be same as `Antikythera.Test.HttpClient.delete/3`
      """
      defun delete_for_success(
              api_schema :: v[map],
              path :: v[String.t()],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        SchemaAsserter.assert_request(asserter, path, nil, headers, [])
        res = delete(path, headers, options)
        SchemaAsserter.assert_success_response_schema(asserter, res)
        res
      end

      @doc """
      Send a GET request which should be error.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`

      Other parameters should be same as `Antikythera.Test.HttpClient.get/3`
      """
      defun get_for_error(
              api_schema :: v[map],
              path :: v[String.t()],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        res = get(path, headers, options)
        SchemaAsserter.assert_error_response_schema(asserter, res)
        res
      end

      @doc """
      Send a PUT request which should be error.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`
      - `options`: In addition to `options` for `Antikythera.Test.HttpClient.put_json/4`, you can specify the following:
        - `:ignore_req_fields`: Specifies keys in request body which will not be validated.

      Other parameters should be same as `Antikythera.Test.HttpClient.put_json/4`
      """
      defun put_json_for_error(
              api_schema :: v[map],
              path :: v[String.t()],
              body :: v[map],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        res = put_json(path, body, headers, options)
        SchemaAsserter.assert_error_response_schema(asserter, res)
        res
      end

      @doc """
      Send a POST request which should be error.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`
      - `options`: In addition to `options` for `Antikythera.Test.HttpClient.post_json/4`, you can specify the following:
        - `:ignore_req_fields`: Specifies keys in request body which will not be validated.

      Other parameters should be same as `Antikythera.Test.HttpClient.post_json/4`
      """
      defun post_json_for_error(
              api_schema :: v[map],
              path :: v[String.t()],
              body :: v[map],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        res = post_json(path, body, headers, options)
        SchemaAsserter.assert_error_response_schema(asserter, res)
        res
      end

      @doc """
      Send a DELETE request which should be error.

      - `api_schema`: Schema definition from `__MODULE__.find_api/1`

      Other parameters should be same as `Antikythera.Test.HttpClient.delete/3`
      """
      defun delete_for_error(
              api_schema :: v[map],
              path :: v[String.t()],
              headers :: v[Headers.t()] \\ %{},
              options :: v[list] \\ []
            ) :: v[Response.t()] do
        asserter = create_schema_asserter(api_schema)
        res = delete(path, headers, options)
        SchemaAsserter.assert_error_response_schema(asserter, res)
        res
      end

      @yaml_api_raw_docs Enum.map(unquote(yaml_files), fn path ->
                           File.cwd!() |> Path.join(path) |> YamlElixir.read_from_file!()
                         end)

      @json_api_raw_docs Enum.map(unquote(json_files), fn path ->
                           File.cwd!() |> Path.join(path) |> File.read!() |> Jason.decode!()
                         end)

      @api_doc [@yaml_api_raw_docs, @json_api_raw_docs]
               |> List.flatten()
               |> Enum.reduce(%{}, fn m, acc ->
                 Antikythera.NestedMap.deep_merge(m, acc)
               end)
               |> Normalizer.normalize(unquote(allows_null_for_optional))

      @doc """
      Find an API schema from OpenAPI specs.

      - `operation_id`: `oprationId` for the API

      You can use this schema to functions in this module.
      """
      defun find_api(operation_id :: v[String.t()]) :: v[map] do
        found =
          @api_doc["paths"]
          |> Enum.flat_map(fn {_path, methods} -> methods end)
          |> Enum.map(fn {_method, api} -> api end)
          |> Enum.find(fn api -> api["operationId"] == operation_id end)

        case found do
          nil ->
            raise "Can't find #{operation_id} in the OpenAPI documents"

          _ ->
            found
        end
      end

      defunp create_schema_asserter(api_schema :: v[map]) :: v[SchemaAsserter.t()] do
        SchemaAsserter.new!(%{api: api_schema, components: @api_doc["components"]})
      end
    end
  end

  @doc false
  defun stringify_keys(m :: v[map]) :: v[map] do
    stringify_keys_imp(m)
  end

  defp stringify_keys_imp(v) when is_map(v) do
    Map.new(v, fn {key, value} -> {"#{key}", stringify_keys_imp(value)} end)
  end

  defp stringify_keys_imp(v) when is_list(v) do
    Enum.map(v, &stringify_keys_imp(&1))
  end

  defp stringify_keys_imp(v) do
    v
  end

  defmodule Normalizer do
    @moduledoc false
    defun normalize(doc :: v[map], allows_null_for_optional :: v[boolean]) :: v[map] do
      doc = append_additional_properties_false(doc)

      if allows_null_for_optional do
        append_nullable_to_optional_field(doc)
      else
        doc
      end
    end

    defunp append_additional_properties_false(doc :: v[map]) :: v[map] do
      replace_having_properties(doc, fn m ->
        Map.put_new(m, "additionalProperties", false)
      end)
    end

    defunp append_nullable_to_optional_field(doc :: v[map]) :: v[map] do
      replace_having_properties(doc, fn m ->
        required = m["required"] || []

        update_in(m["properties"], fn properties ->
          Map.new(properties, fn {k, v} ->
            # is_nil(v["type"]) for $ref
            new_v =
              if (k in required or is_nil(v["type"])) and !v["nullable"] do
                v
              else
                Map.update!(v, "type", &[&1, "null"])
              end

            {k, new_v}
          end)
        end)
      end)
    end

    defp replace_having_properties(m, f) when is_map(m) do
      fixed =
        case m["properties"] do
          nil ->
            m

          _ ->
            f.(m)
        end

      Map.new(fixed, fn {k, v} ->
        {k, replace_having_properties(v, f)}
      end)
    end

    defp replace_having_properties(v, f) when is_list(v) do
      Enum.map(v, &replace_having_properties(&1, f))
    end

    defp replace_having_properties(v, _) do
      v
    end
  end

  defmodule SchemaAsserter do
    @moduledoc false

    alias Antikythera.Http.Headers
    alias Antikythera.Httpc.Response
    import ExUnit.Assertions

    use Croma.Struct,
      fields: [
        api: Croma.Map,
        components: Croma.Map
      ]

    defun assert_request(
            asserter :: SchemaAsserter.t(),
            path :: v[String.t()],
            body :: v[map | nil],
            headers :: v[Headers.t()],
            options :: v[list]
          ) :: :ok do
      assert_request_query(asserter, path)

      if body != nil do
        assert_request_body(asserter, body, options)
      end

      assert_request_header(asserter, headers)
      assert_request_cookie(asserter, headers)
      # No check for path due to low benefits.

      :ok
    end

    defun assert_success_response_schema(
            asserter :: SchemaAsserter.t(),
            %{status: _status} = res :: v[Response.t()]
          ) ::
            :ok do
      if res.status == 500 do
        IO.puts(res.body)
      end

      operation_id = asserter.api["operationId"]
      expected_status = success_response_status(asserter)
      assert {res.status, operation_id, res.body} == {expected_status, operation_id, res.body}

      decoded_body =
        if res.body == "" do
          ""
        else
          Jason.decode!(res.body)
        end

      validation_result = validate_response_body(asserter, decoded_body)
      assert {validation_result, decoded_body, operation_id} == {:ok, decoded_body, operation_id}
      :ok
    end

    defun assert_error_response_schema(asserter :: SchemaAsserter.t(), res :: v[Response.t()]) ::
            :ok do
      body =
        case Jason.decode(res.body) do
          {:ok, body} ->
            body

          {:error, _} ->
            IO.ANSI.format([:red, res.body]) |> IO.puts()
            raise("InternalError")
        end

      operation_id = asserter.api["operationId"]
      validation_result = validate_error_response_body(asserter, body, res.status)

      assert {validation_result, operation_id, body} == {:ok, operation_id, body}

      :ok
    end

    defunp assert_request_query(asserter :: SchemaAsserter.t(), path :: v[String.t()]) :: :ok do
      case URI.parse(path) do
        %{query: query_s} ->
          query = URI.decode_query(query_s || "")
          assert_parameters(asserter, "query", query)
      end
    end

    defunp assert_request_header(asserter :: SchemaAsserter.t(), headers :: v[Headers.t()]) :: :ok do
      headers = headers |> Enum.filter(fn {name, _value} -> name != "cookie" end) |> Map.new()
      assert_parameters(asserter, "header", headers)
    end

    defunp assert_request_cookie(asserter :: SchemaAsserter.t(), headers :: v[Headers.t()]) :: :ok do
      cookies =
        (headers["cookie"] || "")
        |> String.split("; ")
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(fn cookie_list -> String.split(cookie_list, "=") end)
        |> Map.new(fn [k, v] -> {k, v} end)

      assert_parameters(asserter, "cookie", cookies)
    end

    defunp assert_parameters(
             asserter :: SchemaAsserter.t(),
             type :: v[String.t()],
             actual :: v[map]
           ) :: :ok do
      operation_id = asserter.api["operationId"]

      api_parameters = get_parameters_for(asserter, type)

      Enum.each(actual, fn {name, _value} ->
        assert name in Map.keys(api_parameters),
               "#{name} doesn't exist on #{operation_id} API #{type} specification"
      end)

      Enum.filter(api_parameters, fn {_name, required} ->
        required
      end)
      |> Enum.each(fn {name, _} ->
        assert name in Map.keys(actual),
               "required #{name} on #{operation_id} API #{type} specification doesn't exist in the #{type}"
      end)

      :ok
    end

    defunp get_parameters_for(asserter :: SchemaAsserter.t(), in_type :: v[String.t()]) :: v[map] do
      (asserter.api["parameters"] || [])
      |> Enum.map(fn
        %{"$ref" => "#/components/parameters/" <> ref} ->
          asserter.components["parameters"][ref]

        other ->
          other
      end)
      |> Enum.filter(fn
        %{"in" => ^in_type} -> true
        _ -> false
      end)
      |> Map.new(fn other ->
        {other["name"], other["required"] || false}
      end)
    end

    defunp assert_request_body(asserter :: SchemaAsserter.t(), body :: v[map], options :: v[list]) ::
             :ok do
      normalized_body = Impl.stringify_keys(body)
      operation_id = asserter.api["operationId"]
      ignore_req_fields = Keyword.get(options, :ignore_req_fields, [])
      validation_result = validate_request_body(asserter, normalized_body, ignore_req_fields)

      assert {validation_result, normalized_body, operation_id} ==
               {:ok, normalized_body, operation_id}

      :ok
    end

    defunp validate_request_body(
             asserter :: SchemaAsserter.t(),
             body :: v[map],
             ignore_req_fields :: v[list(String.t())]
           ) :: v[:ok | {:error, map}] do
      filtered_body = Map.drop(body, ignore_req_fields)

      case pick_request_body(asserter) do
        nil ->
          if filtered_body == %{} do
            :ok
          else
            {:error, %{}}
          end

        schema ->
          with_ref_target =
            Map.merge(schema, %{
              "components" => asserter.components
            })

          resolved_schema = ExJsonSchema.Schema.resolve(with_ref_target)
          ExJsonSchema.Validator.validate(resolved_schema, filtered_body, error_formatter: false)
      end
    end

    defunp pick_request_body(asserter :: SchemaAsserter.t()) :: v[map | nil] do
      case asserter.api["requestBody"] do
        %{"content" => %{"application/json" => %{"schema" => schema}}} ->
          schema

        _ ->
          nil
      end
    end

    defunp success_response_status(asserter :: SchemaAsserter.t()) :: v[non_neg_integer] do
      {status, _} = pick_success_response(asserter)
      status
    end

    defunp pick_success_response(asserter :: SchemaAsserter.t()) ::
             v[{non_neg_integer, map | nil}] do
      responses = asserter.api["responses"]

      success_key =
        responses
        |> Map.keys()
        |> Enum.find(fn key ->
          key in (200..207 |> Enum.map(&to_string/1))
        end)

      {String.to_integer(success_key),
       responses[success_key]["content"]["application/json"]["schema"]}
    end

    defunp validate_response_body(
             asserter :: SchemaAsserter.t(),
             body :: v[map | list | String.t()]
           ) ::
             v[:ok | {:error, map | String.t()}] do
      case pick_success_response(asserter) do
        {_, nil} ->
          if body == "" do
            :ok
          else
            {:error, "schema is nothing, but response body is not empty"}
          end

        {_, schema} ->
          with_ref_target =
            Map.merge(schema, %{
              "components" => asserter.components
            })

          resolved_schema = ExJsonSchema.Schema.resolve(with_ref_target)
          schema_without_additional_properties = resolve_reference_if_all_of(resolved_schema)

          ExJsonSchema.Validator.validate(schema_without_additional_properties, body,
            error_formatter: false
          )
      end
    end

    # $allOf with item having additionalProperties:false makes validation error.
    # ref. https://github.com/getkin/kin-openapi/issues/101
    # So, this resolves $ref and adds additionalProperties:false to allOf itself.
    #
    # This function is intentionally `defp` because the caller uses `ExJsonSchema.Schema.resolve/1`,
    # `resolve/1` has `no_return` and it breaks `resolved_schema :: ExJsonSchema.Schema.Root`
    # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
    defp resolve_reference_if_all_of(resolved_schema) do
      schema = resolved_schema.schema

      if Map.has_key?(schema, "allOf") do
        ref_targets =
          schema["allOf"]
          # e.g. item %{"$ref" => [:root, "components", "schemas", "AdminUser"]},
          |> Enum.filter(fn x -> Map.has_key?(x, "$ref") end)
          |> Enum.map(fn x ->
            [:root, "components" | rest_path] = x["$ref"]
            rest_path
          end)

          # e.g. item ["schemas", "AdminUser"]
          |> Enum.map(fn path ->
            get_in(schema["components"], path)
          end)

        non_ref_items = Enum.filter(schema["allOf"], fn x -> !Map.has_key?(x, "$ref") end)

        merged =
          Enum.reduce(ref_targets ++ non_ref_items, %{}, fn item, acc ->
            acc
            |> Map.merge(item)
            |> Map.merge(%{
              "properties" => Map.merge(acc["properties"] || %{}, item["properties"]),
              "required" => (acc["required"] || []) ++ (item["required"] || [])
            })
          end)

        %ExJsonSchema.Schema.Root{
          resolved_schema
          | schema:
              Map.merge(merged, %{
                "components" => schema["components"],
                "additionalProperties" => false
              })
        }
      else
        resolved_schema
      end
    end

    defunp validate_error_response_body(
             asserter :: SchemaAsserter.t(),
             body :: v[map],
             status :: v[non_neg_integer]
           ) ::
             v[:ok | {:error, map | :status_not_found}] do
      api_error =
        asserter.api["responses"]
        |> Enum.find(fn {key, _} ->
          api_status = String.to_integer(key)
          api_status >= 400 && api_status == status
        end)

      case api_error do
        nil ->
          {:error, :status_not_found}

        {_, api_error_body} ->
          schema = api_error_body["content"]["application/json"]["schema"]

          with_ref_target =
            Map.merge(schema, %{
              "components" => asserter.components
            })

          resolved_schema = ExJsonSchema.Schema.resolve(with_ref_target)
          ExJsonSchema.Validator.validate(resolved_schema, body, error_formatter: false)
      end
    end
  end
end
