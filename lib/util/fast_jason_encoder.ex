# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.FastJasonEncoder do
  @moduledoc """
  This module converts structures to JSON at low load by avoiding protocol calls. Internally Jason is used.
  """
  alias Antikythera.Time

  defmodule Wrapper do
    defstruct item: nil
  end

  defimpl Jason.Encoder, for: Wrapper do
    def encode(%Wrapper{item: item}, opts) do
      Antikythera.FastJasonEncoder.encode(item, opts)
    end
  end

  def encode(value) do
    Jason.encode(%Wrapper{item: value})
  end

  def encode(value, opts) when is_list(value) do
    case value do
      []   -> "[]"
      list -> [?[ | encode_list(list, opts, false)]
    end
  end
  def encode(value, opts) when is_map(value) do
    case Map.to_list(value) do
      []   -> "{}"
      list -> [?{ | encode_map(list, opts, false)]
    end
  end
  def encode({Time, _ymd, _hms, _ms} = time, opts) do
    if Time.valid?(time) do
      [?", Time.to_iso_timestamp(time), ?"]
    else
      Jason.Encode.value(time, opts)
    end
  end
  def encode(value, opts) do
    Jason.Encode.value(value, opts)
  end

  def encode_map([], _opts, _comma) do
    '}'
  end
  def encode_map([{:__struct__, _v} | tail], opts, comma) do
    encode_map(tail, opts, comma)
  end
  def encode_map(list, opts, true) do
    [?,, encode_map(list, opts, false)]
  end
  def encode_map([{k, v} | tail], opts, _comma) do
    [encode(k, opts), ?:, encode(v, opts) | encode_map(tail, opts, true)]
  end

  def encode_list([], _opts, _comma) do
    ']'
  end
  def encode_list(list, opts, true) do
    [?,, encode_list(list, opts, false)]
  end
  def encode_list([head | tail], opts, _comma) do
    [encode(head, opts) | encode_list(tail, opts, true)]
  end
end
