# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.FastJasonEncoderTest do
  use Croma.TestCase
  use ExUnitProperties

  def validate(value) do
    validate(value, value)
  end
  def validate(source, expected) do
    {:ok, json} = FastJasonEncoder.encode(source)
    assert json == Poison.encode!(source)
    assert expected == Poison.decode!(json)
  end

  test "primitives" do
    values = [0, 1, 1.5, true, false, nil]
    Enum.each(values, &validate(&1))
    validate(:ok, "ok") # Atom is encoded as a string
  end

  test "complext types" do
    values = [[], [1.5], [1, "foo"], %{}, %{"key" => "value"}]
    Enum.each(values, &validate(&1))

    # Atom is encoded as a string
    validate(%{key: "value"}, %{"key" => "value"})
    validate(%{key: :ok    }, %{"key" => "ok"   })

    # Skip FastJasonEncoder.encode vs Poison.encode because the order of the field may change
    obj = %{"k1" => "v1", "k2" => "v2"}
    {:ok, json} = FastJasonEncoder.encode(obj)
    assert obj == Poison.decode!(json)
  end

  test "Antikythera.Time" do
    time = {Antikythera.Time, {2017, 1, 1}, {0, 0, 0}, 0}
    values = [time, [time], %{time: time}]
    Enum.each(values, fn(value) ->
      {:ok, json} = FastJasonEncoder.encode(value)
      assert json == Poison.encode!(value)
    end)
  end

  test "string compatibility" do
    values = ["\\500", "\"", "foo\nbar", "</script>", "日本語"]
    Enum.each(values, &validate(&1))
  end
end
