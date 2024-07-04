# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.StringPreprocessor do
  @moduledoc """
  String preprocessor functions for `Antikythera.ParamStringStruct`.

  This module defines string preprocessor functions which is not defined in Elixir standard library.
  """

  @doc """
  Converts a string to a boolean value. Raises ArgumentError if the argument is not a valid boolean value or is nil.
  """
  defun to_boolean(s :: String.t()) :: boolean do
    "true" -> true
    "false" -> false
    s when is_binary(s) -> raise ArgumentError, "Invalid boolean value: #{s}"
    nil -> raise ArgumentError, "String expected, but got nil"
  end

  @doc """
  Converts a string to a number. Raises ArgumentError if the argument is not a valid number or is nil.
  """
  defun to_number(s :: String.t()) :: number do
    s when is_binary(s) ->
      try do
        String.to_integer(s)
      rescue
        ArgumentError -> String.to_float(s)
      end

    nil ->
      raise ArgumentError, "String expected, but got nil"
  end

  @doc """
  Passthrough function for a string. Raises ArgumentError if the argument is nil.
  """
  defun passthrough_string(s :: String.t()) :: String.t() do
    s when is_binary(s) -> s
    nil -> raise ArgumentError, "String expected, but got nil"
  end

  @doc """
  Converts a string to a DateTime struct. Raises ArgumentError if the argument is not a valid datetime value or is nil.
  """
  defun to_datetime(s :: String.t()) :: DateTime.t() do
    s when is_binary(s) ->
      case DateTime.from_iso8601(s) do
        {:ok, dt, _tz_offset} -> dt
        _ -> raise ArgumentError, "Invalid datetime value: #{s}"
      end

    nil ->
      raise ArgumentError, "String expected, but got nil"
  end
end
