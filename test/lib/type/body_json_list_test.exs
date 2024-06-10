# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonListTest do
  use Croma.TestCase

  defmodule TestList1 do
    use BodyJsonList, elem_module: Croma.PosInteger
  end

  describe "valid?/1 of a list based on BodyJsonList" do
    test "should return true when all the elements are valid" do
      [
        [],
        [1],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestList1.valid?(elem) end)
    end

    test "should return false when an element is invalid" do
      [
        [0],
        ["invalid"],
        [1, 0, 3]
      ]
      |> Enum.each(fn elem -> refute TestList1.valid?(elem) end)
    end

    test "should return false when the given value is not a list" do
      refute TestList1.valid?(1)
    end
  end

  describe "from_params/1 of a list based on BodyJsonList" do
    test "should return :ok with a list when all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestList1.from_params([1, 2, 3])
    end

    test "should return invalid value error when an element is invalid" do
      assert {:error, {:invalid_value, [TestList1, Croma.PosInteger]}} =
               TestList1.from_params([1, 0, 3])
    end

    test "should return invalid value error when the given value is not a list" do
      assert {:error, {:invalid_value, [TestList1]}} = TestList1.from_params(1)
    end
  end

  defmodule TestList2 do
    use BodyJsonList, elem_module: Croma.PosInteger, min_length: 2
  end

  describe "valid?/1 of a list based on BodyJsonList with minimum length" do
    test "should return true if the length is greater than or equal to the minimum length and all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestList2.valid?(elem) end)
    end

    test "should return false if the length is less than the minimum length even if all the elements are valid" do
      [
        [],
        [1]
      ]
      |> Enum.each(fn elem -> refute TestList2.valid?(elem) end)
    end

    test "should return false if the length is greater than or equal to the minimum length but an element is invalid" do
      [
        [0, 2],
        [1, 0, 3]
      ]
      |> Enum.each(fn elem -> refute TestList2.valid?(elem) end)
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with minimum length" do
    test "should return :ok with a list if the length is greater than or equal to the minimum length and all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestList2.from_params([1, 2, 3])
    end

    test "should return invalid value error if the length is less than the minimum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestList2]}} = TestList2.from_params([1])
    end

    test "should return invalid value error if the length is greater than or equal to the minimum length but an element is invalid" do
      assert {:error, {:invalid_value, [TestList2, Croma.PosInteger]}} =
               TestList2.from_params([1, 0, 3])
    end
  end

  defmodule TestList3 do
    use BodyJsonList, elem_module: Croma.PosInteger, max_length: 1
  end

  describe "valid?/1 of a list based on BodyJsonList with maximum length" do
    test "should return true if the length is less than or equal to the maximum length and all the elements are valid" do
      [
        [],
        [1]
      ]
      |> Enum.each(fn elem -> assert TestList3.valid?(elem) end)
    end

    test "should return false if the length is greater than the maximum length even if all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> refute TestList3.valid?(elem) end)
    end

    test "should return false if the length is less than or equal to the maximum length but an element is invalid" do
      refute TestList3.valid?([0])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with maximum length" do
    test "should return :ok with a list if the length is less than or equal to the maximum length and all the elements are valid" do
      assert {:ok, [1]} = TestList3.from_params([1])
    end

    test "should return invalid value error if the length is greater than the maximum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestList3]}} = TestList3.from_params([1, 2])
    end

    test "should return invalid value error if the length is less than or equal to the maximum length but an element is invalid" do
      assert {:error, {:invalid_value, [TestList3, Croma.PosInteger]}} =
               TestList3.from_params([0])
    end
  end

  defmodule TestList4 do
    use BodyJsonList, elem_module: Croma.PosInteger, min_length: 2, max_length: 3
  end

  describe "valid?/1 of a list based on BodyJsonList with both minimum and maximum lengths" do
    test "should return true if the length is within the specific range and all the elements are valid" do
      [
        [1, 2],
        [1, 2, 3]
      ]
      |> Enum.each(fn elem -> assert TestList4.valid?(elem) end)
    end

    test "should return false if the length is less than the minimum length even if all the elements are valid" do
      refute TestList4.valid?([1])
    end

    test "should return false if the length is greater than the maximum length even if all the elements are valid" do
      refute TestList4.valid?([1, 2, 3, 4])
    end

    test "should return false if the length is within the range but an element is invalid" do
      refute TestList4.valid?([1, 0, 3])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with both minimum and maximum lengths" do
    test "should return :ok with a list if the length is within the specific range and all the elements are valid" do
      assert {:ok, [1, 2, 3]} = TestList4.from_params([1, 2, 3])
    end

    test "should return invalid value error if the length is less than the minimum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestList4]}} = TestList4.from_params([1])
    end

    test "should return invalid value error if the length is greater than the maximum length even if all the elements are valid" do
      assert {:error, {:invalid_value, [TestList4]}} = TestList4.from_params([1, 2, 3, 4])
    end

    test "should return invalid value error if the length is within the range but an element is invalid" do
      assert {:error, {:invalid_value, [TestList4, Croma.PosInteger]}} =
               TestList4.from_params([1, 0, 3])
    end
  end

  defmodule TestList5 do
    use BodyJsonList, elem_module: {Date, &Date.from_iso8601/1}
  end

  describe "valid?/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return true when all the elements are valid" do
      [
        [],
        [~D[1970-01-01]],
        [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]
      ]
      |> Enum.each(fn elem -> assert TestList5.valid?(elem) end)
    end

    test "should return false when an element is invalid" do
      [
        ["1970-01-01"],
        [~D[1970-01-01], "1970-01-02", ~D[1970-01-03]]
      ]
      |> Enum.each(fn elem -> refute TestList5.valid?(elem) end)
    end
  end

  describe "new/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return :ok with a list when all the elements are valid" do
      assert {:ok, [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]} =
               TestList5.new([~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]])
    end

    test "should return invalid value error when an element is invalid" do
      assert {:error, {:invalid_value, [TestList5, Date]}} =
               TestList5.new([~D[1970-01-01], "1970-01-02", ~D[1970-01-03]])
    end
  end

  describe "from_params/1 of a list based on BodyJsonList with a custom preprocessor" do
    test "should return :ok with a list when all the elements are valid and the elements are preprocessed" do
      assert {:ok, [~D[1970-01-01], ~D[1970-01-02], ~D[1970-01-03]]} =
               TestList5.from_params(["1970-01-01", "1970-01-02", "1970-01-03"])
    end

    test "should return invalid value error when an element cannot be preprocessed" do
      assert {:error, {:invalid_value, [TestList5, Date]}} =
               TestList5.from_params(["1970-01-01", "invalid", "1970-01-03"])
    end
  end
end
