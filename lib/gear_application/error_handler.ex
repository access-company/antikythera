# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.ErrorHandler do
  @moduledoc """
  Helper module for gear's custom error handler.

  To customize HTTP responses returned on errors, gear must implement an error handler module which

  - is named `YourGear.Controller.Error`, and
  - defines the following functions:
      - Mandatory error handlers
          - `error(Antikythera.Conn.t, Antikythera.ErrorReason.gear_action_error_reason) :: Antikythera.Conn.t`
          - `no_route(Antikythera.Conn.t) :: Antikythera.Conn.t`
          - `bad_request(Antikythera.Conn.t) :: Antikythera.Conn.t`
      - Optional error handlers
          - `bad_executor_pool_id(Antikythera.Conn.t, Antikythera.ExecutorPool.BadIdReason.t) :: Antikythera.Conn.t`
          - `ws_too_many_connections(Antikythera.Conn.t) :: Antikythera.Conn.t` (when your gear uses websocket)

  This module generates `YourGear.error_handler_module/0` function, which is called by antikythera when handling errors.
  """

  alias Antikythera.GearName
  alias AntikytheraCore.GearModule

  @all_handlers [
    error: 2,
    no_route: 1,
    bad_request: 1
  ]

  @doc false
  defun find_error_handler_module(gear_name :: v[GearName.t()]) :: nil | module do
    # during compilation of gear, allowed to call unsafe function
    mod = GearModule.error_handler_unsafe(gear_name)

    try do
      exported_funs = mod.module_info(:exports)
      not_defined_handlers = Enum.reject(@all_handlers, &(&1 in exported_funs))

      if Enum.empty?(not_defined_handlers) do
        mod
      else
        IO.puts("""
        [antikythera] warning: #{mod} exists but some of the error handlers are not defined: #{
          inspect(not_defined_handlers)
        };
        [antikythera]   #{mod} is not eligible for a custom error handler module.
        """)

        nil
      end
    rescue
      # module not defined
      UndefinedFunctionError -> nil
    end
  end

  defmacro __using__(_) do
    quote do
      # Assuming that module attribute `@gear_name` is defined in the __CALLER__'s context
      @error_handler_module Antikythera.GearApplication.ErrorHandler.find_error_handler_module(
                              @gear_name
                            )
      defun error_handler_module() :: nil | module do
        @error_handler_module
      end
    end
  end
end
