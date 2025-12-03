# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ConnTest do
  use Croma.TestCase
  alias Antikythera.Session
  alias Antikythera.Http.SetCookie
  alias Antikythera.Test.ConnHelper

  test "get_req_header" do
    expected_value = "hoge"
    conn = ConnHelper.make_conn(%{headers: %{"foo" => expected_value}})
    assert Conn.get_req_header(conn, "foo") == expected_value
    assert Conn.get_req_header(conn, "nonexisting_key") == nil
  end

  test "get_req_cookie" do
    expected_value = "hoge"
    conn = ConnHelper.make_conn(%{cookies: %{"foo" => expected_value}})
    assert Conn.get_req_cookie(conn, "foo") == expected_value
    assert Conn.get_req_cookie(conn, "nonexisting_key") == nil
  end

  test "get_req_query" do
    conn = ConnHelper.make_conn(%{query_params: %{"foo1" => "foo1", "foo2" => "foo2"}})
    assert Conn.get_req_query(conn, "foo1") == "foo1"
    assert Conn.get_req_query(conn, "nonexisting_key") == nil
  end

  test "put_resp_header" do
    conn1 = ConnHelper.make_conn(%{headers: %{}})
    conn2 = Conn.put_resp_header(conn1, "foo", "bar")
    assert conn2.resp_headers == %{"foo" => "bar"}

    conn3 = Conn.put_resp_header(conn2, "foo", "new_bar")
    assert conn3.resp_headers == %{"foo" => "new_bar"}

    conn4 = Conn.put_resp_header(conn3, "foo2", "bar2")
    assert conn4.resp_headers == %{"foo" => "new_bar", "foo2" => "bar2"}
  end

  test "put_resp_headers" do
    conn1 = ConnHelper.make_conn(%{headers: %{}})
    assert conn1.resp_headers == %{}

    conn2 = Conn.put_resp_headers(conn1, %{"foo" => "bar", "foo2" => "bar2"})
    assert conn2.resp_headers == %{"foo" => "bar", "foo2" => "bar2"}

    conn3 = Conn.put_resp_headers(conn2, %{"foo" => "new_bar"})
    assert conn3.resp_headers == %{"foo" => "new_bar", "foo2" => "bar2"}

    conn4 = Conn.put_resp_headers(conn3, %{"foo3" => "bar3"})
    assert conn4.resp_headers == %{"foo" => "new_bar", "foo2" => "bar2", "foo3" => "bar3"}
  end

  test "put_resp_cookie" do
    conn1 = ConnHelper.make_conn(%{cookies: %{}})
    conn2 = Conn.put_resp_cookie(conn1, "key", "value")
    assert conn2.resp_cookies == %{"key" => %SetCookie{value: "value", path: "/"}}

    conn3 = Conn.put_resp_cookie(conn2, "key", "new_value")
    assert conn3.resp_cookies == %{"key" => %SetCookie{value: "new_value", path: "/"}}

    conn4 = Conn.put_resp_cookie(conn3, "key", "new_value", %{domain: "x.com"})

    assert conn4.resp_cookies == %{
             "key" => %SetCookie{value: "new_value", path: "/", domain: "x.com"}
           }

    conn5 = Conn.put_resp_cookie(conn4, "key", "new_value", %{secure: true, path: "/hoge"})

    assert conn5.resp_cookies == %{
             "key" => %SetCookie{value: "new_value", secure: true, path: "/hoge"}
           }

    conn6 = Conn.put_resp_cookie(conn5, "new_key", "value")

    assert conn6.resp_cookies == %{
             "key" => %SetCookie{value: "new_value", secure: true, path: "/hoge"},
             "new_key" => %SetCookie{value: "value", path: "/"}
           }
  end

  test "put_status" do
    conn1 = ConnHelper.make_conn() |> Conn.put_status(202)
    assert conn1.status == 202
    conn2 = ConnHelper.make_conn() |> Conn.put_status(:accepted)
    assert conn2.status == 202
  end

  test "put_resp_body" do
    conn1 = ConnHelper.make_conn()
    assert conn1.resp_body == ""
    conn2 = Conn.put_resp_body(conn1, "foo")
    assert conn2.resp_body == "foo"
    conn3 = Conn.put_resp_body(conn2, "bar")
    assert conn3.resp_body == "bar"
  end

  test "put_resp_cookie_to_revoke" do
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.put_resp_cookie_to_revoke(conn1, "key1")
    assert conn2.resp_cookies == %{"key1" => %SetCookie{value: "", path: "/", max_age: 0}}
    conn3 = Conn.put_resp_cookie_to_revoke(conn2, "key2")

    assert conn3.resp_cookies == %{
             "key1" => %SetCookie{value: "", path: "/", max_age: 0},
             "key2" => %SetCookie{value: "", path: "/", max_age: 0}
           }
  end

  test "get_session" do
    session = %Session{state: :update, id: nil, data: %{"key" => "value"}}
    conn = ConnHelper.make_conn(%{assigns: %{session: session}})
    assert Conn.get_session(conn, "key") == "value"
    assert Conn.get_session(conn, "nonexisting_key") == nil
  end

  test "put_session" do
    session = %Session{state: :update, id: nil, data: %{}}
    conn1 = ConnHelper.make_conn(%{assigns: %{session: session}})
    assert Conn.get_session(conn1, "key") == nil
    conn2 = Conn.put_session(conn1, "key", "value1")
    assert Conn.get_session(conn2, "key") == "value1"
    conn3 = Conn.put_session(conn2, "key", "value2")
    assert Conn.get_session(conn3, "key") == "value2"
  end

  test "delete_session" do
    session = %Session{state: :update, id: nil, data: %{"key1" => "value1", "key2" => "value2"}}
    conn1 = ConnHelper.make_conn(%{assigns: %{session: session}})
    assert Conn.get_session(conn1, "key1") == "value1"
    assert Conn.get_session(conn1, "key2") == "value2"
    conn2 = Conn.delete_session(conn1, "key1")
    assert Conn.get_session(conn2, "key1") == nil
    assert Conn.get_session(conn2, "key2") == "value2"
    conn3 = Conn.delete_session(conn2, "nonexisting_key")
    assert Conn.get_session(conn3, "key1") == nil
    assert Conn.get_session(conn3, "key2") == "value2"
  end

  test "clear_session" do
    session = %Session{state: :update, id: nil, data: %{"key1" => "value1", "key2" => "value2"}}
    conn1 = ConnHelper.make_conn(%{assigns: %{session: session}})
    assert Conn.get_session(conn1, "key1") == "value1"
    assert Conn.get_session(conn1, "key2") == "value2"
    conn2 = Conn.clear_session(conn1)
    assert Conn.get_session(conn2, "key1") == nil
    assert Conn.get_session(conn2, "key2") == nil
  end

  test "renew_session" do
    session1 = %Session{state: :update, id: nil, data: %{}}
    conn = ConnHelper.make_conn(%{assigns: %{session: session1}})
    %Antikythera.Conn{assigns: %{session: session2}} = Conn.renew_session(conn)
    assert session2.state == :renew
  end

  test "destroy_session" do
    session1 = %Session{state: :update, id: nil, data: %{}}
    conn = ConnHelper.make_conn(%{assigns: %{session: session1}})
    %Antikythera.Conn{assigns: %{session: session2}} = Conn.destroy_session(conn)
    assert session2.state == :destroy
  end

  test "no_cache/1" do
    conn1 = ConnHelper.make_conn()
    assert conn1.resp_headers["cache-control"] == nil
    conn2 = Conn.no_cache(conn1)
    assert conn2.resp_headers["cache-control"] == "private, no-cache, no-store, max-age=0"
  end

  test "json/3 should return body as JSON" do
    conn = ConnHelper.make_conn()
    conn2 = Conn.json(conn, 200, %{msg: "json_api@HelloController"})
    assert conn2.status == 200
    assert conn2.resp_headers == %{"content-type" => "application/json"}
    assert conn2.resp_body == ~S({"msg":"json_api@HelloController"})
  end

  test "json/3 should interpret both pos_integer and atom as an HTTP status code" do
    old_hdr = %{"foo" => "bar"}
    conn = ConnHelper.make_conn(%{resp_headers: old_hdr})

    conn2 = Conn.json(conn, :ok, %{msg: "json_api@HelloController"})
    assert conn2.status == 200

    conn3 = Conn.json(conn, 201, %{msg: "json_api@HelloController"})
    assert conn3.status == 201
  end

  test "json/3 should add content-type header" do
    old_hdr = %{"foo" => "bar"}
    conn = ConnHelper.make_conn(%{resp_headers: old_hdr})

    conn2 = Conn.json(conn, 200, %{msg: "json_api@HelloController"})
    assert conn2.resp_headers == Map.put(old_hdr, "content-type", "application/json")
  end

  test "redirect/2 should set location header and status" do
    redirect_path = "/redirect/path"
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.redirect(conn1, redirect_path)
    assert conn2.status == 302
    assert conn2.resp_headers == %{"location" => redirect_path}

    conn3 = ConnHelper.make_conn()
    conn4 = Conn.redirect(conn3, redirect_path, 301)
    assert conn4.status == 301
    assert conn4.resp_headers == %{"location" => redirect_path}

    conn5 = ConnHelper.make_conn()
    conn6 = Conn.redirect(conn5, redirect_path, :moved_permanently)
    assert conn6.status == 301
    assert conn6.resp_headers == %{"location" => redirect_path}
  end

  test "send_chunked/3 should set chunked state in conn" do
    conn1 = ConnHelper.make_conn()
    headers = %{"content-type" => "text/plain"}
    conn2 = Conn.send_chunked(conn1, 200, headers)

    assert conn2.status == 200
    assert conn2.resp_headers == headers
    assert conn2.chunked == %{enabled: true, chunks: []}
  end

  test "chunk/2 should append chunk to chunks list" do
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.send_chunked(conn1, 200, %{"content-type" => "text/plain"})
    conn3 = Conn.chunk(conn2, "First chunk\n")
    conn4 = Conn.chunk(conn3, "Second chunk\n")

    # Chunks are stored in reverse order for efficiency (using cons)
    # They are reversed when sending via cowboy
    assert conn4.chunked.chunks == ["Second chunk\n", "First chunk\n"]
  end

  test "send_chunked/3 and chunk/2 integration" do
    conn =
      ConnHelper.make_conn()
      |> Conn.send_chunked(200, %{"content-type" => "text/plain"})
      |> Conn.chunk("chunk1")
      |> Conn.chunk("chunk2")
      |> Conn.chunk("chunk3")

    assert conn.status == 200
    assert conn.chunked.enabled == true
    # Chunks are stored in reverse order for efficiency (using cons)
    # They are reversed when sending via cowboy
    assert conn.chunked.chunks == ["chunk3", "chunk2", "chunk1"]
  end

  test "get_streaming_state/1 should return nil when no state is set" do
    conn = ConnHelper.make_conn()
    assert Conn.get_streaming_state(conn) == nil
  end

  test "put_streaming_state/2 and get_streaming_state/1 should store and retrieve state" do
    conn1 = ConnHelper.make_conn()
    state = %{count: 5, last_id: "event_123"}
    conn2 = Conn.put_streaming_state(conn1, state)

    assert Conn.get_streaming_state(conn2) == state
  end

  test "put_streaming_state/2 should update existing state" do
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.put_streaming_state(conn1, %{count: 1})
    conn3 = Conn.put_streaming_state(conn2, %{count: 2, new_field: "value"})

    assert Conn.get_streaming_state(conn3) == %{count: 2, new_field: "value"}
  end

  test "end_chunked/1 should set finished flag in chunked state" do
    conn1 = ConnHelper.make_conn()
    conn2 = Conn.send_chunked(conn1, 200, %{"content-type" => "text/plain"})
    conn3 = Conn.chunk(conn2, "Some data\n")
    conn4 = Conn.end_chunked(conn3)

    assert conn4.chunked.finished == true
    assert conn4.chunked.enabled == true
    # Chunks should still be present
    assert conn4.chunked.chunks == ["Some data\n"]
  end
end
