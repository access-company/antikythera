# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.BaseParamStructTest do
  use Croma.TestCase

  defmodule TestStruct1 do
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

  describe "new/1 of a struct module based on BaseParamStruct" do
    test "should return :ok with a struct if all fields are valid" do
      [
        {
          %TestStruct1{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          }
        },
        {
          %TestStruct1{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: nil,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: nil,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          }
        }
      ]
      |> Enum.each(fn {expected_struct, valid_params} ->
        assert {:ok, ^expected_struct} = TestStruct1.new(valid_params)
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
              %{
                param_croma_builtin: 1,
                param_datetime_related: ~D[1970-01-01],
                param_nilable: 1,
                param_with_throwable_preprocessor: 1,
                param_with_result_preprocessor: 1
              },
              field,
              invalid_value
            )

          assert {:error, {:invalid_value, [TestStruct1, {_type, ^field}]}} =
                   TestStruct1.new(params)
        end)
      end)
    end

    test "should return value missing error if a field is missing" do
      valid_params = %{
        param_croma_builtin: 1,
        param_datetime_related: ~D[1970-01-01],
        param_nilable: 1,
        param_with_throwable_preprocessor: 1,
        param_with_result_preprocessor: 1
      }

      Map.keys(valid_params)
      |> Enum.reject(&(&1 == :param_nilable))
      |> Enum.each(fn field ->
        params = Map.delete(valid_params, field)

        assert {:error, {:value_missing, [TestStruct1, {_type, ^field}]}} =
                 TestStruct1.new(params)
      end)
    end

    test "should return :ok with a struct if a field is missing but it is nilable" do
      assert {:ok, %TestStruct1{param_nilable: nil}} =
               TestStruct1.new(%{
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
          %TestStruct1{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: 1,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            "param_croma_builtin" => 1,
            "param_datetime_related" => ~D[1970-01-01],
            "param_nilable" => 1,
            "param_with_throwable_preprocessor" => "1",
            "param_with_result_preprocessor" => "1"
          }
        },
        {
          %TestStruct1{
            param_croma_builtin: 1,
            param_datetime_related: ~D[1970-01-01],
            param_nilable: nil,
            param_with_throwable_preprocessor: 1,
            param_with_result_preprocessor: 1
          },
          %{
            "param_croma_builtin" => 1,
            "param_datetime_related" => ~D[1970-01-01],
            "param_with_throwable_preprocessor" => "1",
            "param_with_result_preprocessor" => "1"
          }
        }
      ]
      |> Enum.each(fn {expected_struct, valid_params} ->
        assert {:ok, ^expected_struct} = TestStruct1.from_params(valid_params)
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
              %{
                "param_croma_builtin" => 1,
                "param_datetime_related" => ~D[1970-01-01],
                "param_nilable" => 1,
                "param_with_throwable_preprocessor" => "1",
                "param_with_result_preprocessor" => "1"
              },
              Atom.to_string(field),
              invalid_value
            )

          assert {:error, {:invalid_value, [TestStruct1, {_type, ^field}]}} =
                   TestStruct1.from_params(params)
        end)
      end)
    end

    test "should return value missing error if a field is missing" do
      valid_params = %{
        "param_croma_builtin" => 1,
        "param_datetime_related" => ~D[1970-01-01],
        "param_nilable" => 1,
        "param_with_throwable_preprocessor" => "1",
        "param_with_result_preprocessor" => "1"
      }

      Map.keys(valid_params)
      # Reject the param_nilable field because it allows empty value
      |> Enum.reject(&(&1 == "param_nilable"))
      |> Enum.each(fn field ->
        params = Map.delete(valid_params, field)
        field_atom = String.to_existing_atom(field)

        assert {:error, {:value_missing, [TestStruct1, {_type, ^field_atom}]}} =
                 TestStruct1.from_params(params)
      end)
    end
  end

  describe "update/2 of a struct module based on BaseParamStruct" do
    test "should return :ok and an updated struct if all given fields are valid" do
      [
        {
          %TestStruct1{
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
          %TestStruct1{
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
          %TestStruct1{
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
          %TestStruct1{
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
          %TestStruct1{
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
                 TestStruct1.update(
                   %TestStruct1{
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
          assert {:error, {:invalid_value, [TestStruct1, {_type, ^field}]}} =
                   TestStruct1.update(
                     %TestStruct1{
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
        %TestStruct1{
          param_croma_builtin: 1,
          param_datetime_related: ~D[1970-01-01],
          param_nilable: 1,
          param_with_throwable_preprocessor: 1,
          param_with_result_preprocessor: 1
        },
        %TestStruct1{
          param_croma_builtin: 1,
          param_datetime_related: ~D[1970-01-01],
          param_nilable: nil,
          param_with_throwable_preprocessor: 1,
          param_with_result_preprocessor: 1
        }
      ]
      |> Enum.each(fn valid_struct ->
        assert TestStruct1.valid?(valid_struct)
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
            %TestStruct1{
              param_croma_builtin: 1,
              param_datetime_related: ~D[1970-01-01],
              param_nilable: 1,
              param_with_throwable_preprocessor: 1,
              param_with_result_preprocessor: 1
            }
            |> Map.put(field, invalid_value)

          refute TestStruct1.valid?(invalid_struct)
        end)
      end)
    end
  end

  defmodule TestStruct2 do
    use BaseParamStruct,
      accept_case: :snake,
      fields: [paramNamedWithMultipleWords: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :snake" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its snake case" do
      assert {:ok, %TestStruct2{paramNamedWithMultipleWords: 1}} =
               TestStruct2.new(%{paramNamedWithMultipleWords: 1})

      assert {:ok, %TestStruct2{paramNamedWithMultipleWords: 1}} =
               TestStruct2.new(%{param_named_with_multiple_words: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing, [TestStruct2, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStruct2.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing, [TestStruct2, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStruct2.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :snake" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its snake case" do
      assert {:ok, %TestStruct2{paramNamedWithMultipleWords: 1}} =
               TestStruct2.from_params(%{"paramNamedWithMultipleWords" => 1})

      assert {:ok, %TestStruct2{paramNamedWithMultipleWords: 1}} =
               TestStruct2.from_params(%{"param_named_with_multiple_words" => 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing, [TestStruct2, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStruct2.from_params(%{"ParamNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing, [TestStruct2, {Croma.PosInteger, :paramNamedWithMultipleWords}]}} =
               TestStruct2.from_params(%{"PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1})
    end
  end

  defmodule TestStruct3 do
    use BaseParamStruct,
      accept_case: :upper_camel,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :upper_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its upper camel case" do
      assert {:ok, %TestStruct3{param_named_with_multiple_words: 1}} =
               TestStruct3.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStruct3{param_named_with_multiple_words: 1}} =
               TestStruct3.new(%{ParamNamedWithMultipleWords: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct3, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct3.new(%{paramNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [TestStruct3, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct3.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :upper_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its upper camel case" do
      assert {:ok, %TestStruct3{param_named_with_multiple_words: 1}} =
               TestStruct3.from_params(%{"param_named_with_multiple_words" => 1})

      assert {:ok, %TestStruct3{param_named_with_multiple_words: 1}} =
               TestStruct3.from_params(%{"ParamNamedWithMultipleWords" => 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct3, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct3.from_params(%{"paramNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing,
               [TestStruct3, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct3.from_params(%{"PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1})
    end
  end

  defmodule TestStruct4 do
    use BaseParamStruct,
      accept_case: :lower_camel,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :lower_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its lower camel case" do
      assert {:ok, %TestStruct4{param_named_with_multiple_words: 1}} =
               TestStruct4.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStruct4{param_named_with_multiple_words: 1}} =
               TestStruct4.new(%{paramNamedWithMultipleWords: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct4, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct4.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [TestStruct4, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct4.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :lower_camel" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its lower camel case" do
      assert {:ok, %TestStruct4{param_named_with_multiple_words: 1}} =
               TestStruct4.from_params(%{"param_named_with_multiple_words" => 1})

      assert {:ok, %TestStruct4{param_named_with_multiple_words: 1}} =
               TestStruct4.from_params(%{"paramNamedWithMultipleWords" => 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct4, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct4.from_params(%{"ParamNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing,
               [TestStruct4, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct4.from_params(%{"PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1})
    end
  end

  defmodule TestStruct5 do
    use BaseParamStruct,
      accept_case: :capital,
      fields: [param_named_with_multiple_words: Croma.PosInteger]
  end

  describe "new/1 of a struct module based on BaseParamStruct with accept_case: :capital" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its capital case" do
      assert {:ok, %TestStruct5{param_named_with_multiple_words: 1}} =
               TestStruct5.new(%{param_named_with_multiple_words: 1})

      assert {:ok, %TestStruct5{param_named_with_multiple_words: 1}} =
               TestStruct5.new(%{PARAM_NAMED_WITH_MULTIPLE_WORDS: 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct5, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct5.new(%{ParamNamedWithMultipleWords: 1})

      assert {:error,
              {:value_missing,
               [TestStruct5, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct5.new(%{paramNamedWithMultipleWords: 1})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with accept_case: :capital" do
    test "should return :ok with a struct if all fields are valid and the field name is either the same as the field name in the definition or its capital case" do
      assert {:ok, %TestStruct5{param_named_with_multiple_words: 1}} =
               TestStruct5.from_params(%{"param_named_with_multiple_words" => 1})

      assert {:ok, %TestStruct5{param_named_with_multiple_words: 1}} =
               TestStruct5.from_params(%{"PARAM_NAMED_WITH_MULTIPLE_WORDS" => 1})
    end

    test "should return value missing error if the field name is not acceptable" do
      assert {:error,
              {:value_missing,
               [TestStruct5, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct5.from_params(%{"ParamNamedWithMultipleWords" => 1})

      assert {:error,
              {:value_missing,
               [TestStruct5, {Croma.PosInteger, :param_named_with_multiple_words}]}} =
               TestStruct5.from_params(%{paramNamedWithMultipleWords: 1})
    end
  end

  defmodule TestStruct6 do
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
              %TestStruct6{
                param_default_by_mod: 1,
                param_default_by_val: 2,
                param_pp_default_by_val: ~D[1970-01-01]
              }} =
               TestStruct6.new(%{
                 param_default_by_mod: 1,
                 param_default_by_val: 2,
                 param_pp_default_by_val: ~D[1970-01-01]
               })
    end

    test "should return :ok with a struct if a field which has a default value is missing" do
      assert {:ok,
              %TestStruct6{
                param_default_by_mod: 1_000,
                param_default_by_val: 2_000,
                param_pp_default_by_val: ~D[2001-01-01]
              }} = TestStruct6.new(%{})
    end
  end

  describe "from_params/1 of a struct module based on BaseParamStruct with default values" do
    test "should return :ok with a struct if all fields are valid" do
      assert {:ok,
              %TestStruct6{
                param_default_by_mod: 1,
                param_default_by_val: 2,
                param_pp_default_by_val: ~D[1970-01-01]
              }} =
               TestStruct6.from_params(%{
                 "param_default_by_mod" => 1,
                 "param_default_by_val" => 2,
                 "param_pp_default_by_val" => "1970-01-01"
               })
    end

    test "should return :ok with a struct if a field which has a default value is missing" do
      assert {:ok,
              %TestStruct6{
                param_default_by_mod: 1_000,
                param_default_by_val: 2_000,
                param_pp_default_by_val: ~D[2001-01-01]
              }} = TestStruct6.from_params(%{})
    end
  end
end
