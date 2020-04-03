# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.ConfigTest do
  use Croma.TestCase

  test "whitebox_test_secret/0 should read WHITEBOX_TEST_SECRET_JSON environment variable" do
    env_var_name = "WHITEBOX_TEST_SECRET_JSON"
    original = System.get_env(env_var_name)
    System.put_env(env_var_name, ~S({"foo": "bar"}))
    assert Antikythera.Test.Config.whitebox_test_secret()["foo"] == "bar"
    case original do
      nil -> System.delete_env(env_var_name)
      v   -> System.put_env(env_var_name, v)
    end
  end

  test "blackbox_test_secret/0 should read BLACKBOX_TEST_SECRET_JSON environment variable" do
    env_var_name = "BLACKBOX_TEST_SECRET_JSON"
    original = System.get_env(env_var_name)
    System.put_env(env_var_name, ~S({"foo": "bar"}))
    assert Config.blackbox_test_secret()["foo"] == "bar"
    case original do
      nil -> System.delete_env(env_var_name)
      v   -> System.put_env(env_var_name, v)
    end
  end
end
