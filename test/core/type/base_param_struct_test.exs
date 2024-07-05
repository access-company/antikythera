# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.BaseParamStructTest do
  alias AntikytheraCore.BaseParamStructTest.TestStructOfVariousFieldTypes
  use Croma.TestCase

  defmodule TestStructOfVariousFieldTypes do
    use BaseParamStruct,
      fields: [
        param_croma_builtin: Croma.PosInteger,
        param_datetime_related: Date,
        param_nilable: Croma.TypeGen.nilable(Croma.PosInteger),
        param_with_throwable_preprocessor: {Croma.PosInteger, &String.to_integer/1},
        param_with_result_preprocessor: {Croma.PosInteger, &__MODULE__.to_integer/1}
      ]

    defun to_integer(v :: v[String.t()]) :: Croma.Result.t(integer) do
      Croma.Result.try(fn -> String.to_integer(v) end)
    end
  end

  @valid_fields_for_test_struct_of_various_field_types_1 %{
    param_croma_builtin: 1,
    param_datetime_related: ~D[1970-01-01],
    param_nilable: 1,
    param_with_throwable_preprocessor: 1,
    param_with_result_preprocessor: 1
  }
  @valid_fields_for_test_struct_of_various_field_types_2 %{
    param_croma_builtin: 1,
    param_datetime_related: ~D[1970-01-01],
    param_nilable: nil,
    param_with_throwable_preprocessor: 1,
    param_with_result_preprocessor: 1
  }
  @valid_params_for_test_struct_of_various_field_types_1 %{
    "param_croma_builtin" => 1,
    "param_datetime_related" => ~D[1970-01-01],
    "param_nilable" => 1,
    "param_with_throwable_preprocessor" => "1",
    "param_with_result_preprocessor" => "1"
  }
  @valid_params_for_test_struct_of_various_field_types_2 %{
    "param_croma_builtin" => 1,
    "param_datetime_related" => ~D[1970-01-01],
    "param_with_throwable_preprocessor" => "1",
    "param_with_result_preprocessor" => "1"
  }

  describe "new/1 of a struct module based on BaseParamStruct" do
    test "should return :ok with a struct if all fields are valid" do
      [
        @valid_fields_for_test_struct_of_various_field_types_1,
        @valid_fields_for_test_struct_of_various_field_types_2
      ]
      |> Enum.each(fn valid_fields ->
        expected_struct = struct(TestStructOfVariousFieldTypes, valid_fields)
        assert {:ok, ^expected_struct} = TestStructOfVariousFieldTypes.new(valid_fields)
      end)
    end

    test "should return invalid value error if a field is invalid" do
      [
        param_croma_builtin: [0, "1", nil],
        param_datetime_related: [~U[1970-01-01T00:00:00Z], "1970-01-01", nil],
        param_nilable: [0, "1"],
        param_with_throwable_preprocessor: [0, "1", nil],
        param_with_result_preprocessor: [0, "1", nil]
      ]
      |> Enum.each(fn {field, invalid_values} ->
        Enum.each(invalid_values, fn invalid_value ->
          params =
            Map.put(
              @valid_fields_for_test_struct_of_various_field_types_1,
              field,
              invalid_value
            )

          assert {:error, {:invalid_value, [TestStructOfVariousFieldTypes, {_type, ^field}]}} =
                   TestStructOfVariousFieldTypes.new(params)
        end)
      end)
    end

    test "should return value missing error if a field is missing" do
      Map.keys(@valid_fields_for_test_struct_of_various_field_types_1)
      # Reject the param_nilable field because it allows empty value
      |> Enum.reject(&(&1 == :param_nilable))
      |> Enum.each(fn field ->
        params = Map.delete(@valid_fields_for_test_struct_of_various_field_types_1, field)

        assert {:error, {:value_missing, [TestStructOfVariousFieldTypes, {_type, ^field}]}} =
                 TestStructOfVariousFieldTypes.new(params)
      end)
    end

    test "should return :ok with a struct if a field is missing but it is nilable" do
      assert {:ok, %TestStructOfVariousFieldTypes{param_nilable: nil}} =
               TestStructOfVariousFieldTypes.new(%{
                 param_croma_builtin: 1,
                 param_datetime_related: ~D[1970-01-01],
                 param_with_throwable_preprocessor: 1,
                 param_with_result_preprocessor: 1
               })
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct" do
    test "should return :ok with a struct if all fields are valid" do
      [
        {
          struct(
            TestStructOfVariousFieldTypes,
            @valid_fields_for_test_struct_of_various_field_types_1
          ),
          @valid_params_for_test_struct_of_various_field_types_1
        },
        {
          struct(
            TestStructOfVariousFieldTypes,
            @valid_fields_for_test_struct_of_various_field_types_2
          ),
          @valid_params_for_test_struct_of_various_field_types_2
        }
      ]
      |> Enum.each(fn {expected_struct, valid_params} ->
        assert {:ok, ^expected_struct} = TestStructOfVariousFieldTypes.from_params(valid_params)
      end)
    end

    test "should return invalid value error if a field is invalid" do
      [
        param_croma_builtin: [0, "1"],
        param_datetime_related: [~U[1970-01-01T00:00:00Z], "1970-01-01"],
        param_nilable: [0, "1"],
        param_with_throwable_preprocessor: ["0", "string", 1],
        param_with_result_preprocessor: ["0", "string", 1]
      ]
      |> Enum.each(fn {field, invalid_values} ->
        Enum.each(invalid_values, fn invalid_value ->
          params =
            Map.put(
              @valid_params_for_test_struct_of_various_field_types_1,
              Atom.to_string(field),
              invalid_value
            )

          assert {:error, {:invalid_value, [TestStructOfVariousFieldTypes, {_type, ^field}]}} =
                   TestStructOfVariousFieldTypes.from_params(params)
        end)
      end)
    end

    test "should return value missing error if a field is missing" do
      Map.keys(@valid_params_for_test_struct_of_various_field_types_1)
      # Reject the param_nilable field because it allows empty value
      |> Enum.reject(&(&1 == "param_nilable"))
      |> Enum.each(fn field ->
        params = Map.delete(@valid_params_for_test_struct_of_various_field_types_1, field)
        field_atom = String.to_existing_atom(field)

        assert {:error, {:value_missing, [TestStructOfVariousFieldTypes, {_type, ^field_atom}]}} =
                 TestStructOfVariousFieldTypes.from_params(params)
      end)
    end
  end

  describe "update/2 of a struct module based on BaseParamStruct" do
    test "should return :ok and an updated struct if all given fields are valid" do
      [
        {
          %TestStructOfVariousFieldTypes{
            param_croma_builtin: 2,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            param_croma_builtin: 2
          }
        },
        {
          %TestStructOfVariousFieldTypes{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-02],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            param_datetime_related: ~D[1970-01-02]
          }
        },
        {
          %TestStructOfVariousFieldTypes{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: nil,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            param_nilable: nil
          }
        },
        {
          %TestStructOfVariousFieldTypes{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 2,
            param_with_result_preprocessor: 1
          },
          %{
            param_with_throwable_preprocessor: 2
          }
        },
        {
          %TestStructOfVariousFieldTypes{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 2
          },
          %{
            param_with_result_preprocessor: 2
          }
        }
      ]
      |> Enum.each(fn {expected_struct, valid_params} ->
        assert {:ok, ^expected_struct} =
                 TestStructOfVariousFieldTypes.update(
                   %TestStructOfVariousFieldTypes{
                     param_croma_builtin: 1,
                     param_datetime_related: ~D[1970-01-01],
                     param_nilable: 1,
                     param_with_throwable_preprocessor: 1,
                     param_with_result_preprocessor: 1
                   },
                   valid_params
                 )
      end)
    end

    test "should return invalid value error if a field is invalid" do
      [
        param_croma_builtin: [0, "1"],
        param_datetime_related: [~U[1970-01-01T00:00:00Z], "1970-01-01"],
        param_nilable: [0, "1"],
        param_with_throwable_preprocessor: [0, "1"],
        param_with_result_preprocessor: [0, "1"]
      ]
      |> Enum.each(fn {field, invalid_values} ->
        Enum.each(invalid_values, fn invalid_value ->
          assert {:error, {:invalid_value, [TestStructOfVariousFieldTypes, {_type, ^field}]}} =
                   TestStructOfVariousFieldTypes.update(
                     %TestStructOfVariousFieldTypes{
                       param_croma_builtin: 1,
                       param_datetime_related: ~D[1970-01-01],
                       param_nilable: 1,
                       param_with_throwable_preprocessor: 1,
                       param_with_result_preprocessor: 1
                     },
                     %{field => invalid_value}
                   )
        end)
      end)
    end
  end

  describe "valid?/1 of a struct module based on BaseParamStruct" do
    test "should return true if all fields are valid" do
      [
        struct(
          TestStructOfVariousFieldTypes,
          @valid_fields_for_test_struct_of_various_field_types_1
        ),
        struct(
          TestStructOfVariousFieldTypes,
          @valid_fields_for_test_struct_of_various_field_types_2
        )
      ]
      |> Enum.each(fn valid_struct ->
        assert TestStructOfVariousFieldTypes.valid?(valid_struct)
      end)
    end

    test "should return false if a field is invalid" do
      [
        param_croma_builtin: [0, "1", nil],
        param_datetime_related: [~U[1970-01-01T00:00:00Z], "1970-01-01", nil],
        param_nilable: [0, "1"],
        param_with_throwable_preprocessor: [0, "1", nil],
        param_with_result_preprocessor: [0, "1", nil]
      ]
      |> Enum.each(fn {field, invalid_values} ->
        Enum.each(invalid_values, fn invalid_value ->
          invalid_struct =
            struct(
              TestStructOfVariousFieldTypes,
              @valid_fields_for_test_struct_of_various_field_types_1
            )
            |> Map.put(field, invalid_value)

          refute TestStructOfVariousFieldTypes.valid?(invalid_struct)
        end)
      end)
    end
  end

  defmodule TestStructWithAcceptCaseSnake do
    use BaseParamStruct,
      accept_case: :snake,
      fields: [paramNamedWithMultipleWords: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :snake" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its snake case" do
      assert {:ok, %TestStructWithAcceptCaseSnake{paramNamedWithMultipleWords: 1}} =
               TestStructWithAcceptCaseSnake.new(%{paramNamedWithMultipleWords: 1})

      assert {:ok, %TestStructWithAcceptCaseSnake{paramNamedWithMultipleWords: 1}} =
               TestStructWithAcceptCaseSnake.new(%{param_named_with_multiple_words: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStructWithAcceptCaseSnake, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStructWithAcceptCaseSnake.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [TestStructWithAcceptCaseSnake, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStructWithAcceptCaseSnake.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :snake" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its snake case" do
      assert {:ok, %TestStructWithAcceptCaseSnake{paramNamedWithMultipleWords: 1}} =
               TestStructWithAcceptCaseSnake.from_params(%{"paramNamedWithMultipleWords" => 1})

      assert {:ok, %TestStructWithAcceptCaseSnake{paramNamedWithMultipleWords: 1}} =
               TestStructWithAcceptCaseSnake.from_params(%{"param_named_with_multiple_words" => 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStructWithAcceptCaseSnake, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStructWithAcceptCaseSnake.from_params(%{"ParamNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing,
               [TestStructWithAcceptCaseSnake, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStructWithAcceptCaseSnake.from_params(%{"PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1})
    end
  end

  defmodule TestStructWithAcceptCaseUpperCamel do
    use BaseParamStruct,
      accept_case: :upper_camel,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :upper_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its upper camel case" do
      assert {:ok, %TestStructWithAcceptCaseUpperCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseUpperCamel.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStructWithAcceptCaseUpperCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseUpperCamel.new(%{ParamNamedWithMultipleWords: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseUpperCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseUpperCamel.new(%{paramNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseUpperCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseUpperCamel.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :upper_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its upper camel case" do
      assert {:ok, %TestStructWithAcceptCaseUpperCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseUpperCamel.from_params(%{
                 "param_named_with_multiple_words" => 1
               })

      assert {:ok, %TestStructWithAcceptCaseUpperCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseUpperCamel.from_params(%{
                 "ParamNamedWithMultipleWords" => 1
               })
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseUpperCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseUpperCamel.from_params(%{
                 "paramNamedWithMultipleWords" => 1
               })

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseUpperCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseUpperCamel.from_params(%{
                 "PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1
               })
    end
  end

  defmodule TestStructWithAcceptCaseLowerCamel do
    use BaseParamStruct,
      accept_case: :lower_camel,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :lower_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its lower camel case" do
      assert {:ok, %TestStructWithAcceptCaseLowerCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseLowerCamel.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStructWithAcceptCaseLowerCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseLowerCamel.new(%{paramNamedWithMultipleWords: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseLowerCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseLowerCamel.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseLowerCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseLowerCamel.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :lower_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its lower camel case" do
      assert {:ok, %TestStructWithAcceptCaseLowerCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseLowerCamel.from_params(%{
                 "param_named_with_multiple_words" => 1
               })

      assert {:ok, %TestStructWithAcceptCaseLowerCamel{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseLowerCamel.from_params(%{
                 "paramNamedWithMultipleWords" => 1
               })
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseLowerCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseLowerCamel.from_params(%{
                 "ParamNamedWithMultipleWords" => 1
               })

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseLowerCamel,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseLowerCamel.from_params(%{
                 "PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1
               })
    end
  end

  defmodule TestStructWithAcceptCaseCapital do
    use BaseParamStruct,
      accept_case: :capital,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :capital" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its capital case" do
      assert {:ok, %TestStructWithAcceptCaseCapital{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseCapital.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStructWithAcceptCaseCapital{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseCapital.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseCapital,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseCapital.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseCapital,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} = TestStructWithAcceptCaseCapital.new(%{paramNamedWithMultipleWords: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :capital" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its capital case" do
      assert {:ok, %TestStructWithAcceptCaseCapital{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseCapital.from_params(%{
                 "param_named_with_multiple_words" => 1
               })

      assert {:ok, %TestStructWithAcceptCaseCapital{param_named_with_multiple_words: 1}} =
               TestStructWithAcceptCaseCapital.from_params(%{
                 "PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1
               })
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseCapital,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseCapital.from_params(%{"ParamNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing,
               [
                 TestStructWithAcceptCaseCapital,
                 {Croma.PosInteger, :param_named_with_multiple_words}
               ]}} =
               TestStructWithAcceptCaseCapital.from_params(%{paramNamedWithMultipleWords: 1})
    end
  end

  defmodule TestStructWithDefaultValue do
    defmodule IntegerWithDefaultValue do
      use Croma.SubtypeOfInt, min: 1, default: 1_000
    end

    use BaseParamStruct,
      fields: [
        param_default_by_mod: IntegerWithDefaultValue,
        param_default_by_val: {Croma.Integer, [default: 2_000]},
        param_pp_default_by_val: {Date, &Date.from_iso8601/1, [default: ~D[2001-01-01]]}
      ]
  end

  describe "new/1 of a struct module based on BaseParamStruct with default values" do
    test "should return :ok with a struct if all fields are valid" do
      assert {:ok,
              %TestStructWithDefaultValue{
                param_default_by_mod: 1,
                param_default_by_val: 2,
                param_pp_default_by_val: ~D[1970-01-01]
              }} =
               TestStructWithDefaultValue.new(%{
                 param_default_by_mod: 1,
                 param_default_by_val: 2,
                 param_pp_default_by_val: ~D[1970-01-01]
               })
    end

    test "should return :ok with a struct if a field which has a default value is missing" do
      assert {:ok,
              %TestStructWithDefaultValue{
                param_default_by_mod: 1_000,
                param_default_by_val: 2_000,
                param_pp_default_by_val: ~D[2001-01-01]
              }} = TestStructWithDefaultValue.new(%{})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with default values" do
    test "should return :ok with a struct if all fields are valid" do
      assert {:ok,
              %TestStructWithDefaultValue{
                param_default_by_mod: 1,
                param_default_by_val: 2,
                param_pp_default_by_val: ~D[1970-01-01]
              }} =
               TestStructWithDefaultValue.from_params(%{
                 "param_default_by_mod" => 1,
                 "param_default_by_val" => 2,
                 "param_pp_default_by_val" => "1970-01-01"
               })
    end

    test "should return :ok with a struct if a field which has a default value is missing" do
      assert {:ok,
              %TestStructWithDefaultValue{
                param_default_by_mod: 1_000,
                param_default_by_val: 2_000,
                param_pp_default_by_val: ~D[2001-01-01]
              }} = TestStructWithDefaultValue.from_params(%{})
    end
  end
end
