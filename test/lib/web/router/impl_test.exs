# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Router.ImplTest do
  use Croma.TestCase

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
      "/path/with/*wildcard_followed_by_slash/",
    ]
    for path <- invalid_paths do
      list = [{:get, path, X, :a, []}]
      catch_error Impl.generate_route_function_clauses(__MODULE__, :web, list)
    end
  end

  test "Impl.generate_route_function_clauses should accept valid path" do
    valid_paths = [
      "/",
      "/fixed/string/of/segments",
      "/:segment1/:segment2/:segment3",
      "/*wildcard",
      "/long/path/with/:segment1/:segment2/:segment3/and/*wildcard",
    ]
    for path <- valid_paths do
      list = [{:get, path, X, :a, []}]
      _no_error_raised = Impl.generate_route_function_clauses(__MODULE__, :web, list)
    end
  end

  test "Impl.generate_route_function_clauses should reject duplicated path names" do
    list = [{:get, "foo1/bar1", X, :a, as: "test_path"}, {:get, "foo2/bar2", X, :a, as: "test_path"}]
    catch_error Impl.generate_route_function_clauses(__MODULE__, :web, list)
  end
end
