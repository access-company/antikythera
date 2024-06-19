# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonList do
  @moduledoc """
  Module for defining a list of JSON objects with a preprocessor function.

  This module is designed for request body validation (see `Antikythera.Plug.ParamsValidator` and `Antikythera.BodyJsonStruct`).
  You can define a type-safe list with a preprocessor function.

  ## Usage

  To define a list of JSON objects with a preprocessor function, `use` this module in a module.

      defmodule Dates do
        use Antikythera.BodyJsonList, elem_module: {Date, &Date.to_iso8601/1}
      end

  You can use it for request body validation in a controller module, as shown below.

      defmodule MyBody do
        use Antikythera.BodyJsonStruct, fields: [dates: Dates]
      end

      plug Antikythera.Plug.ParamsValidator, :validate, body: MyBody

  When a request with the following JSON body is sent to the controller, it is validated by `MyBody`.
  Every element in the `dates` field is converted to an `Date` struct by the `Date.to_iso8601/1` preprocessor.

      {
        "dates": ["1970-01-01", "1970-01-02", "1970-01-03"]
      }

  ## Options

  - `elem_module`: The module that defines the type of each element in the list. It must either have a `valid?/1` function or be a struct with a preprocessor function.
  - `min_length`: The minimum length of the list. If not specified, there is no minimum length.
  - `max_length`: The maximum length of the list. If not specified, there is no maximum length.
  """

  alias Antikythera.BaseParamStruct
  alias Antikythera.BodyJsonStruct

  @doc false
  defun preprocess_params(
          list_mod :: module(),
          elem_mod :: module(),
          preprocessor :: BodyJsonStruct.Preprocessor.t(),
          params :: list()
        ) :: Croma.Result.t(list(), BaseParamStruct.validate_error_t()) do
    Enum.map(params, fn elem -> preprocess_elem(elem, elem_mod, preprocessor) end)
    |> Croma.Result.sequence()
    |> Croma.Result.map_error(fn {reason, mods} -> {reason, [list_mod | mods]} end)
  end

  defunp preprocess_elem(
           elem :: BaseParamStruct.json_value_t(),
           mod :: module(),
           preprocessor :: BodyJsonStruct.Preprocessor.t()
         ) :: Croma.Result.t(term(), BaseParamStruct.validate_error_t()) do
    try do
      case preprocessor.(elem) do
        {:ok, v} ->
          {:ok, v}

        {:error, {reason, mods}}
        when reason in [:invalid_value, :value_missing] and is_list(mods) ->
          {:error, {reason, [mod | mods]}}

        {:error, _} ->
          {:error, {:invalid_value, [mod]}}

        v ->
          {:ok, v}
      end
    rescue
      _error -> {:error, {:invalid_value, [mod]}}
    end
  end

  @doc false
  defun new_impl(list_mod :: module(), elem_mod :: module(), value :: list()) ::
          Croma.Result.t(list(), BaseParamStruct.validate_error_t()) do
    Enum.map(value, fn v -> validate_field(v, elem_mod) end)
    |> Croma.Result.sequence()
    |> case do
      {:ok, _} = result ->
        result

      {:error, {reason, mods}}
      when reason in [:invalid_value, :value_missing] and is_list(mods) ->
        {:error, {reason, [list_mod | mods]}}
    end
  end

  defunp validate_field(value :: term(), mod :: v[module()]) ::
           Croma.Result.t(term(), BaseParamStruct.validate_error_t()) do
    if valid_field?(value, mod), do: {:ok, value}, else: {:error, {:invalid_value, [mod]}}
  end

  @doc false
  defdelegate valid_field?(value, mod), to: BaseParamStruct

  @doc false
  defun extract_preprocessor_or_default(
          mod :: {module(), BodyJsonStruct.Preprocessor.t()} | module(),
          default :: BodyJsonStruct.Preprocessor.t()
        ) :: {module(), BodyJsonStruct.Preprocessor.t()} do
    {mod, preprocessor} = mod_with_preprocessor, _default
    when is_atom(mod) and is_function(preprocessor, 1) ->
      mod_with_preprocessor

    mod, default when is_atom(mod) ->
      case BodyJsonStruct.Preprocessor.default(mod) do
        {:ok, preprocessor} -> {mod, preprocessor}
        {:error, :no_default_preprocessor} -> {mod, default}
      end
  end

  defmacro __using__(opts) do
    quote bind_quoted: [
            elem_module: opts[:elem_module],
            min: opts[:min_length],
            max: opts[:max_length]
          ] do
      {mod, preprocessor} =
        Antikythera.BodyJsonList.extract_preprocessor_or_default(
          elem_module,
          &Function.identity/1
        )

      @mod mod
      @preprocessor preprocessor

      @type t :: [unquote(@mod).t]

      @min min
      @max max
      cond do
        is_nil(@min) and is_nil(@max) ->
          defguardp valid_length?(_len) when true

        is_nil(@min) ->
          defguardp valid_length?(len) when len <= @max

        is_nil(@max) ->
          defguardp valid_length?(len) when @min <= len

        true ->
          defguardp valid_length?(len) when @min <= len and len <= @max
      end

      defun valid?(value :: term()) :: boolean() do
        l when is_list(l) and valid_length?(length(l)) ->
          Enum.all?(l, fn v -> Antikythera.BodyJsonList.valid_field?(v, @mod) end)

        _ ->
          false
      end

      defun new(value :: term()) :: Croma.Result.t(t()) do
        l when is_list(l) and valid_length?(length(l)) ->
          Antikythera.BodyJsonList.new_impl(__MODULE__, @mod, l)

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun new!(value :: term()) :: t() do
        new(value) |> Croma.Result.get!()
      end

      defun from_params(params :: term()) :: Croma.Result.t(t()) do
        params when is_list(params) ->
          Antikythera.BodyJsonList.preprocess_params(__MODULE__, @mod, @preprocessor, params)
          |> Croma.Result.bind(&new/1)

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun from_params!(params :: term()) :: t() do
        from_params(params) |> Croma.Result.get!()
      end

      unless is_nil(@min) do
        defun min_length() :: non_neg_integer(), do: @min
      end

      unless is_nil(@max) do
        defun max_length() :: non_neg_integer(), do: @max
      end
    end
  end
end
