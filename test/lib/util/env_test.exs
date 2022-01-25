# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.EnvTest do
  use Croma.TestCase
  alias Antikythera.Test.ConnHelper

  describe "base_url/1" do
    test "should return the url based on Host HTTP header" do
      conn1 = ConnHelper.make_conn(%{headers: %{"host" => "example.com"}})
      assert Env.base_url(conn1) == "http://example.com"

      conn2 = ConnHelper.make_conn(%{headers: %{"host" => "testgear.localhost:8080"}})
      assert Env.base_url(conn2) == "http://testgear.localhost:8080"
    end

    test "raises error when Host header is not specified" do
      conn = ConnHelper.make_conn(%{headers: %{}})

      assert_raise(RuntimeError, "`Host` header is not in the request", fn ->
        Env.base_url(conn)
      end)
    end
  end
end
