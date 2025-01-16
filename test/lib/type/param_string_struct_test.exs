# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ParamStringStructTest do
  use Croma.TestCase
  use ExUnitProperties

  defunp croma_builtins_with_generators() :: v[[{module, (-> StreamData.t(term))}]] do
    [
      {Croma.Boolean, fn -> boolean() end},
      {Croma.Float, fn -> float() end},
      {Croma.Integer, fn -> integer() end},
      {Croma.NegInteger, fn -> positive_integer() |> map(&(-&1)) end},
      {Croma.NonNegInteger, fn -> non_negative_integer() end},
      {Croma.Number, fn -> one_of([float(), integer()]) end},
      {Croma.PosInteger, fn -> positive_integer() end},
      {Croma.String, fn -> string(:utf8) end}
    ]
  end

  describe "default preprocessor" do
    property "should convert a string to its corresponding Croma built-in types if the string can be naturally converted" do
      croma_builtins_with_generators()
      |> Enum.each(fn {mod, gen} ->
        assert {:ok, f} = ParamStringStruct.PreprocessorGenerator.generate(mod)

        check all(v <- gen.()) do
          case f.(to_string(v)) do
            {:ok, x} -> assert x === v
            x -> assert x === v
          end
        end
      end)
    end

    property "should convert a string to its corresponding nilable Croma built-in types if the string can be naturally converted" do
      croma_builtins_with_generators()
      |> Enum.each(fn {mod, gen} ->
        assert {:ok, f} =
                 ParamStringStruct.PreprocessorGenerator.generate(Croma.TypeGen.nilable(mod))

        check all(v <- gen.()) do
          case f.(to_string(v)) do
            {:ok, x} -> assert x === v
            x -> assert x === v
          end
        end
      end)
    end

    test "should accept nil as a nilable Croma built-in type" do
      croma_builtins_with_generators()
      |> Enum.each(fn {mod, _gen} ->
        assert {:ok, f} =
                 ParamStringStruct.PreprocessorGenerator.generate(Croma.TypeGen.nilable(mod))

        case f.(nil) do
          {:ok, x} -> assert is_nil(x)
          x -> assert is_nil(x)
        end
      end)
    end

    test "should convert a string to its corresponding DateTime-related types if the string can be naturally converted" do
      [
        {Date, [~D[1970-01-01], ~D[9999-12-31]]},
        {DateTime, [~U[1970-01-01T00:00:00Z], ~U[9999-12-31T23:59:59.999999Z]]},
        {NaiveDateTime, [~N[1970-01-01T00:00:00], ~N[9999-12-31T23:59:59.999999]]},
        {Time, [~T[00:00:00], ~T[23:59:59.999999]]}
      ]
      |> Enum.each(fn {mod, valid_values} ->
        assert {:ok, f} = ParamStringStruct.PreprocessorGenerator.generate(mod)

        Enum.each(valid_values, fn v ->
          case f.(to_string(v)) do
            {:ok, x} -> assert x === v
            x -> assert x === v
          end
        end)
      end)
    end

    test "should convert a string to DateTime if the string is in ISO 8601 format with an arbitrary time zone" do
      assert {:ok, f} = ParamStringStruct.PreprocessorGenerator.generate(DateTime)

      case f.("2024-02-01T00:00:00+09:00") do
        {:ok, x} -> assert x === ~U[2024-01-31T15:00:00Z]
        x -> assert x === ~U[2024-01-31T15:00:00Z]
      end
    end

    test "should not be defined for unsupported types" do
      defmodule Time do
        use Croma.SubtypeOfInt, min: 0, max: 86_399
      end

      [Time, Croma.TypeGen.nilable(Croma.Atom)]
      |> Enum.each(fn mod ->
        assert {:error, :no_default_preprocessor} =
                 ParamStringStruct.PreprocessorGenerator.generate(mod)
      end)
    end
  end

  defmodule TestParamStringStruct do
    use ParamStringStruct,
      fields: [
        param_boolean: Croma.Boolean,
        param_float: Croma.Float,
        param_integer: Croma.Integer,
        param_neg_integer: Croma.NegInteger,
        param_non_neg_integer: Croma.NonNegInteger,
        param_number: Croma.Number,
        param_pos_integer: Croma.PosInteger,
        param_string: Croma.String,
        param_date: Date,
        param_datetime: DateTime,
        param_naive_datetime: NaiveDateTime,
        param_time: Time
      ]
  end

  describe "from_params/1 of a struct module based on ParamStringStruct" do
    test "should return :ok with a struct if all parameters are valid" do
      params = %{
        "param_boolean" => "true",
        "param_float" => "1.0",
        "param_integer" => "1",
        "param_neg_integer" => "-1",
        "param_non_neg_integer" => "0",
        "param_number" => "1",
        "param_pos_integer" => "1",
        "param_string" => "string",
        "param_date" => "2024-02-01",
        "param_datetime" => "2024-02-01T00:00:00+09:00",
        "param_naive_datetime" => "2024-02-01T00:00:00",
        "param_time" => "00:00:00"
      }

      assert {:ok,
              %TestParamStringStruct{
                param_boolean: true,
                param_float: 1.0,
                param_integer: 1,
                param_neg_integer: -1,
                param_non_neg_integer: 0,
                param_number: 1,
                param_pos_integer: 1,
                param_string: "string",
                param_date: ~D[2024-02-01],
                param_datetime: ~U[2024-01-31T15:00:00Z],
                param_naive_datetime: ~N[2024-02-01T00:00:00],
                param_time: ~T[00:00:00]
              }} = TestParamStringStruct.from_params(params)
    end

    test "should return invalid value error if a parameter is invalid" do
      [
        {"param_boolean", ["nil", "invalid"]},
        {"param_float", ["0", "invalid"]},
        {"param_integer", ["0.0", "invalid"]},
        {"param_neg_integer", ["0", "invalid"]},
        {"param_non_neg_integer", ["-1", "invalid"]},
        {"param_number", ["invalid"]},
        {"param_pos_integer", ["0", "invalid"]},
        {"param_date", ["2024-02-30", "invalid"]},
        {"param_datetime", ["2024-02-01T00:00:00", "invalid"]},
        {"param_naive_datetime", ["2024-02-30T00:00:00", "invalid"]},
        {"param_time", ["24:00:00", "invalid"]}
      ]
      |> Enum.each(fn {field_name, invalid_values} ->
        Enum.each(invalid_values, fn invalid_value ->
          params =
            %{
              "param_boolean" => "true",
              "param_float" => "1.0",
              "param_integer" => "1",
              "param_neg_integer" => "-1",
              "param_non_neg_integer" => "0",
              "param_number" => "1",
              "param_pos_integer" => "1",
              "param_string" => "string",
              "param_date" => "2024-02-01",
              "param_datetime" => "2024-02-01T00:00:00+09:00",
              "param_naive_datetime" => "2024-02-01T00:00:00",
              "param_time" => "00:00:00"
            }
            |> Map.put(field_name, invalid_value)

          field_name_atom = String.to_existing_atom(field_name)

          assert {:error, {:invalid_value, [TestParamStringStruct, {_type, ^field_name_atom}]}} =
                   TestParamStringStruct.from_params(params)
        end)
      end)
    end

    test "should return value missing error if a parameter is missing" do
      [
        "param_boolean",
        "param_float",
        "param_integer",
        "param_neg_integer",
        "param_non_neg_integer",
        "param_number",
        "param_pos_integer",
        "param_string",
        "param_date",
        "param_datetime",
        "param_naive_datetime",
        "param_time"
      ]
      |> Enum.each(fn field_name ->
        params =
          %{
            "param_boolean" => "true",
            "param_float" => "1.0",
            "param_integer" => "1",
            "param_neg_integer" => "-1",
            "param_non_neg_integer" => "0",
            "param_number" => "1",
            "param_pos_integer" => "1",
            "param_string" => "string",
            "param_date" => "2024-02-01",
            "param_datetime" => "2024-02-01T00:00:00+09:00",
            "param_naive_datetime" => "2024-02-01T00:00:00",
            "param_time" => "00:00:00"
          }
          |> Map.delete(field_name)

        field_name_atom = String.to_existing_atom(field_name)

        assert {:error, {:value_missing, [TestParamStringStruct, {_type, ^field_name_atom}]}} =
                 TestParamStringStruct.from_params(params)
      end)
    end
  end
end
