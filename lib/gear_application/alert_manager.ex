# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.AlertManager do
  @moduledoc """
  Helper module to define interface module for alerting.
  """

  defmacro __using__(_) do
    quote do
      defmodule AlertManager do
        defun notify(body :: v[String.t]) :: :ok do
          AntikytheraCore.Alert.Manager.notify(__MODULE__, body)
        end
      end
    end
  end
end
