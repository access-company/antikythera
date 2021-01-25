# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

# In order to convert maps with frequently used tuple values directly into JSON on `Poison.encode/1,2`,
# implements tuple-to-string conversion for specific types (especially Antikythera.Time.t).

defimpl Poison.Encoder, for: Tuple do
  alias Antikythera.Time

  def encode({Time, _ymd, _hms, _ms} = time, options), do: encode_time(time, options)

  def encode(tuple, _options) do
    raise Poison.EncodeError,
      value: tuple,
      message: "cannot encode unsupported tuple, got: #{inspect(tuple)}"
  end

  defp encode_time(time, _options) do
    if Time.valid?(time) do
      ~s|"#{Time.to_iso_timestamp(time)}"|
    else
      raise Poison.EncodeError,
        value: time,
        message: "invalid Antikythera.Time.t, got: #{inspect(time)}"
    end
  end
end
