# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.Config do
  @moduledoc """
  Helpers to be used in each gear's `test/test_helper.exs`.

  At the top of `test/test_helper.exs`, all gears must place the following line:

      Antikythera.Test.Config.init()

  This line will start [`ExUnit`](http://elixir-lang.org/docs/stable/ex_unit/) and
  set configurations for whitebox/blackbox test mode.
  """

  alias AntikytheraCore.Handler.CowboyRouting
  alias AntikytheraCore.GearManager
  alias AntikytheraCore.GearModule

  # TODO: remove when upgrading to Elixir v1.10+ where this timeout is infinity
  @long_module_load_timeout 600_000

  deployment_envs = Application.fetch_env!(:antikythera, :deployments) |> Keyword.keys()

  def init() do
    System.at_exit(fn _ -> stop_gear_supervisors() end)

    ExUnit.start()

    if blackbox_test?() do
      ExUnit.configure(
        exclude: [:test],
        include: [:blackbox, :blackbox_only],
        module_load_timeout: @long_module_load_timeout
      )

      IO.puts("Target base URL: #{base_url()}")
    else
      ExUnit.configure(exclude: [:blackbox_only], module_load_timeout: @long_module_load_timeout)
    end
  end

  # Explicit termination of gear's supervisor is required to ensure that
  # the gear's logger gracefully closes its log file.
  defp stop_gear_supervisors() do
    GearManager.running_gear_names()
    |> Enum.each(fn gear_name ->
      :ok =
        gear_name
        |> GearModule.root_supervisor()
        |> Supervisor.stop()
    end)
  end

  def base_url() do
    gear_name = Mix.Project.config()[:app]

    case test_mode() do
      :whitebox ->
        "http://#{CowboyRouting.default_domain(gear_name, :local)}:#{
          Antikythera.Env.port_to_listen()
        }"

      :blackbox_local ->
        "http://#{CowboyRouting.default_domain(gear_name, :local)}:#{
          System.get_env("TEST_PORT") || 8080
        }"

      other_env ->
        base_url_for_deployment(gear_name, other_env)
    end
  end

  Enum.each(deployment_envs, fn env ->
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    defp base_url_for_deployment(gear_name, unquote(:"blackbox_#{env}")) do
      "https://" <> CowboyRouting.default_domain(gear_name, unquote(env))
    end
  end)

  def blackbox_test?(), do: test_mode() != :whitebox

  def test_mode() do
    case System.get_env("TEST_MODE") do
      nil -> :whitebox
      "blackbox_local" -> :blackbox_local
      other -> test_mode_for_deployment(other)
    end
  end

  Enum.each(deployment_envs, fn env ->
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    defp test_mode_for_deployment(unquote("blackbox_#{env}")), do: :"blackbox_#{unquote(env)}"
  end)

  defp test_secret(env_var_name) do
    case System.get_env(env_var_name) do
      nil -> raise "Environment variable `#{env_var_name}` not found!"
      s -> Poison.decode!(s)
    end
  end

  def whitebox_test_secret() do
    test_secret("WHITEBOX_TEST_SECRET_JSON")
  end

  def blackbox_test_secret() do
    test_secret("BLACKBOX_TEST_SECRET_JSON")
  end
end
