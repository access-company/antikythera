# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.GearApplication.Logger do
  @moduledoc """
  Helper module to define each gear's `Logger` module.
  """

  defmacro __using__(_) do
    quote unquote: false do
      defmodule Logger do
        for level <- [:debug, :info, :error] do
          @spec unquote(level)(String.t) :: :ok
          def unquote(level)(msg) when is_binary(msg) do
            AntikytheraCore.GearLog.Writer.unquote(level)(__MODULE__, msg)
          end
        end
      end
    end
  end
end
