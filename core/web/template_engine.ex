# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.TemplateEngine do
  @moduledoc """
  This is an implementation of `EEx.Engine` that auto-escape dynamic parts within HAML templates.
  """

  use EEx.Engine
  alias Antikythera.TemplateSanitizer

  def init(_opts), do: {:safe, ""}

  def handle_body({:safe, iodata}) do
    q =
      quote do
        IO.iodata_to_binary(unquote(iodata))
      end
    {:safe, q}
  end

  def handle_text("", text) do
    handle_text({:safe, ""}, text)
  end
  def handle_text({:safe, buffer}, text) do
    q = quote do: [unquote(buffer) | unquote(text)]
    {:safe, q}
  end

  def handle_expr("", marker, expr) do
    handle_expr({:safe, ""}, marker, expr)
  end
  def handle_expr({:safe, buffer}, "=", expr) do
    q =
      quote do
        tmp = unquote(buffer)
        [tmp | unquote(to_safe_expr(expr))]
      end
    {:safe, q}
  end
  def handle_expr({:safe, buffer}, "", expr) do
    q =
      quote do
        tmp = unquote(buffer)
        unquote(expr)
        tmp
      end
    {:safe, q}
  end

  # For literals we can do the work at compile time
  defp to_safe_expr(s) when is_binary(s) , do: TemplateSanitizer.html_escape(s)
  defp to_safe_expr(nil)                 , do: ""
  defp to_safe_expr(a) when is_atom(a)   , do: TemplateSanitizer.html_escape(Atom.to_string(a))
  defp to_safe_expr(i) when is_integer(i), do: Integer.to_string(i)
  defp to_safe_expr(f) when is_float(f)  , do: Float.to_string(f)

  # Otherwise we do the work at runtime
  defp to_safe_expr(expr) do
    quote do
      AntikytheraCore.TemplateEngine.to_safe_iodata(unquote(expr))
    end
  end

  def to_safe_iodata({:safe, data})                 , do: data
  def to_safe_iodata(s) when is_binary(s)           , do: TemplateSanitizer.html_escape(s)
  def to_safe_iodata(nil)                           , do: ""
  def to_safe_iodata(a) when is_atom(a)             , do: TemplateSanitizer.html_escape(Atom.to_string(a))
  def to_safe_iodata(i) when is_integer(i)          , do: Integer.to_string(i)
  def to_safe_iodata(f) when is_float(f)            , do: Float.to_string(f)
  def to_safe_iodata([])                            , do: ""
  def to_safe_iodata([h | _] = l) when is_integer(h), do: List.to_string(l) # convert charlist to String.t
  def to_safe_iodata([h | t])                       , do: [to_safe_iodata(h) | to_safe_iodata(t)]
end
