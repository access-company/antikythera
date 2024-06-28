# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonStructTest do
  use Croma.TestCase

  defmodule TestStructOfNestedStructField do
    defmodule NestedStruct do
      use BodyJsonStruct,
        fields: [
          param_pos_int: Croma.PosInteger
        ]
    end

    use BodyJsonStruct,
      fields: [
        param_object: NestedStruct
      ]
  end

  describe "from_params/1 of a struct based on BodyJsonStruct with nested structs" do
    test "should return :ok with a struct nested in a struct if all the fields are valid" do
      params = %{
        "param_object" => %{
          "param_pos_int" => 1
        }
      }

      assert {:ok,
              %TestStructOfNestedStructField{
                param_object: %TestStructOfNestedStructField.NestedStruct{param_pos_int: 1}
              }} = TestStructOfNestedStructField.from_params(params)
    end

    test "should return invalid value error when a field of a nested struct is invalid" do
      params = %{
        "param_object" => %{
          "param_pos_int" => 0
        }
      }

      assert {:error,
              {:invalid_value,
               [
                 TestStructOfNestedStructField,
                 {TestStructOfNestedStructField.NestedStruct, :param_object},
                 {Croma.PosInteger, :param_pos_int}
               ]}} = TestStructOfNestedStructField.from_params(params)
    end

    test "should return value missing error when a field of a nested struct is missing" do
      params = %{
        "param_object" => %{}
      }

      assert {:error,
              {:value_missing,
               [
                 TestStructOfNestedStructField,
                 {TestStructOfNestedStructField.NestedStruct, :param_object},
                 {Croma.PosInteger, :param_pos_int}
               ]}} = TestStructOfNestedStructField.from_params(params)
    end
  end

  defmodule TestStructOfListAndMap do
    defmodule TestList do
      use Antikythera.BodyJsonList, elem_module: Croma.PosInteger
    end

    defmodule TestMap do
      use Antikythera.BodyJsonMap, value_module: Croma.PosInteger
    end

    use Antikythera.BodyJsonStruct,
      fields: [
        param_list: TestList,
        param_map: TestMap
      ]
  end

  describe "from_params/1 of a struct based on BodyJsonStruct with lists and maps" do
    test "should return :ok with a struct if all the fields are valid" do
      params = %{
        "param_list" => [1, 2, 3],
        "param_map" => %{"a" => 1, "b" => 2, "c" => 3}
      }

      assert {:ok,
              %TestStructOfListAndMap{
                param_list: [1, 2, 3],
                param_map: %{"a" => 1, "b" => 2, "c" => 3}
              }} = TestStructOfListAndMap.from_params(params)
    end

    test "should return invalid value error when an element of a list is invalid" do
      params = %{
        "param_list" => [1, 0, 3],
        "param_map" => %{"a" => 1, "b" => 2, "c" => 3}
      }

      assert {:error,
              {:invalid_value,
               [
                 TestStructOfListAndMap,
                 {TestStructOfListAndMap.TestList, :param_list},
                 Croma.PosInteger
               ]}} = TestStructOfListAndMap.from_params(params)
    end

    test "should return invalid value error when a value of a map is invalid" do
      params = %{
        "param_list" => [1, 2, 3],
        "param_map" => %{"a" => 1, "b" => 0, "c" => 3}
      }

      assert {:error,
              {:invalid_value,
               [
                 TestStructOfListAndMap,
                 {TestStructOfListAndMap.TestMap, :param_map},
                 Croma.PosInteger
               ]}} = TestStructOfListAndMap.from_params(params)
    end
  end
end
