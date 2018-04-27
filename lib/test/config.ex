# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.Config do
  @moduledoc """
  Helpers to be used in each gear's `test/test_helper.exs`.

  At the top of `test/test_helper.exs`, all gears must place the following line:

      Antikythera.Test.Config.init()

  This line will start [`ExUnit`](http://elixir-lang.org/docs/stable/ex_unit/) and
  set configurations for whitebox/blackbox test mode.
  """

  alias AntikytheraCore.Handler.CowboyRouting

  deployment_envs = Application.fetch_env!(:antikythera, :deployments) |> Keyword.keys()

  def init() do
    ExUnit.start()
    if blackbox_test?() do
      ExUnit.configure(exclude: [:test], include: [:blackbox, :blackbox_only])
      IO.puts("Target base URL: #{base_url()}")
    else
      ExUnit.configure(exclude: [:blackbox_only])
    end
  end

  def base_url() do
    gear_name = Mix.Project.config()[:app]
    case test_mode() do
      :whitebox       -> "http://#{CowboyRouting.default_domain(gear_name, :local)}:#{Antikythera.Env.port_to_listen()}"
      :blackbox_local -> "http://#{CowboyRouting.default_domain(gear_name, :local)}:#{System.get_env("TEST_PORT") || 8080}"
      other_env       -> base_url_for_deployment(gear_name, other_env)
    end
  end

  Enum.each(deployment_envs, fn env ->
    defp base_url_for_deployment(gear_name, unquote(:"blackbox_#{env}")) do
      "https://" <> CowboyRouting.default_domain(gear_name, unquote(env))
    end
  end)

  def blackbox_test?(), do: test_mode() != :whitebox

  def test_mode() do
    case System.get_env("TEST_MODE") do
      nil              -> :whitebox
      "blackbox_local" -> :blackbox_local
      other            -> test_mode_for_deployment(other)
    end
  end

  Enum.each(deployment_envs, fn env ->
    defp test_mode_for_deployment(unquote("blackbox_#{env}")), do: :"blackbox_#{unquote(env)}"
  end)

  def blackbox_test_secret() do
    env_var_name = "BLACKBOX_TEST_SECRET_JSON"
    case System.get_env(env_var_name) do
      nil -> raise "Environment variable `#{env_var_name}` not found!"
      s   -> Poison.decode!(s)
    end
  end
end
