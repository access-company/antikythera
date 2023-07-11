# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Router.ImplTest do
  use Croma.TestCase

  alias Antikythera.GearActionTimeout

  test "Impl.generate_route_function_clauses should reject invalid path" do
    invalid_paths = [
      "",
      "path/starting/with/non_slash",
      "/path/with/trailing/slash/",
      "//",
      "/segment with invalid characters",
      "/segment/with/colon:inside",
      "/segment/with/asterisk*inside",
      "/just/a/colon/:",
      "/just/an/asterisk/*",
      "/colon/with/non_snake_case/:Hoge",
      "/asterisk/with/non_snake_case/*123",
      "/path/with/duplicated/:segment/:segment",
      "/path/with/duplicated/:segment/for/both/match_one/and/match_multi/*segment",
      "/path/with/*wildcard/followed/by/other/segments",
      "/path/with/*wildcard_followed_by_slash/"
    ]

    for path <- invalid_paths do
      list = [{:get, path, X, :a, []}]

      assert_raise RuntimeError, fn ->
        Impl.generate_route_function_clauses(__MODULE__, :web, list)
      end
    end
  end

  test "Impl.generate_route_function_clauses should accept valid path" do
    valid_paths = [
      "/",
      "/fixed/string/of/segments",
      "/:segment1/:segment2/:segment3",
      "/*wildcard",
      "/long/path/with/:segment1/:segment2/:segment3/and/*wildcard"
    ]

    for path <- valid_paths do
      list = [{:get, path, X, :a, []}]
      _no_error_raised = Impl.generate_route_function_clauses(__MODULE__, :web, list)
    end
  end

  test "Impl.generate_route_function_clauses should reject duplicated path names" do
    list = [
      {:get, "/foo1/bar1", X, :a, as: "test_path"},
      {:get, "/foo2/bar2", X, :a, as: "test_path"}
    ]

    assert_raise RuntimeError,
                 "path names are not unique",
                 fn ->
                   Impl.generate_route_function_clauses(__MODULE__, :web, list)
                 end
  end

  test "Impl.generate_route_function_clauses should accept valid timeout value" do
    valid_timeout_values = [GearActionTimeout.min(), GearActionTimeout.max()]

    for timeout <- valid_timeout_values do
      list = [{:get, "/", X, :a, timeout: timeout}]
      _no_error_raised = Impl.generate_route_function_clauses(__MODULE__, :web, list)
    end
  end

  test "Impl.generate_route_function_clauses should reject invalid timeout value" do
    invalid_timeout_values = [
      :not_a_number,
      1_234.567,
      GearActionTimeout.min() - 1,
      GearActionTimeout.max() + 1
    ]

    for timeout <- invalid_timeout_values do
      list = [{:get, "/", X, :a, timeout: timeout}]

      assert_raise RuntimeError,
                   ~r/^option `:timeout` must be a positive integer less than or equal to \d+ but given:/,
                   fn ->
                     Impl.generate_route_function_clauses(__MODULE__, :web, list)
                   end
    end
  end
end
