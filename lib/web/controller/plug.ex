# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Controller.Plug do
  @moduledoc """
  Macro definition for plug DSL.

  "Plug" is a specification of composable modules for web apps.
  For example, you can define your authentication logic as a plug and apply it to all your controller actions.

  ## Usage

  To use plug you must first add `use Antikythera.Controller` in your controller module.
  Then you can invoke `plug/3` macro as follows.

      plug Antikythera.Plug.BasicAuthentication, :check_with_config, []

  The arguments are

  1. module
  2. function name
  3. options to be passed to plug function
  4. (optional) options for enabling plug

  In this case `Antikythera.Plug.BasicAuthentication.check_with_config/2` is invoked just before execution of actions
  defined in this controller module.
  If you want to skip running plug for some actions in a controller module, you can use `:except` or `:only` option.

      plug YourGear.SomePlug1, :do_something, [], [except: [:action_x, :action_y]]
      plug YourGear.SomePlug2, :do_something, [], [only: [:action_x]]
  """

  defmacro __using__(_opts) do
    quote do
      import Antikythera.Controller.Plug
      Module.register_attribute(__MODULE__, :plugs, accumulate: true)
      @before_compile Antikythera.Controller.Plug
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @plugs_reversed Enum.reverse(@plugs)

      def __action__(conn, action) do
        # Be careful when you edit the body of this function: changes won't be applied until all gears are re-compiled.
        Antikythera.Controller.Plug._run_action(conn, action, __MODULE__, @plugs_reversed)
      end
    end
  end

  defmacro plug(mod, func, plug_arg, opts \\ []) when is_atom(func) do
    plug_impl(mod, func, plug_arg, opts)
  end

  defp plug_impl(module, func, plug_arg, opts) do
    except = Keyword.get(opts, :except, [])
    only   = Keyword.get(opts, :only  , [])
    if !Enum.all?(except, &is_atom/1), do: raise ":except must be a list of action names (atoms)"
    if !Enum.all?(only  , &is_atom/1), do: raise ":only must be a list of action names (atoms)"
    if !Enum.empty?(except) and !Enum.empty?(only), do: raise "either :except or :only must be empty"
    quote bind_quoted: [module: module, func: func, plug_arg: plug_arg, except: except, only: only] do
      @plugs {module, func, plug_arg, except, only}
    end
  end

  @doc false
  def _run_action(conn, action, controller, plugs_reversed) do
    AntikytheraCore.GearLog.ContextHelper.set(conn)
    plugs =
      Enum.filter(plugs_reversed, fn
        {_, _, _, []            , []          } -> true
        {_, _, _, except_actions, []          } -> action not in except_actions
        {_, _, _, []            , only_actions} -> action in only_actions
      end)
    run_action_with_plugs(conn, controller, action, plugs)
  end

  defp run_action_with_plugs(conn, controller, action, []) do
    apply(controller, action, [conn])
  end
  defp run_action_with_plugs(conn, controller, action, [{mod, fun, arg, _except, _only} | plugs]) do
    %Antikythera.Conn{status: status} = conn2 = apply(mod, fun, [conn, arg])
    case status do
      nil -> run_action_with_plugs(conn2, controller, action, plugs)
      _   -> conn2
    end
  end
end
