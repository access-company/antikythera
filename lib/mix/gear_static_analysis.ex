# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

# `Module.concat` is safe because mix task runs in a separate process.
# credo:disable-for-this-file Credo.Check.Warning.UnsafeToAtom

defmodule Mix.Tasks.Compile.GearStaticAnalysis do
  @moduledoc """
  Statically checks issues in gear's source code.

  Since antikythera is designed to run multiple gears within an ErlangVM, it assumes that each gear

  - is implemented so that it can run side-by-side with other gears, and
  - does not disturb resource allocation controlled by antikythera.

  This task is integrated into `mix compile` command so that these issues are detected each time gear's source code is compiled.
  """

  use Mix.Task.Compiler
  alias Antikythera.MacroUtil

  def run(_) do
    Mix.Project.config()[:elixirc_paths]
    |> Enum.flat_map(fn dir ->
      Path.wildcard(Path.join([dir, "**", "*.ex"]))
    end)
    |> Enum.flat_map(&find_issues_in_file/1)
    |> report()
  end

  defp find_issues_in_file(ex_file_path) do
    File.read!(ex_file_path)
    |> Code.string_to_quoted!()
    |> Macro.prewalk([], fn
      {:defmodule, meta, [{:__aliases__, _, atoms}, [do: body]]}, acc ->
        {issue_or_nil, tool?} =
          check_toplevel_module_name(Module.concat(atoms), meta, ex_file_path)

        check_module_body(body, List.wrap(issue_or_nil) ++ acc, ex_file_path, tool?)

      {:defimpl, meta,
       [{:__aliases__, _, protocol_atoms}, [for: {:__aliases__, _, mod_atoms}], [do: body]]},
      acc ->
        issue_or_nil =
          check_defimpl(
            Module.concat(protocol_atoms),
            Module.concat(mod_atoms),
            meta,
            ex_file_path
          )

        check_module_body(body, List.wrap(issue_or_nil) ++ acc, ex_file_path, false)

      n, acc ->
        {n, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp check_toplevel_module_name(mod, meta, file) do
    # Compare module name prefix as String.t, in order not to be confused by the difference between e.g. `Mix` and `:Mix`.
    gear_name_camel = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()

    case Module.split(mod) do
      [^gear_name_camel | _] ->
        {nil, false}

      ["Mix", ^gear_name_camel | _] ->
        {nil, true}

      ["Mix", "Tasks", ^gear_name_camel | _] ->
        {nil, true}

      _ ->
        {{:error, file, meta, "module name `#{inspect(mod)}` is not prefixed with the gear name"},
         false}
    end
  end

  defp check_defimpl(protocol, mod, meta, file) do
    # `defimpl` can be at the toplevel or within `defmodule`; we have to take the both cases into account.
    gear_name_camel = Mix.Project.config()[:app] |> Atom.to_string() |> Macro.camelize()

    case Module.split(protocol) do
      [^gear_name_camel | _] ->
        nil

      _ ->
        case Module.split(mod) do
          [^gear_name_camel | _] ->
            nil

          _ ->
            {:error, file, meta,
             "implementing non-gear-specific protocol for non-gear-specific type can affect other projects and is thus prohibited"}
        end
    end
  end

  defp check_module_body(body, acc, file, tool?) do
    # Since we want to employ different rules for (1) production code and (2) mix task (tool),
    # we need to traverse the module body with different accumulator function.
    issues =
      MacroUtil.prewalk_accumulate(body, [], fn n, acc2 ->
        List.wrap(check_ast_node(n, file, tool?)) ++ acc2
      end)

    # don't walk into the module body further by returning `nil`
    {nil, issues ++ acc}
  end

  defp check_ast_node(n, file, tool?) do
    case n do
      {:defimpl, meta,
       [{:__aliases__, _, protocol_atoms}, [for: {:__aliases__, _, mod_atoms}], [do: _block]]} ->
        # We don't have to check `defimpl` without `for:`, as the enclosing module's name is enforced to be properly prefixed by gear name.
        check_defimpl(Module.concat(protocol_atoms), Module.concat(mod_atoms), meta, file)

      {:use, meta, [{:__aliases__, _, atoms} | kw]} ->
        with_concatenated_module_atom(atoms, fn mod ->
          check_use_within_module(mod, kw, meta, file, tool?)
        end)

      {{:., _, [{:__aliases__, _, atoms}, fun]}, meta, args} ->
        with_concatenated_module_atom(atoms, fn mod ->
          check_remote_call(mod, fun, args, meta, file, tool?)
        end)

      {{:., _, [erlang_mod, fun]}, meta, args} ->
        check_remote_call(erlang_mod, fun, args, meta, file, tool?)

      {:__aliases__, meta, atoms} ->
        with_concatenated_module_atom(atoms, fn mod ->
          check_module(mod, meta, file, tool?)
        end)

      {fun, meta, args} when is_atom(fun) and is_list(args) ->
        check_local_call(fun, args, meta, file, tool?)

      atom when is_atom(atom) ->
        check_atom(atom, file)

      _ ->
        nil
    end
  end

  defp with_concatenated_module_atom(atoms, f) do
    # exclude module aliases such as `__MODULE__.Foo` by returning `nil`
    if Enum.all?(atoms, &is_atom/1) do
      f.(Module.concat(atoms))
    end
  end

  defp check_use_within_module(Gettext, _kw, _meta, file, _tool?) do
    {:error, file, [],
     "directly invoking `use Gettext` is not allowed (`use Antikythera.Gettext` instead)"}
  end

  defp check_use_within_module(_mod, _kw, _meta, _file, _tool?), do: nil

  defguardp writing_to_stdout?(args)
            when is_list(args) and (length(args) == 1 or hd(args) == :stdio)

  defp check_remote_call(mod, fun, args, meta, file, false) do
    with :ok <- check_disturbing_execution_of_vm(mod, fun),
         :ok <- check_writing_to_stdout(mod, fun, args),
         :ok <- check_spawning_process(mod, fun),
         :ok <- check_executing_shell_command(mod, fun) do
      nil
    else
      {severity, message} -> {severity, file, meta, message}
    end
  end

  defp check_remote_call(_mod, _fun, _args, _meta, _file, _tool?), do: nil

  defp check_disturbing_execution_of_vm(mod, fun) do
    if disturbing_execution_of_vm?(mod, fun) do
      {:error, "disturbing execution of ErlangVM is strictly prohibited"}
    else
      :ok
    end
  end

  defp disturbing_execution_of_vm?(System, fun) when fun in [:halt, :stop], do: true
  defp disturbing_execution_of_vm?(:erlang, :halt), do: true
  defp disturbing_execution_of_vm?(:init, _fun), do: true
  defp disturbing_execution_of_vm?(_mod, _fun), do: false

  defp check_writing_to_stdout(IO, fun, args)
       when fun in [:inspect, :puts, :write] and writing_to_stdout?(args) do
    severity = if Mix.env() == :prod, do: :error, else: :warning

    {severity,
     "writing to STDOUT/STDERR is not allowed in prod environment (use each gear's logger instead)"}
  end

  defp check_writing_to_stdout(_mod, _fun, _args), do: :ok

  defp check_spawning_process(mod, fun) when mod in [Process, Task, Agent] do
    if spawning_a_new_process?(Atom.to_string(fun)) do
      {:error, "spawning processes in gear's code is prohibited"}
    else
      :ok
    end
  end

  defp check_spawning_process(_mod, _fun), do: :ok

  defp check_executing_shell_command(:os, :cmd) do
    {:error, "calling :os.cmd/1 in gear's code is prohibited"}
  end

  defp check_executing_shell_command(System, :cmd) do
    if use_antikythera_internal_modules?() do
      :ok
    else
      {:error, "calling System.cmd/3 in gear's code is prohibited"}
    end
  end

  defp check_executing_shell_command(_mod, _fun), do: :ok

  defp spawning_a_new_process?("start" <> _), do: true
  defp spawning_a_new_process?("spawn" <> _), do: true
  defp spawning_a_new_process?("async" <> _), do: true
  defp spawning_a_new_process?(_), do: false

  defp check_local_call(fun, _args, meta, file, _tool?) do
    if Atom.to_string(fun) |> String.starts_with?("spawn") do
      {:error, file, meta, "spawning processes in gear's code is prohibited"}
    end
  end

  defp check_module(mod, meta, file, tool?) do
    [
      check_module_prefix(mod, meta, file, tool?),
      check_deprecated_libraries(mod, meta, file)
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
      ["AntikytheraCore" | _] ->
        {:error, file, meta, "direct use of `AntikytheraCore.*` is prohibited"}

      ["AntikytheraEal" | _] ->
        {:error, file, meta, "direct use of `AntikytheraEal.*` is prohibited"}

      ["AntikytheraLocal" | _] ->
        {:error, file, meta, "direct use of `AntikytheraLocal.*` is prohibited"}

      _ ->
        nil
    end
  end

  defp check_test_only_modules(mod_str, meta, file, tool?) do
    if !tool? do
      case String.split(mod_str, ".") do
        ["Antikythera", "Test" | _] ->
          {:error, file, meta, "using `Antikythera.Test.*` in production code is prohibited"}

        _ ->
          nil
      end
    end
  end

  defp check_task_only_modules(mod_str, meta, file, tool?) do
    if !tool? do
      case String.split(mod_str, ".") do
        ["Antikythera", "Mix", "Task" | _] ->
          {:error, file, meta, "`Antikythera.Mix.Task.*` can only be used in mix tasks"}

        _ ->
          nil
      end
    end
  end

  defp check_deprecated_libraries(_mod, _meta, _file) do
    # currently there's nothing to check
    nil
  end

  defp check_atom(atom, file) do
    case atom do
      :hackney ->
        {:warning, file, [],
         "directly depending on `:hackney` is not allowed (for `Antikythera.Httpc` use other options; for initialization of HTTP client library in your mix tasks use `Antikythera.Mix.Task.prepare_antikythera_instance/0`)"}

      _ ->
        nil
    end
  end

  defp report(issues) do
    mod_name = Module.split(__MODULE__) |> List.last()
    prefix = "[#{mod_name}]"

    Enum.each(issues, fn
      {:warning, file, meta, msg} ->
        IO.puts("#{prefix} #{file}:#{meta[:line]} WARNING #{msg}")

      {:error, file, meta, msg} ->
        IO.puts(
          IO.ANSI.red() <> "#{prefix} #{file}:#{meta[:line]} ERROR #{msg}" <> IO.ANSI.reset()
        )
    end)

    {warnings, errors} = Enum.split_with(issues, &match?({:warning, _, _, _}, &1))
    n_warnings = length(warnings)
    n_errors = length(errors)

    cond do
      n_errors > 0 ->
        Mix.raise(
          "#{prefix} Found #{n_errors} errors and #{n_warnings} warnings. Please fix them and try again."
        )

      n_warnings > 0 ->
        {IO.puts("#{prefix} Found #{n_warnings} warnings."), []}

      true ->
        {:ok, []}
    end
  end
end
