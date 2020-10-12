# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.ConfigTest do
  use Croma.TestCase

  defp assert_test_secret(env_var_name, secret_getter) do
    original = System.get_env(env_var_name)
    System.put_env(env_var_name, ~S({"foo": "bar"}))
    assert secret_getter.()["foo"] == "bar"

    case original do
      nil -> System.delete_env(env_var_name)
      v -> System.put_env(env_var_name, v)
    end
  end

  test "whitebox_test_secret/0 should read WHITEBOX_TEST_SECRET_JSON environment variable" do
    assert_test_secret("WHITEBOX_TEST_SECRET_JSON", &Config.whitebox_test_secret/0)
  end

  test "blackbox_test_secret/0 should read BLACKBOX_TEST_SECRET_JSON environment variable" do
    assert_test_secret("BLACKBOX_TEST_SECRET_JSON", &Config.blackbox_test_secret/0)
  end
end
