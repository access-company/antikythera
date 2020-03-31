# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

Antikythera.Test.Config.init()

defmodule Antikythera.Test.ConfigTest do
  use Croma.TestCase

  test "blackbox_test_secret/0 should read BLACKBOX_TEST_SECRET_JSON environment variable" do
    env_var_name = "BLACKBOX_TEST_SECRET_JSON"
    original = System.get_env(env_var_name)
    System.put_env(env_var_name, "{\"foo\": \"bar\"}")
    assert Antikythera.Test.Config.blackbox_test_secret()["foo"] == "bar"
    if original != nil do
      System.put_env(env_var_name, original)
    end
  end
end
