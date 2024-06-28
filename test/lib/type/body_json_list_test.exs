# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonListTest do
  use Croma.TestCase

  defmodule TestListOfValidatableElem do
    use BodyJsonList, elem_module: Croma.PosInteger
  end

  describe "valid?/1 of a list based on BodyJsonList" do
    test "should return true when all the elements are valid" do
      [
        [],
        [1],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestListOfValidatableElem.valid?(elem) end)
    end

    test "should return false when an element is invalid" do
      [
        [0],
        ["invalid"],
        [1, 0, 3]
      ]
      |> Enum.each(fn elem -> refute TestListOfValidatableElem.valid?(elem) end)
    end

    test "should return false when the given value is not a list" do
      refute TestListOfValidatableElem.valid?(1)
    end
  end

  describe "from_params/1 of a list based on BodyJsonList" do
    test "should return :ok with a list when all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestListOfValidatableElem.from_params([1, 2, 3])
    end

    test "should return invalid value error when an element is invalid" do
      assert {:error, {:invalid_value, [TestListOfValidatableElem, Croma.PosInteger]}} =
               TestListOfValidatableElem.from_params([1, 0, 3])
    end

    test "should return invalid value error when the given value is not a list" do
      assert {:error, {:invalid_value, [TestListOfValidatableElem]}} =
               TestListOfValidatableElem.from_params(1)
    end
  end

  defmodule TestListWithMinLength do
    use BodyJsonList, elem_module: Croma.PosInteger, min_length: 2
  end

  describe "valid?/1 of a list based on BodyJsonList with minimum length" do
    test "should return true if the length is greater than or equal to the minimum length and all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestListWithMinLength.valid?(elem) end)
    end

    test "should return false if the length is less than the minimum length even if all the elements are valid" do
      [
        [],
        [1]
      ]
      |> Enum.each(fn elem -> refute TestListWithMinLength.valid?(elem) end)
    end

    test "should return false if the length is greater than or equal to the minimum length but an element is invalid" do
      [
        [0, 2],
        [1, 0, 3]
      ]
      |> Enum.each(fn elem -> refute TestListWithMinLength.valid?(elem) end)
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with minimum length" do
    test "should return :ok with a list if the length is greater than or equal to the minimum length and all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestListWithMinLength.from_params([1, 2, 3])
    end

    test "should return invalid value error if the length is less than the minimum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestListWithMinLength]}} =
               TestListWithMinLength.from_params([1])
    end

    test "should return invalid value error if the length is greater than or equal to the minimum length but an element is invalid" do
      assert {:error, {:invalid_value, [TestListWithMinLength, Croma.PosInteger]}} =
               TestListWithMinLength.from_params([1, 0, 3])
    end
  end

  defmodule TestListWithMaxLength do
    use BodyJsonList, elem_module: Croma.PosInteger, max_length: 1
  end

  describe "valid?/1 of a list based on BodyJsonList with maximum length" do
    test "should return true if the length is less than or equal to the maximum length and all the elements are valid" do
      [
        [],
        [1]
      ]
      |> Enum.each(fn elem -> assert TestListWithMaxLength.valid?(elem) end)
    end

    test "should return false if the length is greater than the maximum length even if all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> refute TestListWithMaxLength.valid?(elem) end)
    end

    test "should return false if the length is less than or equal to the maximum length but an element is invalid" do
      refute TestListWithMaxLength.valid?([0])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with maximum length" do
    test "should return :ok with a list if the length is less than or equal to the maximum length and all the elements are valid" do
      assert {:ok, [1]} = TestListWithMaxLength.from_params([1])
    end

    test "should return invalid value error if the length is greater than the maximum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestListWithMaxLength]}} =
               TestListWithMaxLength.from_params([1, 2])
    end

    test "should return invalid value error if the length is less than or equal to the maximum length but an element is invalid" do
      assert {:error, {:invalid_value, [TestListWithMaxLength, Croma.PosInteger]}} =
               TestListWithMaxLength.from_params([0])
    end
  end

  defmodule TestListWithBothMinAndMaxLength do
    use BodyJsonList, elem_module: Croma.PosInteger, min_length: 2, max_length: 3
  end

  describe "valid?/1 of a list based on BodyJsonList with both minimum and maximum lengths" do
    test "should return true if the length is within the specific range and all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestListWithBothMinAndMaxLength.valid?(elem) end)
    end

    test "should return false if the length is less than the minimum length even if all the elements are valid" do
      refute TestListWithBothMinAndMaxLength.valid?([1])
    end

    test "should return false if the length is greater than the maximum length even if all the elements are valid" do
      refute TestListWithBothMinAndMaxLength.valid?([1, 2, 3, 4])
    end

    test "should return false if the length is within the range but an element is invalid" do
      refute TestListWithBothMinAndMaxLength.valid?([1, 0, 3])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with both minimum and maximum lengths" do
    test "should return :ok with a list if the length is within the specific range and all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestListWithBothMinAndMaxLength.from_params([1, 2, 3])
    end

    test "should return invalid value error if the length is less than the minimum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestListWithBothMinAndMaxLength]}} =
               TestListWithBothMinAndMaxLength.from_params([1])
    end

    test "should return invalid value error if the length is greater than the maximum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestListWithBothMinAndMaxLength]}} =
               TestListWithBothMinAndMaxLength.from_params([1, 2, 3, 4])
    end

    test "should return invalid value error if the length is within the range but an element is invalid" do
      assert {:error, {:invalid_value, [TestListWithBothMinAndMaxLength, Croma.PosInteger]}} =
               TestListWithBothMinAndMaxLength.from_params([1, 0, 3])
    end
  end

  defmodule TestListWithCustomPreprocessor do
    use BodyJsonList, elem_module: {Date, &Date.from_iso8601/1}
  end

  describe "valid?/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return true when all the elements are valid" do
      [
        [],
        [~D[1970-01-01]],
        [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]
      ]
      |> Enum.each(fn elem -> assert TestListWithCustomPreprocessor.valid?(elem) end)
    end

    test "should return false when an element is invalid" do
      [
        ["1970-01-01"],
        [~D[1970-01-01], "1970-01-02", ~D[1970-01-03]]
      ]
      |> Enum.each(fn elem -> refute TestListWithCustomPreprocessor.valid?(elem) end)
    end
  end

  describe "new/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return :ok with a list when all the elements are valid" do
      assert {:ok, [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]} =
               TestListWithCustomPreprocessor.new([~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]])
    end

    test "should return invalid value error when an element is invalid" do
      assert {:error, {:invalid_value, [TestListWithCustomPreprocessor, Date]}} =
               TestListWithCustomPreprocessor.new([~D[1970-01-01], "1970-01-02", ~D[1970-01-03]])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return :ok with a list when all the elements are valid and the elements are preprocessed" do
      assert {:ok, [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]} =
               TestListWithCustomPreprocessor.from_params([
                 "1970-01-01",
                 "1970-01-02",
                 "1970-01-03"
               ])
    end

    test "should return invalid value error when an element cannot be preprocessed" do
      assert {:error, {:invalid_value, [TestListWithCustomPreprocessor, Date]}} =
               TestListWithCustomPreprocessor.from_params(["1970-01-01", "invalid", "1970-01-03"])
    end
  end
end
