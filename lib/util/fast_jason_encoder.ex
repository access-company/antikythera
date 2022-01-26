# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.FastJasonEncoder do
  @moduledoc """
  This module converts structures to JSON at low load by avoiding protocol calls. Internally Jason is used.
  """

  alias Croma.Result, as: R
  alias Antikythera.Time

  defmodule Wrapper do
    defstruct item: nil
  end

  defimpl Jason.Encoder, for: Wrapper do
    def encode(%Wrapper{item: item}, opts) do
      Antikythera.FastJasonEncoder.encode(item, opts)
    end
  end

  defun encode(value :: any) :: R.t(String.t(), Jason.EncodeError.t() | Exception.t()) do
    Jason.encode(%Wrapper{item: value})
  end

  R.define_bang_version_of(encode: 1)

  defun encode(value :: any, opts :: Jason.Encode.opts()) :: iodata do
    [], _ ->
      "[]"

    list, opts when is_list(list) ->
      [?[ | encode_list(list, opts, false)]

    empty_map, _ when empty_map == %{} ->
      "{}"

    %MapSet{map: map}, opts ->
      encode(Map.keys(map), opts)

    %DateTime{} = value, _ ->
      [?", DateTime.to_iso8601(value), ?"]

    map, opts when is_map(map) ->
      [?{ | encode_map(Map.to_list(map), opts, false)]

    value, opts ->
      if Time.valid?(value) do
        [?", Time.to_iso_timestamp(value), ?"]
      else
        Jason.Encode.value(value, opts)
      end
  end

  defunp encode_map(value :: [tuple], opts :: Jason.Encode.opts(), comma :: boolean) :: iodata do
    [], _, _ ->
      '}'

    [{:__struct__, _v} | tail], opts, comma ->
      encode_map(tail, opts, comma)

    list, opts, true ->
      [?,, encode_map(list, opts, false)]

    [{k, v} | tail], opts, false ->
      [encode(k, opts), ?:, encode(v, opts) | encode_map(tail, opts, true)]
  end

  defunp encode_list(value :: list, opts :: Jason.Encode.opts(), comma :: boolean) :: iodata do
    [], _, _ -> ']'
    list, opts, true -> [?,, encode_list(list, opts, false)]
    [head | tail], opts, false -> [encode(head, opts) | encode_list(tail, opts, true)]
  end
end
