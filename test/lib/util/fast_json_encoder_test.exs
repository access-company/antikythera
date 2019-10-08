# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.FastJasonEncoderTest do
  use Croma.TestCase
  use ExUnitProperties

  defp assert_compatible_with_poison(value) do
    assert_compatible_with_poison(value, value)
  end

  defp assert_compatible_with_poison(source, expected) do
    {:ok, json} = FastJasonEncoder.encode(source)
    assert json == Poison.encode!(source)
    assert Poison.decode!(json) == expected
  end

  test "primitives" do
    values = [0, 1, 1.5, true, false, nil]
    Enum.each(values, &assert_compatible_with_poison/1)
    assert_compatible_with_poison(:ok, "ok") # Atom is encoded as a string
  end

  test "complext types" do
    values = [[], [1.5], [1, "foo"], %{}, %{"key" => "value"}]
    Enum.each(values, &assert_compatible_with_poison/1)

    # Atom is encoded as a string
    assert_compatible_with_poison(%{key: "value"}, %{"key" => "value"})
    assert_compatible_with_poison(%{key: :ok    }, %{"key" => "ok"   })

    # Skip `FastJasonEncoder.encode/1` vs `Poison.encode/1` because the order of the field may change.
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
    Enum.each(values, &assert_compatible_with_poison/1)
  end

  defmodule MyStruct do
    defstruct name: nil
  end
  test "module" do
    values = [%MyStruct{name: nil}, %MyStruct{name: "Taro"}]
    Enum.each(values, fn(value) ->
      {:ok, json} = FastJasonEncoder.encode(value)
      assert json == Poison.encode!(value)
      assert json == Poison.encode!(Map.from_struct(value))
    end)
  end
end
