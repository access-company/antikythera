# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.Compile.GearStaticAnalysis do
  @moduledoc """
  Statically checks issues in gear's source code.

  Since antikythera is designed to run multiple gears within an ErlangVM, it assumes that each gear

  - is implemented so that it can run side-by-side with other gears, and
  - does not disturb resource allocation controlled by antikythera.

  This task is integrated into `mix compile` command so that these issues are detected each time gear's source code is compiled.
  """

  use Mix.Task # change this to `Mix.Task.Compiler` when upgrading to Elixir v1.6.0
  alias Antikythera.MacroUtil

  def run(_) do
    Mix.Project.config()[:elixirc_paths]
    |> Enum.flat_map(fn(dir) ->
      Path.wildcard(Path.join([dir, "**", "*.ex"]))
    end)
    |> Enum.flat_map(&find_issues_in_file/1)
    |> report()
  end

  defp find_issues_in_file(ex_file_path) do
    find_issue = make_function_to_find_issue(ex_file_path)
    File.read!(ex_file_path)
    |> Code.string_to_quoted!()
    |> Macro.prewalk([], find_issue)
    |> elem(1)
    |> Enum.reverse()
  end

  defp make_function_to_find_issue(ex_file_path) do
    fn
      ({:defmodule, meta, [{:__aliases__, _, atoms}, [do: body]]}, acc) ->
        find_issue_in_module(meta, atoms, body, acc, ex_file_path)
      ({:defimpl, meta, [{:__aliases__, _, protocol_atoms}, [for: {:__aliases__, _, mod_atoms}], [do: body]]}, acc) ->
        find_issue_in_impl(meta, protocol_atoms, mod_atoms, body, acc, ex_file_path)
      (n, acc) ->
        {n, acc}
    end
  end

  defp find_issue_in_module(meta, atoms, body, acc, ex_file_path) do
    concated_atoms = Module.safe_concat(atoms)
    {issue_or_nil, tool?} = check_toplevel_module_name(concated_atoms, meta, ex_file_path)
    check_module_body(body, List.wrap(issue_or_nil) ++ acc, ex_file_path, tool?)
  end

  defp find_issue_in_impl(meta, protocol_atoms, mod_atoms, body, acc, ex_file_path) do
    concated_protocol_atoms = Module.safe_concat(protocol_atoms)
    concated_mod_atoms = Module.safe_concat(mod_atoms)
    issue_or_nil = check_defimpl(concated_protocol_atoms, concated_mod_atoms, meta, ex_file_path)
    check_module_body(body, List.wrap(issue_or_nil) ++ acc, ex_file_path, false)
  end

  defp check_toplevel_module_name(mod, meta, file) do
    # Compare module name prefix as String.t, in order not to be confused by the difference between e.g. `Mix` and `:Mix`.
    gear_name_camel = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
    case Module.split(mod) do
      [^gear_name_camel | _]                 -> {nil, false}
      ["Mix", ^gear_name_camel | _]          -> {nil, true}
      ["Mix", "Tasks", ^gear_name_camel | _] -> {nil, true}
      _                                      -> {{:error, file, meta, "module name `#{inspect(mod)}` is not prefixed with the gear name"}, false}
    end
  end

  defp check_defimpl(protocol, mod, meta, file) do
    # `defimpl` can be at the toplevel or within `defmodule`; we have to take the both cases into account.
    gear_name_camel = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()
    case Module.split(protocol) do
      [^gear_name_camel | _] -> nil
      _                      ->
        case Module.split(mod) do
          [^gear_name_camel | _] -> nil
          _                      -> {:error, file, meta, "implementing non-gear-specific protocol for non-gear-specific type can affect other projects and is thus prohibited"}
        end
    end
  end

  defp check_module_body(body, acc, file, tool?) do
    # Since we want to employ different rules for (1) production code and (2) mix task (tool),
    # we need to traverse the module body with different accumulator function.
    issues =
      MacroUtil.prewalk_accumulate(body, [], fn(n, acc2) ->
        List.wrap(check_ast_node(n, file, tool?)) ++ acc2
      end)
    {nil, issues ++ acc} # don't walk into the module body further by returning `nil`
  end

  defp check_ast_node({:defimpl, meta, [{:__aliases__, _, protocol_atoms},
                                        [for: {:__aliases__, _, mod_atoms}],
                                        [do: _block]]},
                      file,
                      _tool?) do
    concated_protocol_atoms = Module.safe_concat(protocol_atoms)
    concated_mod_atoms = Module.safe_concat(mod_atoms)
    # We don't have to check `defimpl` without `for:`, as the enclosing module's name is enforced to be properly prefixed by gear name.
    check_defimpl(concated_protocol_atoms, concated_mod_atoms, meta, file)
  end

  defp check_ast_node({:use, meta, [{:__aliases__, _, atoms} | kw]}, file, _tool?) do
    with_concatenated_module_atom(atoms, fn mod ->
      check_use_within_module(mod, kw, meta, file)
    end)
  end

  defp check_ast_node({{:., _, [{:__aliases__, _, atoms}, fun]}, meta, args}, file, false = _tool?) do
    with_concatenated_module_atom(atoms, fn mod ->
      check_remote_call(mod, fun, args, meta, file)
    end)
  end

  defp check_ast_node({{:., _, [erlang_mod, fun]}, meta, args}, file, false = _tool?) do
    check_remote_call(erlang_mod, fun, args, meta, file)
  end

  defp check_ast_node({:__aliases__, meta, atoms}, file, tool?) do
    with_concatenated_module_atom(atoms, fn mod ->
      check_module(mod, meta, file, tool?)
    end)
  end

  defp check_ast_node({fun, meta, args}, file, _tool?) when is_atom(fun) and is_list(args) do
    check_local_call(fun, args, meta, file)
  end

  defp check_ast_node(atom, file, _tool?) when is_atom(atom) do
    check_atom(atom, file)
  end

  defp check_ast_node(_, _file, _tool?), do: nil

  defp with_concatenated_module_atom(atoms, f) do
    # exclude module aliases such as `__MODULE__.Foo` by returning `nil`
    if Enum.all?(atoms, &is_atom/1) do
      f.(Module.safe_concat(atoms))
    end
  end

  defp check_use_within_module(mod, _kw, _meta, file) do
    if mod == Gettext do
      {:error, file, [], "directly invoking `use Gettext` is not allowed (`use Antikythera.Gettext` instead)"}
    end
  end

  defp check_remote_call(System, fun, _args, meta, file) when fun in [:halt, :stop] do
    {:error, file, meta, "disturbing execution of ErlangVM is strictly prohibited"}
  end

  defp check_remote_call(:erlang, :halt = _fun, _args, meta, file) do
    {:error, file, meta, "disturbing execution of ErlangVM is strictly prohibited"}
  end

  defp check_remote_call(:init, _fun, _args, meta, file) do
    {:error, file, meta, "disturbing execution of ErlangVM is strictly prohibited"}
  end

  defp check_remote_call(IO, fun, args, meta, file) do
    if fun in [:inspect, :puts, :write] and writing_to_stdout?(args) do
      severity = if Mix.env() == :prod, do: :error, else: :warning
      {severity, file, meta, "writing to STDOUT/STDERR is not allowed in prod environment (use each gear's logger instead)"}
    end
  end

  defp check_remote_call(mod, fun, _args, meta, file) when mod in [Process, Task, Agent] do
    if spawning_a_new_process?(Atom.to_string(fun)) do
      {:error, file, meta, "spawning processes in gear's code is prohibited"}
    end
  end

  defp check_remote_call(:os, :cmd = _fun, _args, meta, file) do
    {:error, file, meta, "calling :os.cmd/1 in gear's code is prohibited"}
  end

  defp check_remote_call(System, :cmd = _fun, _args, meta, file) do
    use_internals? = use_antikythera_internal_modules?()
    if !use_internals? do
      {:error, file, meta, "calling System.cmd/3 in gear's code is prohibited"}
    end
  end

  defp check_remote_call(_mod, _fun, _args, _meta, _file), do: nil

  defp writing_to_stdout?([_]         ), do: true
  defp writing_to_stdout?([:stdio | _]), do: true
  defp writing_to_stdout?(_           ), do: false

  defp spawning_a_new_process?("start" <> _), do: true
  defp spawning_a_new_process?("spawn" <> _), do: true
  defp spawning_a_new_process?("async" <> _), do: true
  defp spawning_a_new_process?(_           ), do: false

  defp check_local_call(fun, _args, meta, file) do
    if Atom.to_string(fun) |> String.starts_with?("spawn") do
      {:error, file, meta, "spawning processes in gear's code is prohibited"}
    end
  end

  defp check_module(mod, meta, file, tool?) do
    [
      check_module_prefix(mod, meta, file, tool?),
      check_deprecated_libraries(mod, meta, file),
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp check_module_prefix(mod, meta, file, tool?) do
    mod_str = inspect(mod)
    if use_antikythera_internal_modules?() do
      check_task_only_modules(mod_str, meta, file, tool?) ||
      check_test_only_modules(mod_str, meta, file, tool?)
    else
      check_task_only_modules(mod_str, meta, file, tool?) ||
      check_test_only_modules(mod_str, meta, file, tool?) ||
      check_antikythera_internal_modules(mod_str, meta, file)
    end
  end

  defp use_antikythera_internal_modules?() do
    Mix.Project.config()
    |> Keyword.fetch!(:antikythera_gear)
    |> Keyword.fetch!(:use_antikythera_internal_modules?)
  end

  defp check_antikythera_internal_modules(mod_str, meta, file) do
    case String.split(mod_str, ".") do
      ["AntikytheraCore"  | _] -> {:error, file, meta, "direct use of `AntikytheraCore.*` is prohibited"}
      ["AntikytheraEal"   | _] -> {:error, file, meta, "direct use of `AntikytheraEal.*` is prohibited"}
      ["AntikytheraLocal" | _] -> {:error, file, meta, "direct use of `AntikytheraLocal.*` is prohibited"}
      _                        -> nil
    end
  end

  defp check_test_only_modules(mod_str, meta, file, tool?) do
    if !tool? do
      case String.split(mod_str, ".") do
        ["Antikythera", "Test" | _] -> {:error, file, meta, "using `Antikythera.Test.*` in production code is prohibited"}
        _                           -> nil
      end
    end
  end

  defp check_task_only_modules(mod_str, meta, file, tool?) do
    if !tool? do
      case String.split(mod_str, ".") do
        ["Antikythera", "Mix", "Task" | _] -> {:error, file, meta, "`Antikythera.Mix.Task.*` can only be used in mix tasks"}
        _                                  -> nil
      end
    end
  end

  defp check_deprecated_libraries(_mod, _meta, _file) do
    # currently there's nothing to check
    nil
  end

  defp check_atom(atom, file) do
    case atom do
      :hackney -> {:warning, file, [], "directly depending on `:hackney` is not allowed (for `Antikythera.Httpc` use other options; for initialization of HTTP client library in your mix tasks use `Antikythera.Mix.Task.prepare_antikythera_instance/0`)"}
      _        -> nil
    end
  end

  defp report(issues) do
    mod_name = Module.split(__MODULE__) |> List.last()
    prefix   = "[#{mod_name}]"
    print_issues(issues, prefix)
    {warnings, errors} = Enum.split_with(issues, &match?({:warning, _, _, _}, &1))
    n_warnings = length(warnings)
    n_errors   = length(errors)
    cond do
      n_errors   > 0 -> Mix.raise("#{prefix} Found #{n_errors} errors and #{n_warnings} warnings. Please fix them and try again.")
      n_warnings > 0 -> IO.puts("#{prefix} Found #{n_warnings} warnings.")
      true           -> :ok
    end
  end

  defp print_issues(issues, prefix) do
    Enum.each(issues, fn
      {:warning, file, meta, msg} -> IO.puts("#{prefix} #{file}:#{meta[:line]} WARNING #{msg}")
      {:error  , file, meta, msg} -> IO.puts(IO.ANSI.red() <> "#{prefix} #{file}:#{meta[:line]} ERROR #{msg}" <> IO.ANSI.reset())
    end)
  end
end
