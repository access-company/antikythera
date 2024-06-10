# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonStructTest do
  use Croma.TestCase

  defmodule TestStruct1 do
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

      assert {:ok, %TestStruct1{param_object: %TestStruct1.NestedStruct{param_pos_int: 1}}} =
               TestStruct1.from_params(params)
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
                 TestStruct1,
                 {TestStruct1.NestedStruct, :param_object},
                 {Croma.PosInteger, :param_pos_int}
               ]}} = TestStruct1.from_params(params)
    end

    test "should return value missing error when a field of a nested struct is missing" do
      params = %{
        "param_object" => %{}
      }

      assert {:error,
              {:value_missing,
               [
                 TestStruct1,
                 {TestStruct1.NestedStruct, :param_object},
                 {Croma.PosInteger, :param_pos_int}
               ]}} = TestStruct1.from_params(params)
    end
  end

  defmodule TestStruct2 do
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
              %TestStruct2{param_list: [1, 2, 3], param_map: %{"a" => 1, "b" => 2, "c" => 3}}} =
               TestStruct2.from_params(params)
    end

    test "should return invalid value error when an element of a list is invalid" do
      params = %{
        "param_list" => [1, 0, 3],
        "param_map" => %{"a" => 1, "b" => 2, "c" => 3}
      }

      assert {:error,
              {:invalid_value,
               [
                 TestStruct2,
                 {TestStruct2.TestList, :param_list},
                 Croma.PosInteger
               ]}} = TestStruct2.from_params(params)
    end

    test "should return invalid value error when a value of a map is invalid" do
      params = %{
        "param_list" => [1, 2, 3],
        "param_map" => %{"a" => 1, "b" => 0, "c" => 3}
      }

      assert {:error,
              {:invalid_value,
               [
                 TestStruct2,
                 {TestStruct2.TestMap, :param_map},
                 Croma.PosInteger
               ]}} = TestStruct2.from_params(params)
    end
  end
end
