# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Controller.JsonTest do
  use Croma.TestCase
  alias Antikythera.Conn
  alias Antikythera.Test.ConnHelper

  test "json should return body as JSON" do
    conn  = ConnHelper.make_conn()
    conn2 = Conn.json(conn, 200, %{msg: "json_api@HelloController"})
    assert conn2.status       == 200
    assert conn2.resp_headers == %{"content-type" => "application/json"}
    assert conn2.resp_body    == ~S({"msg":"json_api@HelloController"})
  end

  test "json should interpret both pos_integer and atom as an HTTP status code" do
    old_hdr = %{"foo" => "bar"}
    conn  = ConnHelper.make_conn(%{resp_headers: old_hdr})

    conn2 = Conn.json(conn, :ok, %{msg: "json_api@HelloController"})
    assert conn2.status == 200

    conn3 = Conn.json(conn, 201, %{msg: "json_api@HelloController"})
    assert conn3.status == 201
  end

  test "json should add content-type header" do
    old_hdr = %{"foo" => "bar"}
    conn  = ConnHelper.make_conn(%{resp_headers: old_hdr})

    conn2 = Conn.json(conn, 200, %{msg: "json_api@HelloController"})
    assert conn2.resp_headers == Map.put(old_hdr, "content-type", "application/json")
  end
end
