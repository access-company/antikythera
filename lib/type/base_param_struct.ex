# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BaseParamStruct do
  @moduledoc """
  *TBD*
  """

  @type json_value_t() ::
          boolean()
          | number()
          | String.t()
          | list(json_value_t())
          | %{required(String.t()) => json_value_t()}

  @type params_t() :: %{required(atom() | String.t()) => json_value_t()}
  @type validate_error_reason_t() :: :invalid_value | :value_missing
  @type validate_error_t() :: {validate_error_reason_t(), list(module() | {module(), atom()})}

  @typep validatable_t() :: term()
  @type preprocessor_t() ::
          (nil | json_value_t() -> Croma.Result.t(validatable_t()) | validatable_t())

  @doc false
  defun compute_default_value(mod :: v[module()]) :: Croma.Result.t(term(), :no_default_value) do
    try do
      {:ok, mod.default()}
    rescue
      UndefinedFunctionError -> {:error, :no_default_value}
    end
  end

  @doc false
  defun preprocess_params(
          struct_mod :: v[module()],
          fields_with_pps :: list({atom(), module(), preprocessor_t()}),
          params :: params_t()
        ) :: Croma.Result.t(%{required(atom()) => term()}, validate_error_t()) do
    Enum.reduce_while(fields_with_pps, {:ok, %{}}, fn {field_name, _mod, _preprocessor} =
                                                        field_with_pp,
                                                      {:ok, preprocessed} ->
      get_param(params, field_name)
      |> preprocess_param(field_with_pp)
      |> case do
        {:ok, v} -> {:cont, {:ok, Map.put(preprocessed, field_name, v)}}
        {:error, {reason, mods}} -> {:halt, {:error, {reason, [struct_mod | mods]}}}
      end
    end)
  end

  defunp preprocess_param(
           param :: nil | json_value_t(),
           {field_name, mod, preprocessor} :: {atom(), module(), preprocessor_t()}
         ) :: Croma.Result.t(validatable_t(), validate_error_t()) do
    error_reason = if is_nil(param), do: :value_missing, else: :invalid_value

    try do
      case preprocessor.(param) do
        {:ok, v} ->
          {:ok, v}

        {:error, {reason, [^mod | mods]}} when reason in [:invalid_value, :value_missing] ->
          {:error, {reason, [{mod, field_name} | mods]}}

        {:error, _} ->
          {:error, {error_reason, [{mod, field_name}]}}

        v ->
          {:ok, v}
      end
    rescue
      _error -> {:error, {error_reason, [{mod, field_name}]}}
    end
  end

  defunp get_param(params :: params_t(), field_name :: atom()) :: nil | json_value_t() do
    field_name_str = Atom.to_string(field_name)

    cond do
      Map.has_key?(params, field_name) -> params[field_name]
      Map.has_key?(params, field_name_str) -> params[field_name_str]
      true -> nil
    end
  end

  @doc false
  defun new_impl(
          struct_mod :: module(),
          fields_with_default_values ::
            list({atom(), module(), Croma.Result.t(term(), :no_default_value)}),
          dict :: term()
        ) ::
          Croma.Result.t(struct(), validate_error_t()) do
    struct_mod, fields_with_default_values, dict
    when is_atom(struct_mod) and is_list(fields_with_default_values) and
           (is_list(dict) or is_map(dict)) ->
      Enum.map(fields_with_default_values, fn {field_name, mod, default_value_opt} ->
        fetch_and_validate_field(dict, field_name, mod, default_value_opt)
      end)
      |> Croma.Result.sequence()
      |> case do
        {:ok, kvs} ->
          {:ok, struct_mod.__struct__(kvs)}

        {:error, {reason, mods}}
        when reason in [:invalid_value, :value_missing] and is_list(mods) ->
          {:error, {reason, [struct_mod | mods]}}
      end

    struct_mod, _, _ when is_atom(struct_mod) ->
      {:error, {:invalid_value, [struct_mod]}}
  end

  defunp fetch_and_validate_field(
           dict ::
             list({atom() | String.t(), term()}) | %{required(atom() | String.t()) => term()},
           field_name :: v[atom()],
           mod :: v[module()],
           default_value_opt :: Croma.Result.t(term(), :no_default_value) \\ {:error,
            :no_default_value}
         ) :: Croma.Result.t({atom(), term()}, validate_error_t()) do
    case fetch_from_dict(dict, field_name) do
      {:ok, value} ->
        case validate_field(value, mod) do
          {:ok, v} ->
            {:ok, {field_name, v}}

          {:error, {reason, [^mod | mods]}} when reason in [:invalid_value, :value_missing] ->
            {:error, {reason, [{mod, field_name} | mods]}}
        end

      :error ->
        case default_value_opt do
          {:ok, default_value} -> {:ok, {field_name, default_value}}
          {:error, :no_default_value} -> {:error, {:value_missing, [{mod, field_name}]}}
        end
    end
  end

  defunp fetch_from_dict(
           dict ::
             list({atom() | String.t(), term()}) | %{required(atom() | String.t()) => term()},
           key :: atom()
         ) :: {:ok, term()} | :error do
    dict, key when is_list(dict) ->
      key_str = Atom.to_string(key)

      Enum.find_value(dict, :error, fn
        {k, v} when k == key or k == key_str -> {:ok, v}
        _ -> nil
      end)

    dict, key when is_map(dict) ->
      case Map.fetch(dict, key) do
        {:ok, _} = result -> result
        :error -> Map.fetch(dict, Atom.to_string(key))
      end
  end

  defunp validate_field(value :: term(), mod :: v[module()]) ::
           Croma.Result.t(term(), validate_error_t()) do
    if valid_field?(value, mod), do: {:ok, value}, else: {:error, {:invalid_value, [mod]}}
  end

  @doc false
  defun valid_field?(value :: term(), mod :: v[module()]) :: boolean() do
    if :code.get_mode() == :interactive do
      true = Code.ensure_loaded?(mod)
    end

    cond do
      function_exported?(mod, :valid?, 1) -> mod.valid?(value)
      function_exported?(mod, :__struct__, 0) -> is_struct(value, mod)
    end
  end

  @doc false
  defun update_impl(
          s :: struct(),
          struct_mod :: module(),
          fields :: list({atom(), module()}),
          dict :: term()
        ) ::
          Croma.Result.t(struct(), validate_error_t()) do
    s, struct_mod, fields, dict
    when is_atom(struct_mod) and is_struct(s, struct_mod) and (is_list(dict) or is_map(dict)) ->
      Enum.map(fields, fn {field_name, mod} -> fetch_and_validate_field(dict, field_name, mod) end)
      |> Enum.reject(&match?({:error, {:value_missing, _}}, &1))
      |> Croma.Result.sequence()
      |> case do
        {:ok, kvs} ->
          {:ok, struct(s, kvs)}

        {:error, {reason, mods}}
        when reason in [:invalid_value, :value_missing] and is_list(mods) ->
          {:error, {reason, [struct_mod | mods]}}
      end

    s, struct_mod, _, _ when is_struct(s, struct_mod) and is_atom(struct_mod) ->
      {:error, {:invalid_value, [struct_mod]}}
  end

  @doc false
  defun treat_invalid_missing_value_as_value_missing_error(
          struct_mod :: module(),
          params :: params_t(),
          error :: validate_error_t()
        ) :: validate_error_t() do
    struct_mod, params, {:invalid_value, [mod, {_type_mod, field_name} | _] = mods}
    when struct_mod == mod ->
      field_name_str = Atom.to_string(field_name)

      if Map.has_key?(params, field_name) or Map.has_key?(params, field_name_str) do
        {:invalid_value, mods}
      else
        {:value_missing, mods}
      end

    _, _, error ->
      error
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      default_pp =
        Keyword.get(opts, :default_preprocessor, fn _ -> {:error, :no_default_preprocessor} end)

      fields_with_preprocessors =
        Keyword.fetch!(opts, :fields)
        |> Enum.map(fn
          {field_name, {mod, preprocessor}}
          when is_atom(field_name) and is_atom(mod) and is_function(preprocessor, 1) ->
            {field_name, mod, preprocessor}

          {field_name, mod} when is_atom(field_name) and is_atom(mod) ->
            case default_pp.(mod) do
              {:ok, preprocessor} -> {field_name, mod, preprocessor}
              {:error, :no_default_preprocessor} -> {field_name, mod, &Function.identity/1}
            end
        end)

      fields =
        Enum.map(fields_with_preprocessors, fn {field_name, mod, _preprocessor} ->
          {field_name, mod}
        end)

      fields_with_default_values =
        Enum.map(fields, fn {field_name, mod} ->
          {field_name, mod, Antikythera.BaseParamStruct.compute_default_value(mod)}
        end)

      @base_param_struct_fields fields
      @base_param_struct_fields_with_preprocessors fields_with_preprocessors
      @base_param_struct_fields_with_default_values fields_with_default_values

      use Croma
      use Croma.Struct, fields: fields

      defun from_params(params :: term()) :: Croma.Result.t(t()) do
        params when is_map(params) ->
          Antikythera.BaseParamStruct.preprocess_params(
            __MODULE__,
            @base_param_struct_fields_with_preprocessors,
            params
          )
          |> Croma.Result.bind(&new/1)
          |> Croma.Result.map_error(
            &Antikythera.BaseParamStruct.treat_invalid_missing_value_as_value_missing_error(
              __MODULE__,
              params,
              &1
            )
          )

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun from_params!(params :: Antikythera.BaseParamStruct.params_t()) :: t() do
        from_params(params) |> Croma.Result.get!()
      end

      # Override
      def new(dict) do
        Antikythera.BaseParamStruct.new_impl(
          __MODULE__,
          @base_param_struct_fields_with_default_values,
          dict
        )
      end

      # Override
      def update(s, dict) do
        Antikythera.BaseParamStruct.update_impl(s, __MODULE__, @base_param_struct_fields, dict)
      end

      # Override
      def valid?(%__MODULE__{} = s) do
        Enum.all?(@base_param_struct_fields, fn {field_name, mod} ->
          Map.fetch!(s, field_name) |> Antikythera.BaseParamStruct.valid_field?(mod)
        end)
      end

      def valid?(_), do: false

      defoverridable from_params: 1, from_params!: 1, new: 1, update: 2, valid?: 1
    end
  end
end
