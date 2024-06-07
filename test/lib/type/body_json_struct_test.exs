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
end
