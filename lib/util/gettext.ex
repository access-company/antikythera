# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Gettext do
  @moduledoc """
  A thin wrapper around `Gettext.__using__/1` to forward error logs to each gear's logger.

  Usage of this module is exactly the same as `Gettext`; just `use #{inspect(__MODULE__)}` instead of `use Gettext`.
  Options given to `#{inspect(__MODULE__)}.__using__/1` are directly passed to `Gettext.__using__/1`.
  This module overrides the default implementation of `c:Gettext.Backend.handle_missing_bindings/2`
  to suit the use cases for antikythera gears.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Gettext, opts

      gear_name = Mix.Project.config()[:app]
      @logger_module AntikytheraCore.GearModule.logger_unsafe(gear_name)

      def handle_missing_bindings(exception, incomplete) do
        _ = @logger_module.error(Exception.message(exception))
        incomplete
      end
    end
  end
end
