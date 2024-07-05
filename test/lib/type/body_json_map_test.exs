# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonMapTest do
  use Croma.TestCase

  defmodule TestMapOfValidatableValue do
    use BodyJsonMap, value_module: Croma.PosInteger
  end

  describe "valid?/1 of a map based on BodyJsonMap" do
    test "should return true when all the values are valid" do
      [
        %{},
        %{"a" => 1},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMapOfValidatableValue.valid?(map) end)
    end

    test "should return false when a value is invalid" do
      [
        %{"a" => 0},
        %{"a" => "invalid"},
        %{"a" => 1, "b" => 0, "c" => 3}
      ]
      |> Enum.each(fn map -> refute TestMapOfValidatableValue.valid?(map) end)
    end

    test "should return false when a key is not a string" do
      refute TestMapOfValidatableValue.valid?(%{a: 1})
    end

    test "should return false when the given value is not a map" do
      refute TestMapOfValidatableValue.valid?(1)
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap" do
    test "should return :ok with a map when all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMapOfValidatableValue.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error when a value is invalid" do
      assert {:error, {:invalid_value, [TestMapOfValidatableValue, Croma.PosInteger]}} =
               TestMapOfValidatableValue.from_params(%{"a" => 1, "b" => 0, "c" => 3})
    end

    test "should return invalid value error when a key is not a string" do
      assert {:error, {:invalid_value, [TestMapOfValidatableValue]}} =
               TestMapOfValidatableValue.from_params(%{a: 1})
    end

    test "should return invalid value error when the given value is not a map" do
      assert {:error, {:invalid_value, [TestMapOfValidatableValue]}} =
               TestMapOfValidatableValue.from_params(1)
    end
  end

  defmodule TestMapWithMinSize do
    use BodyJsonMap, value_module: Croma.PosInteger, min_size: 2
  end

  describe "valid/1 of a map based on BodyJsonMap with min_size option" do
    test "should return true if the size is greater than or equal to the minimum size and all the values are valid" do
      [
        %{"a" => 1, "b" => 2},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMapWithMinSize.valid?(map) end)
    end

    test "should return false if the size is less than the minimum size even if all the values are valid" do
      [
        %{},
        %{"a" => 1}
      ]
      |> Enum.each(fn map -> refute TestMapWithMinSize.valid?(map) end)
    end

    test "should return false if the size is greater than or equal to the minimum size but a value is invalid" do
      refute TestMapWithMinSize.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with min_size option" do
    test "should return :ok with a map if the size is greater than or equal to the minimum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMapWithMinSize.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error if the size is greater than or equal to the minimum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMapWithMinSize, Croma.PosInteger]}} =
               TestMapWithMinSize.from_params(%{"a" => 0, "b" => 2})
    end

    test "should return invalid value error if the size is less than the minimum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMapWithMinSize]}} =
               TestMapWithMinSize.from_params(%{"a" => 1})
    end
  end

  defmodule TestMapWithMaxSize do
    use BodyJsonMap, value_module: Croma.PosInteger, max_size: 2
  end

  describe "valid/1 of a map based on BodyJsonMap with max_size option" do
    test "should return true if the size is less than or equal to the maximum size and all the values are valid" do
      [
        %{},
        %{"a" => 1},
        %{"a" => 1, "b" => 2}
      ]
      |> Enum.each(fn map -> assert TestMapWithMaxSize.valid?(map) end)
    end

    test "should return false if the size is greater than the maximum size even if all the values are valid" do
      refute TestMapWithMaxSize.valid?(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return false if the size is less than or equal to the maximum size but a value is invalid" do
      refute TestMapWithMaxSize.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with max_size option" do
    test "should return :ok with a map if the size is less than or equal to the maximum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2}} = TestMapWithMaxSize.from_params(%{"a" => 1, "b" => 2})
    end

    test "should return invalid value error if the size is less than or equal to the maximum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMapWithMaxSize, Croma.PosInteger]}} =
               TestMapWithMaxSize.from_params(%{"a" => 0, "b" => 2})
    end

    test "should return invalid value error if the size is greater than the maximum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMapWithMaxSize]}} =
               TestMapWithMaxSize.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end
  end

  defmodule TestMapWithBothMinAndMaxSize do
    use BodyJsonMap, value_module: Croma.PosInteger, min_size: 2, max_size: 3
  end

  describe "valid/1 of a map based on BodyJsonMap with both min_size and max_size options" do
    test "should return true if the size is between the minimum size and the maximum size and all the values are valid" do
      [
        %{"a" => 1, "b" => 2},
        %{"a" => 1, "b" => 2, "c" => 3}
      ]
      |> Enum.each(fn map -> assert TestMapWithBothMinAndMaxSize.valid?(map) end)
    end

    test "should return false if the size is less than the minimum size even if all the values are valid" do
      refute TestMapWithBothMinAndMaxSize.valid?(%{"a" => 1})
    end

    test "should return false if the size is greater than the maximum size even if all the values are valid" do
      refute TestMapWithBothMinAndMaxSize.valid?(%{"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end

    test "should return false if the size is between the minimum size and the maximum size but a value is invalid" do
      refute TestMapWithBothMinAndMaxSize.valid?(%{"a" => 0, "b" => 2})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with both min_size and max_size options" do
    test "should return :ok with a map if the size is between the minimum size and the maximum size and all the values are valid" do
      assert {:ok, %{"a" => 1, "b" => 2, "c" => 3}} =
               TestMapWithBothMinAndMaxSize.from_params(%{"a" => 1, "b" => 2, "c" => 3})
    end

    test "should return invalid value error if the size is less than the minimum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMapWithBothMinAndMaxSize]}} =
               TestMapWithBothMinAndMaxSize.from_params(%{"a" => 1})
    end

    test "should return invalid value error if the size is greater than the maximum size even if all the values are valid" do
      assert {:error, {:invalid_value, [TestMapWithBothMinAndMaxSize]}} =
               TestMapWithBothMinAndMaxSize.from_params(%{"a" => 1, "b" => 2, "c" => 3, "d" => 4})
    end

    test "should return invalid value error if the size is between the minimum size and the maximum size but a value is invalid" do
      assert {:error, {:invalid_value, [TestMapWithBothMinAndMaxSize, Croma.PosInteger]}} =
               TestMapWithBothMinAndMaxSize.from_params(%{"a" => 0, "b" => 2})
    end
  end

  defmodule TestMapWithCustomPreprocessor do
    use BodyJsonMap, value_module: {Date, &Date.from_iso8601/1}
  end

  describe "valid?/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return true if all the values are valid" do
      [
        %{},
        %{"a" => ~D[1970-01-01]},
        %{"a" => ~D[1970-01-01], "b" => ~D[1970-01-02], "c" => ~D[1970-01-03]}
      ]
      |> Enum.each(fn map -> assert TestMapWithCustomPreprocessor.valid?(map) end)
    end

    test "should return false if a value is invalid" do
      [
        %{"a" => "1970-01-01"},
        %{"a" => ~D[1970-01-01], "b" => "1970-01-02", "c" => ~D[1970-01-03]}
      ]
      |> Enum.each(fn map -> refute TestMapWithCustomPreprocessor.valid?(map) end)
    end
  end

  describe "new/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return :ok with a map if all the values are valid" do
      assert {:ok, %{"a" => ~D[1970-01-01]}} =
               TestMapWithCustomPreprocessor.new(%{"a" => ~D[1970-01-01]})
    end

    test "should return invalid value error if a value is invalid" do
      assert {:error, {:invalid_value, [TestMapWithCustomPreprocessor, Date]}} =
               TestMapWithCustomPreprocessor.new(%{"a" => "1970-01-01"})
    end
  end

  describe "from_params/1 of a map based on BodyJsonMap with a custom preprocessor" do
    test "should return :ok with a map if all the values are valid and the values are preprocessed" do
      assert {:ok, %{"a" => ~D[1970-01-01]}} =
               TestMapWithCustomPreprocessor.from_params(%{"a" => "1970-01-01"})
    end

    test "should return invalid value error if a value is invalid" do
      assert {:error, {:invalid_value, [TestMapWithCustomPreprocessor, Date]}} =
               TestMapWithCustomPreprocessor.from_params(%{"a" => "invalid"})
    end
  end
end
