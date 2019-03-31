# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.TokenBucketTest do
  use Croma.TestCase
  alias Croma.Result, as: R

  test "should use different bucket if executor_pool is different" do
    assert TokenBucket.take({:gear, :gear1}, "bucket_name", 100, 1, 1) == :ok
    assert TokenBucket.take({:gear, :gear2}, "bucket_name", 100, 1, 1) == :ok
  end

  test "should use same bucket if executor_pool is same" do
    assert TokenBucket.take({:gear, :gear1}, "same_bucket_name", 100, 1, 1) == :ok
    assert R.error?(TokenBucket.take({:gear, :gear1}, "same_bucket_name", 100, 1, 1))
  end
end
