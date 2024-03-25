# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.ConnTest do
  use Croma.TestCase

  alias Antikythera.Conn, as: LibConn

  defp make_fake_conn(status, body) do
    %LibConn{
      request: nil,
      context: nil,
      status: status,
      resp_headers: %{},
      resp_cookies: %{},
      resp_body: body,
      before_send: [],
      assigns: %{}
    }
  end

  describe "validate/1" do
    test "should return :ok for status which can have body" do
      conn1 = make_fake_conn(200, "body")
      assert Conn.validate(conn1) == :ok

      conn2 = make_fake_conn(200, "")
      assert Conn.validate(conn2) == :ok
    end

    test "should return :ok for status which must not have body if body is empty" do
      Enum.each([100, 101, 204, 304], fn status ->
        conn = make_fake_conn(status, "")

        assert Conn.validate(conn) == :ok
      end)
    end

    test "should raise MatchError for status which must not have body if body isn't empty" do
      Enum.each([100, 101, 204, 304], fn status ->
        conn = make_fake_conn(status, "body")

        assert_raise MatchError, fn ->
          Conn.validate(conn)
        end
      end)
    end
  end
end
