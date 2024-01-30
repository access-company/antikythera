# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraEal.ImplChooser do
  defmacro __using__(_) do
    config_key =
      Module.split(__CALLER__.module)
      |> List.last()
      |> Macro.underscore()
      # during compilation, safe to call `String.to_atom/1`
      |> String.to_atom()

    behaviour_module = Module.safe_concat(__CALLER__.module, "Behaviour")

    quote bind_quoted: [config_key: config_key, behaviour_module: behaviour_module] do
      @behaviour behaviour_module
      impl_module = AntikytheraEal.ImplChooser.extract_impl_module(config_key)

      behaviour_module.behaviour_info(:callbacks)
      |> Enum.each(fn {name, arity} ->
        vars = AntikytheraEal.ImplChooser.make_vars(arity, __MODULE__)
        @impl true
        def unquote(name)(unquote_splicing(vars)) do
          # Use `apply/3` to avoid xref warnings about unavailability of `impl_module`
          # (`impl_module` can be defined by a mix project invisible from `:antikythera`).
          apply(unquote(impl_module), unquote(name), unquote(vars))
        end
      end)
    end
  end

  def make_vars(n, module) do
    # Works even if `n == 0`
    Enum.drop(0..n, 1)
    |> Enum.map(fn i ->
      # during compilation, safe to generate atoms
      Macro.var(:"arg#{i}", module)
    end)
  end

  def extract_impl_module(config_key) do
    being_compiled_app = Mix.Project.config()[:app]
    Application.fetch_env!(being_compiled_app, :eal_impl_modules) |> Keyword.fetch!(config_key)
  end
end
