# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.TemplateEngine do
  @moduledoc """
  This is an implementation of `EEx.Engine` that auto-escape dynamic parts within HAML templates.
  """

  @behaviour EEx.Engine

  alias Antikythera.TemplateSanitizer

  @impl true
  def init(_opts) do
    %{
      iodata: [],
      dynamic: [],
      vars_count: 0
    }
  end

  @impl true
  def handle_begin(state) do
    %{state | iodata: [], dynamic: []}
  end

  @impl true
  def handle_end(quoted) do
    handle_body(quoted)
  end

  @impl true
  def handle_body(state) do
    %{iodata: iodata, dynamic: dynamic} = state

    q =
      quote do
        IO.iodata_to_binary(unquote(Enum.reverse(iodata)))
      end

    {:__block__, [], Enum.reverse([{:safe, q} | dynamic])}
  end

  @impl true
  def handle_text(state, text) do
    %{iodata: iodata} = state
    %{state | iodata: [text | iodata]}
  end

  @impl true
  def handle_expr(state, "=", expr) do
    %{iodata: iodata, dynamic: dynamic, vars_count: vars_count} = state
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    var = Macro.var(:"arg#{vars_count}", __MODULE__)

    q =
      quote do
        unquote(var) = unquote(to_safe_expr(expr))
      end

    %{state | dynamic: [q | dynamic], iodata: [var | iodata], vars_count: vars_count + 1}
  end

  def handle_expr(state, "", expr) do
    %{dynamic: dynamic} = state
    %{state | dynamic: [expr | dynamic]}
  end

  def handle_expr(state, marker, expr) do
    EEx.Engine.handle_expr(state, marker, expr)
  end

  # For literals we can do the work at compile time
  defp to_safe_expr(s) when is_binary(s), do: TemplateSanitizer.html_escape(s)
  defp to_safe_expr(nil), do: ""
  defp to_safe_expr(a) when is_atom(a), do: TemplateSanitizer.html_escape(Atom.to_string(a))
  defp to_safe_expr(i) when is_integer(i), do: Integer.to_string(i)
  defp to_safe_expr(f) when is_float(f), do: Float.to_string(f)

  # Otherwise we do the work at runtime
  defp to_safe_expr(expr) do
    quote do
      AntikytheraCore.TemplateEngine.to_safe_iodata(unquote(expr))
    end
  end

  def to_safe_iodata({:safe, data}), do: data
  def to_safe_iodata(s) when is_binary(s), do: TemplateSanitizer.html_escape(s)
  def to_safe_iodata(nil), do: ""
  def to_safe_iodata(a) when is_atom(a), do: TemplateSanitizer.html_escape(Atom.to_string(a))
  def to_safe_iodata(i) when is_integer(i), do: Integer.to_string(i)
  def to_safe_iodata(f) when is_float(f), do: Float.to_string(f)
  def to_safe_iodata([]), do: ""
  # convert charlist to String.t
  def to_safe_iodata([h | _] = l) when is_integer(h), do: List.to_string(l)
  def to_safe_iodata([h | t]), do: [to_safe_iodata(h) | to_safe_iodata(t)]
end
