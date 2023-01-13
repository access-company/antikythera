# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ConnTypesTest do
  use ExUnit.Case
  alias Antikythera.Request, as: Req
  alias Antikythera.Context
  alias Antikythera.Conn

  test "validate PathMatches" do
    assert Req.PathMatches.valid?(%{foo: "bar"})
    assert Req.PathMatches.valid?(%{foo1: "bar1", foo2: "wild/card"})
    assert Req.PathMatches.valid?(%{})

    refute Req.PathMatches.valid?(%{"not_atom" => "bar"})
    refute Req.PathMatches.valid?(%{foo: :not_string})
    refute Req.PathMatches.valid?("not_map")
  end

  test "validate Sender" do
    assert Req.Sender.valid?({:web, "127.0.0.1"})
    assert Req.Sender.valid?({:gear, :testgear})

    refute Req.Sender.valid?({:gear, "not_atom"})
    refute Req.Sender.valid?({:undefined_key, :testgear})
    refute Req.Sender.valid?("not_atom")
    refute Req.Sender.valid?({})
  end

  test "validate BeforeSend" do
    assert Conn.BeforeSend.valid?([fn conn -> conn end])
    assert Conn.BeforeSend.valid?([])

    refute Conn.BeforeSend.valid?(["not_function"])
    refute Conn.BeforeSend.valid?("not_list")
  end

  test "validate Assign" do
    assert Conn.Assigns.valid?(%{foo: "bar"})
    assert Conn.Assigns.valid?(%{foo1: "bar1", foo2: "bar2"})
    assert Conn.Assigns.valid?(%{})

    refute Conn.Assigns.valid?(%{"not_atom" => "bar"})
    refute Conn.Assigns.valid?("not_map")
  end

  test "Request: new/1" do
    base_req = %Req{
      method: :get,
      path_info: ["hoge"],
      path_matches: %{foo: "bar"},
      query_params: %{},
      headers: %{},
      cookies: %{},
      raw_body: "",
      body: "",
      sender: {:web, "127.0.0.1"}
    }

    assert Req.new(
             method: :get,
             path_info: ["hoge"],
             path_matches: %{foo: "bar"},
             sender: {:web, "127.0.0.1"}
           ) == {:ok, base_req}

    assert Req.new(
             method: :get,
             path_info: ["hoge"],
             path_matches: %{foo: "bar"},
             query_params: %{"foo" => "bar"},
             headers: %{"foo" => "bar"},
             cookies: %{"foo" => "bar"},
             body: "hoge",
             sender: {:gear, :testgear}
           ) ==
             {:ok,
              %Req{
                base_req
                | query_params: %{"foo" => "bar"},
                  headers: %{"foo" => "bar"},
                  cookies: %{"foo" => "bar"},
                  body: "hoge",
                  sender: {:gear, :testgear}
              }}

    assert Req.new(path_info: ["hoge"], path_matches: %{foo: "bar"}, sender: {:web, "127.0.0.1"}) ==
             {:error, {:value_missing, [Req, {Antikythera.Http.Method, :method}]}}

    assert Req.new(method: :get, path_matches: %{foo: "bar"}, sender: {:web, "127.0.0.1"}) ==
             {:error, {:value_missing, [Req, {Antikythera.PathInfo, :path_info}]}}

    assert Req.new(method: :get, path_info: ["hoge"], sender: {:web, "127.0.0.1"}) ==
             {:error, {:value_missing, [Req, {Req.PathMatches, :path_matches}]}}

    assert Req.new([]) == {:error, {:value_missing, [Req, {Antikythera.Http.Method, :method}]}}

    assert Req.new(method: :get, path_info: ["hoge"], path_matches: %{foo: "bar"}) ==
             {:error, {:value_missing, [Req, {Req.Sender, :sender}]}}
  end

  test "Conn: new/1" do
    {:ok, req} =
      Req.new(method: :get, path_info: ["hoge"], path_matches: %{}, sender: {:web, "127.0.0.1"})

    context = AntikytheraCore.Context.make(:testgear, {Testgear.Controller.Hello, :hello})

    base_conn = %Conn{
      request: req,
      context: context,
      status: nil,
      resp_headers: %{},
      resp_cookies: %{},
      resp_body: "",
      before_send: [],
      assigns: %{}
    }

    assert Conn.new(request: req, context: context, status: nil) == {:ok, base_conn}

    {:ok, conn1} =
      Conn.new(
        request: req,
        context: context,
        status: 200,
        resp_headers: %{"foo" => "bar"},
        resp_body: "hoge",
        assigns: %{foo: "bar"}
      )

    assert conn1 == %Conn{
             base_conn
             | status: 200,
               resp_headers: %{"foo" => "bar"},
               resp_body: "hoge",
               assigns: %{foo: "bar"}
           }

    assert Conn.new(request: req) == {:error, {:value_missing, [Conn, {Context, :context}]}}
    assert Conn.new(context: context) == {:error, {:value_missing, [Conn, {Req, :request}]}}
    assert Conn.new([]) == {:error, {:value_missing, [Conn, {Req, :request}]}}
    {:error, reason} = Conn.new(request: req, context: context, status: :ok)

    assert reason ==
             {:invalid_value,
              [Conn, {Croma.TypeGen.Nilable.Antikythera.Http.Status.Int, :status}]}
  end
end
