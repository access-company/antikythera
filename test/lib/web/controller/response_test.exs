# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule SolomonLib.Controller.ResponseTest do
  use Croma.TestCase
  alias SolomonLib.Conn
  alias SolomonLib.Test.ConnHelper

  test "redirect should set location header and status" do
    redirect_path = "/redirect/path"
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.redirect(conn1, redirect_path)
    assert conn2.status       == 302
    assert conn2.resp_headers == %{"location" => redirect_path}

    conn3 = ConnHelper.make_conn()
    conn4 = Conn.redirect(conn3, redirect_path, 301)
    assert conn4.status       == 301
    assert conn4.resp_headers == %{"location" => redirect_path}

    conn5 = ConnHelper.make_conn()
    conn6 = Conn.redirect(conn5, redirect_path, :moved_permanently)
    assert conn6.status       == 301
    assert conn6.resp_headers == %{"location" => redirect_path}
  end
end
