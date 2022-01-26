# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Router.Reverse do
  @moduledoc """
  Internal helper functions for macros in `Antikythera.Router`, to generate/implement reverse routing functions.
  """

  @typep placeholder_filler :: String.t() | [String.t()]

  defun define_path_helper(path_name :: atom, path :: String.t()) :: Macro.t() do
    quote bind_quoted: [path_name: path_name, path: path] do
      {placeholder_vars, placeholder_types} =
        String.split(path, "/", trim: true)
        |> Enum.map(fn
          # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
          ":" <> name -> {Macro.var(String.to_atom(name), __MODULE__), quote(do: String.t())}
          "*" <> name -> {Macro.var(String.to_atom(name), __MODULE__), quote(do: [String.t()])}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.unzip()

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      fun_name = :"#{path_name}_path"

      @spec unquote(fun_name)(unquote_splicing(placeholder_types), %{String.t() => String.t()}) ::
              String.t()
      def unquote(fun_name)(unquote_splicing(placeholder_vars), query_params \\ %{}) do
        Antikythera.Router.Reverse.make_path(
          unquote(path),
          [unquote_splicing(placeholder_vars)],
          query_params
        )
      end
    end
  end

  defun make_path(
          path_pattern :: v[String.t()],
          fillers :: v[[placeholder_filler]],
          query_params :: v[%{String.t() => String.t()}]
        ) :: String.t() do
    replaced_path = fill_path(String.split(path_pattern, "/"), fillers, [])

    query =
      Enum.map_join(query_params, "&", fn
        {"", _} -> raise "empty query parameter name is not allowed"
        {k, s} when is_binary(s) -> URI.encode_www_form(k) <> "=" <> URI.encode_www_form(s)
        {k, i} when is_integer(i) -> URI.encode_www_form(k) <> "=" <> Integer.to_string(i)
      end)

    case query do
      "" -> replaced_path
      _ -> replaced_path <> "?" <> query
    end
  end

  defunp fill_path(patterns :: [String.t()], fillers :: [placeholder_filler], acc :: [String.t()]) ::
           String.t() do
    [], [], acc ->
      Enum.reverse(acc) |> Enum.join("/")

    [":" <> _ | patterns], [filler | fillers], acc ->
      fill_path(patterns, fillers, [encode_segment(filler) | acc])

    ["*" <> _ | patterns], [filler | fillers], acc ->
      fill_path(patterns, fillers, [encode_segment_list(filler) | acc])

    [fixed | patterns], fillers, acc ->
      fill_path(patterns, fillers, [fixed | acc])
  end

  defunp encode_segment(segment :: String.t()) :: String.t() do
    if segment == "", do: raise("empty segment is not allowed")
    URI.encode_www_form(segment)
  end

  defunp encode_segment_list(segments :: [String.t()]) :: String.t() do
    Enum.map_join(segments, "/", &encode_segment/1)
  end
end
