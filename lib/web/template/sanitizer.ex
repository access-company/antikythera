# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.TemplateSanitizer do
  @type safe :: {:safe, String.t()}

  @doc """
  Marks data as HTML safe to avoid double-escaping.
  """
  defun raw(data :: String.t() | safe) :: safe do
    {:safe, data} -> {:safe, data}
    nil -> {:safe, ""}
    data when is_binary(data) -> {:safe, data}
  end

  @doc """
  Converts special characters in the given string to character entity references.
  """
  defun html_escape(str :: v[String.t()]) :: String.t() do
    for <<char <- str>> do
      escape_char(char)
    end
    |> IO.iodata_to_binary()
  end

  [
    {?<, "&lt;"},
    {?>, "&gt;"},
    {?&, "&amp;"},
    {?", "&quot;"},
    {?', "&#39;"}
  ]
  |> Enum.each(fn {match, insert} ->
    defp escape_char(unquote(match)), do: unquote(insert)
  end)

  defp escape_char(char), do: char
end
