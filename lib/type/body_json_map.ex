# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonMap do
  @moduledoc """
  *TBD*
  """
  alias Antikythera.BaseParamStruct
  alias Antikythera.BodyJsonStruct

  @doc false
  defun preprocess_params(
          map_mod :: module(),
          value_mod :: module(),
          preprocessor :: BodyJsonStruct.Preprocessor.t(),
          params :: map()
        ) ::
          Croma.Result.t(map(), BaseParamStruct.validate_error_t()) do
    Enum.map(params, fn {k, v} ->
      preprocess_value(v, value_mod, preprocessor) |> Croma.Result.map(&{k, &1})
    end)
    |> Croma.Result.sequence()
    |> case do
      {:ok, kv_list} -> {:ok, Enum.into(kv_list, %{})}
      {:error, {reason, mods}} -> {:error, {reason, [map_mod | mods]}}
    end
  end

  defunp preprocess_value(
           value :: BaseParamStruct.json_value_t(),
           mod :: module(),
           preprocessor :: BodyJsonStruct.Preprocessor.t()
         ) ::
           Croma.Result.t(term(), BaseParamStruct.validate_error_t()) do
    try do
      case preprocessor.(value) do
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
  defun new_impl(map_mod :: module(), value_mod :: module(), value :: map()) ::
          Croma.Result.t(map(), BaseParamStruct.validate_error_t()) do
    Enum.map(value, fn
      {k, v} when is_binary(k) -> validate_field(v, value_mod) |> Croma.Result.map(&{k, &1})
      _ -> {:error, {:invalid_value, []}}
    end)
    |> Croma.Result.sequence()
    |> case do
      {:ok, kv_list} ->
        {:ok, Enum.into(kv_list, %{})}

      {:error, {reason, mods}}
      when reason in [:invalid_value, :value_missing] and is_list(mods) ->
        {:error, {reason, [map_mod | mods]}}
    end
  end

  defunp validate_field(value :: term(), mod :: module()) ::
           Croma.Result.t(term(), BaseParamStruct.validate_error_t()) do
    if valid_field?(value, mod), do: {:ok, value}, else: {:error, {:invalid_value, [mod]}}
  end

  @doc false
  defdelegate valid_field?(value, mod), to: BaseParamStruct

  defmacro __using__(opts) do
    quote bind_quoted: [
            value_module: opts[:value_module],
            min: opts[:min_size],
            max: opts[:max_size]
          ] do
      {mod, preprocessor} =
        Antikythera.BodyJsonList.extract_preprocessor_or_default(
          value_module,
          &Function.identity/1
        )

      @mod mod
      @preprocessor preprocessor

      @type t :: %{required(String.t()) => @mod.t()}

      @min min
      @max max
      cond do
        is_nil(@min) and is_nil(@max) ->
          defguardp valid_size?(_size) when true

        is_nil(@min) ->
          defguardp valid_size?(size) when size <= @max

        is_nil(@max) ->
          defguardp valid_size?(size) when @min <= size

        true ->
          defguardp valid_size?(size) when @min <= size and size <= @max
      end

      defun valid?(value :: term()) :: boolean() do
        m when is_map(m) and valid_size?(map_size(m)) ->
          Enum.all?(m, fn {k, v} ->
            is_binary(k) and Antikythera.BodyJsonMap.valid_field?(v, @mod)
          end)

        _ ->
          false
      end

      defun new(value :: term()) :: Croma.Result.t(t()) do
        m when is_map(m) and valid_size?(map_size(m)) ->
          Antikythera.BodyJsonMap.new_impl(__MODULE__, @mod, m)

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun new!(value :: term()) :: t() do
        new(value) |> Croma.Result.get!()
      end

      defun from_params(params :: term()) :: Croma.Result.t(t()) do
        m when is_map(m) ->
          Antikythera.BodyJsonMap.preprocess_params(__MODULE__, @mod, @preprocessor, m)
          |> Croma.Result.bind(&new/1)

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun from_params!(params :: term()) :: t() do
        from_params(params) |> Croma.Result.get!()
      end

      unless is_nil(@min) do
        defun min_size() :: non_neg_integer(), do: @min
      end

      unless is_nil(@max) do
        defun max_size() :: non_neg_integer(), do: @max
      end
    end
  end
end
