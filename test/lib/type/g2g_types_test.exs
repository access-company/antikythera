# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule SolomonLib.G2gTypesTest do
  use ExUnit.Case

  test "G2gRequest: new/1" do
    alias SolomonLib.G2gRequest, as: GRq
    assert GRq.new([method: :get, path: "/"])                         == {:ok, %GRq{body: "", cookies: %{}, headers: %{}, method: :get, path: "/", query_params: %{}}}
    assert GRq.new([method: :get, path: "/", headers: %{"x" => "y"}]) == {:ok, %GRq{body: "", cookies: %{}, headers: %{"x" => "y"}, method: :get, path: "/", query_params: %{}}}
    assert GRq.new([])                                                == {:error, {:value_missing, [GRq, {SolomonLib.Http.Method , :method }]}}
    assert GRq.new([method: :get])                                    == {:error, {:value_missing, [GRq, {SolomonLib.EncodedPath , :path   }]}}
    assert GRq.new([path: "/"])                                       == {:error, {:value_missing, [GRq, {SolomonLib.Http.Method , :method }]}}
    assert GRq.new([method: :get, path: "without_slash"])             == {:error, {:invalid_value, [GRq, {SolomonLib.EncodedPath , :path   }]}}
    assert GRq.new([method: :get, path: "/", headers: "not map"])     == {:error, {:invalid_value, [GRq, {SolomonLib.Http.Headers, :headers}]}}
  end

  test "G2gResponse: new/1" do
    alias SolomonLib.G2gResponse, as: GRs
    assert GRs.new([status: 200])                     == {:ok, %GRs{status: 200, headers: %{}, cookies: %{}, body: ""}}
    assert GRs.new([status: 200, body: "valid body"]) == {:ok, %GRs{status: 200, headers: %{}, cookies: %{}, body: "valid body", }}
    assert GRs.new([status: 200, headers: "not_map"]) == {:error, {:invalid_value, [GRs, {SolomonLib.Http.Headers   , :headers}]}}
    assert GRs.new([status: :ok])                     == {:error, {:invalid_value, [GRs, {SolomonLib.Http.Status.Int, :status }]}}
    assert GRs.new([])                                == {:error, {:value_missing, [GRs, {SolomonLib.Http.Status.Int, :status }]}}
  end
end
