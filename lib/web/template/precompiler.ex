# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.TemplatePrecompiler do
  @moduledoc """
  Definition of macro to precompile HAML templates.

  Each gear's template module (web/template.ex) must use this module as follows:

      defmodule YourGear.Template do
        use Antikythera.TemplatePrecompiler
      end

  HAML files whose paths match `web/template/**/*.html.haml` are loaded and converted into function clauses at compile time.
  To render HAML files in controller actions, use `Antikythera.Conn.render/5`.

  As all macro-generated function clauses of `content_for/2` reside in `YourGear.Template`,
  you can, for example, put `alias` before `use Antikythera.TemplatePrecompiler` so that it takes effect in all HAML templates.
  """

  alias Antikythera.MacroUtil
  alias AntikytheraCore.TemplateEngine

  defmacro __using__(_) do
    %Macro.Env{file: caller_filepath, module: module} = __CALLER__
    check_caller_module(module)
    Path.dirname(caller_filepath) |> define_haml_content_funs()
  end

  defp check_caller_module(mod) do
    gear_name_camel = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
    case Module.split(mod) do
      [^gear_name_camel, "Template"] -> :ok
      _                              -> raise "`use #{inspect(__MODULE__)}` is usable only in `#{gear_name_camel}.Template`"
    end
  end

  defp define_haml_content_funs(dir) do
    haml_paths = Path.wildcard(Path.join([dir, "template", "**", "*.html.haml"]))
    if Enum.empty?(haml_paths) do
      []
    else
      clause_header =
        quote do
          @spec content_for(String.t, Keyword.t(any)) :: {:safe, String.t}
          def content_for(name, params \\ [])
        end
      clauses = Enum.map(haml_paths, &define_haml_content_fun(dir, &1))
      [clause_header | clauses]
    end
  end

  defp define_haml_content_fun(dir, path) do
    name           = path |> Path.relative_to(Path.join(dir, "template")) |> String.replace_suffix(".html.haml", "")
    eex_content    = path |> File.read!() |> Calliope.Render.precompile()
    quoted_content = EEx.compile_string(eex_content, [file: path, engine: TemplateEngine])
    var_names      = extract_free_vars_in_quoted(quoted_content)
    quote do
      # file modifications are tracked by `PropagateFileModifications`; `@external_resource` here would be redundant
      def content_for(unquote(name), params) do
        import Antikythera.TemplateSanitizer
        unquote(Enum.map(var_names, &Macro.var(&1, nil))) = Enum.map(unquote(var_names), &Keyword.fetch!(params, &1))
        unquote(quoted_content)
      end
    end
  end

  defp extract_free_vars_in_quoted(q) do
    {free_vars_map, _} = MacroUtil.prewalk_accumulate(q, {%{}, MapSet.new()}, &extract_vars_in_ast_node/2)
    for {var_name, count} <- free_vars_map, count > 0, do: var_name
  end

  defp extract_vars_in_ast_node({:::, _, [_, {:binary, _, nil}]}, {acc_free, acc_bound} = _acc) do
    {Map.update(acc_free, :binary, -1, &(&1 - 1)), acc_bound} # cancel count of type expr in AST of string interpolation
  end

  defp extract_vars_in_ast_node({:=, _, [lhs, _rhs]}, {acc_free, acc_bound} = _acc) do
    {acc_free, MapSet.union(collect_vars(lhs), acc_bound)}
  end

  defp extract_vars_in_ast_node({:<-, _, [lhs, _rhs]}, {acc_free, acc_bound} = _acc) do
    {acc_free, MapSet.union(collect_vars(lhs), acc_bound)}
  end

  defp extract_vars_in_ast_node({:->, _, [[lhs | _guards], _rhs]}, {acc_free, acc_bound} = _acc) do
    {acc_free, MapSet.union(collect_vars(lhs), acc_bound)}
  end

  defp extract_vars_in_ast_node({name, _, nil}, {acc_free, acc_bound} = acc) do
    if name in acc_bound, do: acc, else: {Map.update(acc_free, name, 1, &(&1 + 1)), acc_bound}
  end

  defp extract_vars_in_ast_node(_, acc), do: acc

  defunp collect_vars(q :: Macro.t) :: MapSet.t do
    MacroUtil.prewalk_accumulate(q, [], fn(t, acc) ->
      case t do
        {name, _, nil} when is_atom(name) -> [name | acc]
        _                                 -> acc
      end
    end)
    |> MapSet.new()
  end
end
