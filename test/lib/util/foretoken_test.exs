# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ForeTokenTest do
  use Croma.TestCase
  alias Croma.Result, as: R
  alias Antikythera.ForeToken

  test "should use different bucket if executor_pool is different" do
    assert ForeToken.take({:gear, :gear1}, "bucket_name", 100, 1, 1) == :ok
    assert ForeToken.take({:gear, :gear2}, "bucket_name", 100, 1, 1) == :ok
  end

  test "should use same bucket if executor_pool is same" do
    assert ForeToken.take({:gear, :gear1}, "same_bucket_name", 100, 1, 1) == :ok
    assert R.error?(ForeToken.take({:gear, :gear1}, "same_bucket_name", 100, 1, 1))
  end
end
