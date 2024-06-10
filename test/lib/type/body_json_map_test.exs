# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonMapTest do
  use Croma.TestCase

  defmodule TestMap1 do
    use BodyJsonMap, value_module: Croma.PosInteger
  end

  describe "valid?/1 of a map based on BodyJsonMap" do
    test "should return true when all the values are valid" do
      [
        %{},
        %{"a" => 1},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMap1.valid?(map) end)
    end

    test "should return false when a value is invalid" do
      [
        %{"a" => 0},
        %{"a" => "invalid"},
        %{"a" => 1, "b" => 0, "c" => 3}
      ]
      |> Enum.each(fn map -> refute TestMap1.valid?(map) end)
    end

    test "should return false when a key is not a string" do
      refute TestMap1.valid?(%{a: 1})
    end

    test "should return false when the given value is not a map" do
      refute TestMap1.valid?(1)
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap" do
    test "should return :ok with a map when all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMap1.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error when a value is invalid" do
      assert {:error, {:invalid_value, [TestMap1, Croma.PosInteger]}} =
               TestMap1.from_params(%{"a" => 1, "b" => 0, "c" => 3})
    end

    test "should return invalid value error when a key is not a string" do
      assert {:error, {:invalid_value, [TestMap1]}} = TestMap1.from_params(%{a: 1})
    end

    test "should return invalid value error when the given value is not a map" do
      assert {:error, {:invalid_value, [TestMap1]}} = TestMap1.from_params(1)
    end
  end

  defmodule TestMap2 do
    use BodyJsonMap, value_module: Croma.PosInteger, min_size: 2
  end

  describe "valid/1 of a map based on BodyJsonMap with min_size option" do
    test "should return true if the size is greater than or equal to the minimum size and all the values are valid" do
      [
        %{"a" => 1, "b" => 2},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMap2.valid?(map) end)
    end

    test "should return false if the size is less than the minimum size even if all the values are valid" do
      [
        %{},
        %{"a" => 1}
      ]
      |> Enum.each(fn map -> refute TestMap2.valid?(map) end)
    end

    test "should return false if the size is greater than or equal to the minimum size but a value is invalid" do
      refute TestMap2.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with min_size option" do
    test "should return :ok with a map if the size is greater than or equal to the minimum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMap2.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error if the size is greater than or equal to the minimum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMap2, Croma.PosInteger]}} =
               TestMap2.from_params(%{"a" => 0, "b" => 2})
    end

    test "should return invalid value error if the size is less than the minimum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMap2]}} = TestMap2.from_params(%{"a" => 1})
    end
  end

  defmodule TestMap3 do
    use BodyJsonMap, value_module: Croma.PosInteger, max_size: 2
  end

  describe "valid/1 of a map based on BodyJsonMap with max_size option" do
    test "should return true if the size is less than or equal to the maximum size and all the values are valid" do
      [
        %{},
        %{"a" => 1},
        %{"a" => 1, "b" => 2}
      ]
      |> Enum.each(fn map -> assert TestMap3.valid?(map) end)
    end

    test "should return false if the size is greater than the maximum size even if all the values are valid" do
      refute TestMap3.valid?(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return false if the size is less than or equal to the maximum size but a value is invalid" do
      refute TestMap3.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with max_size option" do
    test "should return :ok with a map if the size is less than or equal to the maximum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2}} = TestMap3.from_params(%{"a" => 1, "b" => 2})
    end

    test "should return invalid value error if the size is less than or equal to the maximum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMap3, Croma.PosInteger]}} =
               TestMap3.from_params(%{"a" => 0, "b" => 2})
    end

    test "should return invalid value error if the size is greater than the maximum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMap3]}} =
               TestMap3.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end
  end

  defmodule TestMap4 do
    use BodyJsonMap, value_module: Croma.PosInteger, min_size: 2, max_size: 3
  end

  describe "valid/1 of a map based on BodyJsonMap with both min_size and max_size options" do
    test "should return true if the size is between the minimum size and the maximum size and all the values are valid" do
      [
        %{"a" => 1, "b" => 2},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMap4.valid?(map) end)
    end

    test "should return false if the size is less than the minimum size even if all the values are valid" do
      refute TestMap4.valid?(%{"a" => 1})
    end

    test "should return false if the size is greater than the maximum size even if all the values are valid" do
      refute TestMap4.valid?(%{"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end

    test "should return false if the size is between the minimum size and the maximum size but a value is invalid" do
      refute TestMap4.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with both min_size and max_size options" do
    test "should return :ok with a map if the size is between the minimum size and the maximum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMap4.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error if the size is less than the minimum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMap4]}} = TestMap4.from_params(%{"a" => 1})
    end

    test "should return invalid value error if the size is greater than the maximum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMap4]}} =
               TestMap4.from_params(%{"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end

    test "should return invalid value error if the size is between the minimum size and the maximum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMap4, Croma.PosInteger]}} =
               TestMap4.from_params(%{"a" => 0, "b" => 2})
    end
  end

  defmodule TestMap5 do
    use BodyJsonMap, value_module: {Date, &Date.from_iso8601/1}
  end

  describe "valid?/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return true if all the values are valid" do
      [
        %{},
        %{"a" => ~D[1970-01-01]},
        %{"a" => ~D[1970-01-01], "b" => ~D[1970-01-02], "c" => ~D[1970-01-03]}
      ]
      |> Enum.each(fn map -> assert TestMap5.valid?(map) end)
    end

    test "should return false if a value is invalid" do
      [
        %{"a" => "1970-01-01"},
        %{"a" => ~D[1970-01-01], "b" => "1970-01-02", "c" => ~D[1970-01-03]}
      ]
      |> Enum.each(fn map -> refute TestMap5.valid?(map) end)
    end
  end

  describe "new/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return :ok with a map if all the values are valid" do
      assert {:ok, %{"a" => ~D[1970-01-01]}} = TestMap5.new(%{"a" => ~D[1970-01-01]})
    end

    test "should return invalid value error if a value is invalid" do
      assert {:error, {:invalid_value, [TestMap5, Date]}} = TestMap5.new(%{"a" => "1970-01-01"})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return :ok with a map if all the values are valid and the values are preprocessed" do
      assert {:ok, %{"a" => ~D[1970-01-01]}} = TestMap5.from_params(%{"a" => "1970-01-01"})
    end

    test "should return invalid value error if a value is invalid" do
      assert {:error, {:invalid_value, [TestMap5, Date]}} =
               TestMap5.from_params(%{"a" => "invalid"})
    end
  end
end
