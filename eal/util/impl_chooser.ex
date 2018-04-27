# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraEal.ImplChooser do
  defmacro __using__(_) do
    config_key =
      Module.split(__CALLER__.module)
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom() # during compilation, safe to call `String.to_atom/1`
    behaviour_module = Module.safe_concat(__CALLER__.module, "Behaviour")
    quote bind_quoted: [config_key: config_key, behaviour_module: behaviour_module] do
      @behaviour behaviour_module
      impl_module = AntikytheraEal.ImplChooser.extract_impl_module(config_key)
      behaviour_module.behaviour_info(:callbacks)
      |> Enum.each(fn {name, arity} ->
        vars = AntikytheraEal.ImplChooser.make_vars(arity, __MODULE__)
        defdelegate unquote(name)(unquote_splicing(vars)), to: impl_module
      end)
    end
  end

  def make_vars(n, module) do
    Enum.drop(0..n, 1)
    |> Enum.map(fn i ->
      Macro.var(:"arg#{i}", module) # during compilation, safe to generate atoms
    end)
  end

  def extract_impl_module(config_key) do
    being_compiled_app = Mix.Project.config()[:app]
    Application.fetch_env!(being_compiled_app, :eal_impl_modules) |> Keyword.fetch!(config_key)
  end
end
