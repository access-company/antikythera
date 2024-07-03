# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.BaseParamStruct do
  @moduledoc """
  Base module to define a struct that represents abstract parameters.
  """

  alias Croma.Result, as: R

  @type json_value_t ::
          boolean
          | number
          | String.t()
          | [json_value_t]
          | %{String.t() => json_value_t}

  @type params_t :: %{(atom | String.t()) => json_value_t}
  @type validate_error_reason_t :: :invalid_value | :value_missing
  @type validate_error_t :: {validate_error_reason_t, [module | {module, atom}]}

  @typep validatable_t :: term
  @typep preprocessor_t :: (nil | json_value_t -> R.t(validatable_t) | validatable_t)
  @typep accept_case_t :: :snake | :lower_camel | :upper_camel | :capital
  @typep default_value_opt_t :: R.t(term, :no_default_value)
  @typep field_option_t :: {:default, term}
  @typep mod_with_options_t ::
           module
           | {module, preprocessor_t}
           | {module, [field_option_t]}
           | {module, preprocessor_t, [field_option_t]}
  @typep field_t :: {atom, mod_with_options_t}
  @typep field_with_attr_t ::
           {atom, [atom], module, preprocessor_t, default_value_opt_t}

  @doc false
  defun attach_attributes_to_field(
          {field_name, mod_with_options} :: field_t,
          accept_case :: nil | accept_case_t,
          pp_generator :: (module -> R.t(term, :no_default_preprocessor))
        ) :: field_with_attr_t do
    accepted_field_names = compute_accepted_field_names(field_name, accept_case)

    {mod, preprocessor, default_value_opt} =
      extract_mod_and_options(mod_with_options, pp_generator)

    {field_name, accepted_field_names, mod, preprocessor, default_value_opt}
  end

  defunp extract_mod_and_options(
           mod_with_options :: mod_with_options_t,
           pp_generator :: (module -> R.t(term, :no_default_preprocessor))
         ) :: {module, preprocessor_t, default_value_opt_t} do
    {mod, preprocessor, [default: default_value]}, _pp_generator
    when is_atom(mod) and is_function(preprocessor, 1) ->
      {mod, preprocessor, {:ok, default_value}}

    {mod, preprocessor}, _pp_generator when is_atom(mod) and is_function(preprocessor, 1) ->
      {mod, preprocessor, compute_default_value(mod)}

    {mod, [default: default_value]}, pp_generator when is_atom(mod) ->
      {mod, R.get(pp_generator.(mod), &Function.identity/1), {:ok, default_value}}

    mod, pp_generator when is_atom(mod) ->
      {mod, R.get(pp_generator.(mod), &Function.identity/1), compute_default_value(mod)}
  end

  defunp compute_default_value(mod :: v[module]) :: default_value_opt_t do
    try do
      {:ok, mod.default()}
    rescue
      UndefinedFunctionError -> {:error, :no_default_value}
    end
  end

  defunp compute_accepted_field_names(field_name :: atom, accept_case :: nil | accept_case_t) :: [
           atom
         ] do
    field_name, nil when is_atom(field_name) ->
      [field_name]

    field_name, accept_case
    when is_atom(field_name) and accept_case in [:snake, :lower_camel, :upper_camel, :capital] ->
      converter =
        case accept_case do
          :snake -> &Macro.underscore/1
          :lower_camel -> &lower_camelize/1
          :upper_camel -> &Macro.camelize/1
          :capital -> &String.upcase/1
        end

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      converted_field_name = Atom.to_string(field_name) |> converter.() |> String.to_atom()
      Enum.uniq([field_name, converted_field_name])
  end

  defunp lower_camelize(s :: v[String.t()]) :: v[String.t()] do
    case Macro.camelize(s) do
      "" -> ""
      <<c::utf8>> <> rest -> String.downcase(<<c>>) <> rest
    end
  end

  @doc false
  defun preprocess_params(
          struct_mod :: v[module],
          fields_with_attrs :: v[[field_with_attr_t]],
          params :: params_t
        ) :: R.t(%{atom => term}, validate_error_t) do
    Enum.map(fields_with_attrs, fn {field_name, accepted_field_names, mod, preprocessor,
                                    default_value_opt} ->
      case get_param(params, field_name, accepted_field_names, mod, default_value_opt) do
        {:ok, param} ->
          preprocess_param(param, field_name, mod, preprocessor)
          |> R.map(&{field_name, &1})

        {:default, default_value} ->
          {:ok, {field_name, default_value}}

        {:error, error} ->
          {:error, error}
      end
    end)
    |> R.sequence()
    |> case do
      {:ok, kvs} -> {:ok, Map.new(kvs)}
      {:error, {reason, mods}} -> {:error, {reason, [struct_mod | mods]}}
    end
  end

  defunp get_param(
           params :: params_t,
           field_name :: atom,
           accepted_field_names :: [atom],
           mod :: module,
           default_value_opt :: default_value_opt_t
         ) :: R.t(nil | json_value_t, validate_error_t) | {:default, term} do
    _params, _field_name, [], _mod, {:ok, default_value} ->
      {:default, default_value}

    _params, field_name, [], mod, {:error, :no_default_value} ->
      {:error, {:value_missing, [{mod, field_name}]}}

    params, field_name, [accepted_field_name | rest], mod, default_value_opt ->
      case try_get_param(params, accepted_field_name) do
        {:ok, value} -> {:ok, value}
        {:error, :no_value} -> get_param(params, field_name, rest, mod, default_value_opt)
      end
  end

  defunp try_get_param(params :: params_t, field_name :: v[atom]) ::
           R.t(nil | json_value_t, :no_value) do
    field_name_str = Atom.to_string(field_name)

    cond do
      is_map_key(params, field_name) -> {:ok, params[field_name]}
      is_map_key(params, field_name_str) -> {:ok, params[field_name_str]}
      true -> {:error, :no_value}
    end
  end

  defunp preprocess_param(
           param :: nil | json_value_t,
           field_name :: v[atom],
           mod :: v[module],
           preprocessor :: preprocessor_t
         ) :: R.t(validatable_t, validate_error_t) do
    try do
      case preprocessor.(param) do
        {:ok, v} ->
          {:ok, v}

        {:error, {reason, [^mod | mods]}} when reason in [:invalid_value, :value_missing] ->
          {:error, {reason, [{mod, field_name} | mods]}}

        {:error, _} ->
          {:error, {:invalid_value, [{mod, field_name}]}}

        v ->
          {:ok, v}
      end
    rescue
      _error -> {:error, {:invalid_value, [{mod, field_name}]}}
    end
  end

  @doc false
  defun new_impl(
          struct_mod :: module,
          fields_with_attrs :: [field_with_attr_t],
          dict :: term
        ) :: R.t(struct, validate_error_t) do
    struct_mod, fields_with_attrs, dict when is_list(dict) or is_map(dict) ->
      Enum.map(fields_with_attrs, fn {field_name, accepted_field_names, mod, _preprocessor,
                                      default_value_opt} ->
        fetch_and_validate_field(dict, field_name, accepted_field_names, mod, default_value_opt)
      end)
      |> R.sequence()
      |> case do
        {:ok, kvs} ->
          {:ok, struct_mod.__struct__(kvs)}

        {:error, {reason, mods}}
        when reason in [:invalid_value, :value_missing] and is_list(mods) ->
          {:error, {reason, [struct_mod | mods]}}
      end

    struct_mod, _, _ ->
      {:error, {:invalid_value, [struct_mod]}}
  end

  defunp fetch_and_validate_field(
           dict :: v[[{atom | String.t(), term}] | %{(atom | String.t()) => term}],
           field_name :: v[atom],
           accepted_field_names :: v[[atom]],
           mod :: v[module],
           default_value_opt :: default_value_opt_t \\ {:error, :no_default_value}
         ) :: R.t({atom, term}, validate_error_t) do
    case fetch_from_dict(dict, field_name, accepted_field_names) do
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
           dict :: [{atom | String.t(), term}] | %{(atom | String.t()) => term},
           key :: atom,
           accepted_keys :: [atom]
         ) :: {:ok, term} | :error do
    _dict, _key, [] ->
      :error

    dict, key, [accepted_key | rest] ->
      case try_fetch_from_dict(dict, accepted_key) do
        {:ok, value} -> {:ok, value}
        :error -> fetch_from_dict(dict, key, rest)
      end
  end

  defunp try_fetch_from_dict(
           dict :: [{atom | String.t(), term}] | %{(atom | String.t()) => term},
           key :: atom
         ) :: {:ok, term} | :error do
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

  defunp validate_field(value :: term, mod :: v[module]) :: R.t(term, validate_error_t) do
    if valid_field?(value, mod), do: {:ok, value}, else: {:error, {:invalid_value, [mod]}}
  end

  @doc false
  defun valid_field?(value :: term, mod :: v[module]) :: boolean do
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
          s :: struct,
          struct_mod :: module,
          fields :: [{atom, [atom], module}],
          dict :: term
        ) :: R.t(struct, validate_error_t) do
    s, struct_mod, fields, dict
    when is_struct(s, struct_mod) and (is_list(dict) or is_map(dict)) ->
      Enum.map(fields, fn {field_name, accept_field_names, mod} ->
        fetch_and_validate_field(dict, field_name, accept_field_names, mod)
      end)
      |> Enum.reject(&match?({:error, {:value_missing, _}}, &1))
      |> R.sequence()
      |> case do
        {:ok, kvs} ->
          {:ok, struct(s, kvs)}

        {:error, {reason, mods}}
        when reason in [:invalid_value, :value_missing] and is_list(mods) ->
          {:error, {reason, [struct_mod | mods]}}
      end

    s, struct_mod, _, _ when is_struct(s, struct_mod) ->
      {:error, {:invalid_value, [struct_mod]}}
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if opts[:accept_case] not in [nil, :snake, :lower_camel, :upper_camel, :capital] do
        raise ":accept_case option must be one of :snake, :lower_camel, :upper_camel, or :capital"
      end

      pp_generator =
        Keyword.get(opts, :preprocessor_generator, fn _mod ->
          {:error, :no_default_preprocessor}
        end)

      fields_with_attrs =
        Keyword.fetch!(opts, :fields)
        |> Enum.map(
          &AntikytheraCore.BaseParamStruct.attach_attributes_to_field(
            &1,
            opts[:accept_case],
            pp_generator
          )
        )

      fields =
        Enum.map(fields_with_attrs, fn {field_name, _field_names, mod, _preprocessor,
                                        _default_value_opt} ->
          {field_name, mod}
        end)

      fields_with_accept_fields =
        Enum.map(fields_with_attrs, fn {field_name, field_names, mod, _preprocessor,
                                        _default_value_opt} ->
          {field_name, field_names, mod}
        end)

      opts_for_croma_struct = Keyword.put(opts, :fields, fields)

      @base_param_struct_fields fields
      @base_param_struct_fields_with_attrs fields_with_attrs
      @base_param_struct_fields_with_accept_fields fields_with_accept_fields

      use Croma
      use Croma.Struct, opts_for_croma_struct

      defun from_params(params :: term) :: R.t(t()) do
        params when is_map(params) ->
          AntikytheraCore.BaseParamStruct.preprocess_params(
            __MODULE__,
            @base_param_struct_fields_with_attrs,
            params
          )
          |> R.bind(&new/1)

        _ ->
          {:error, {:invalid_value, [__MODULE__]}}
      end

      defun from_params!(params :: term) :: t() do
        from_params(params) |> R.get!()
      end

      # Override
      def new(dict) do
        AntikytheraCore.BaseParamStruct.new_impl(
          __MODULE__,
          @base_param_struct_fields_with_attrs,
          dict
        )
      end

      # Override
      def update(s, dict) do
        AntikytheraCore.BaseParamStruct.update_impl(
          s,
          __MODULE__,
          @base_param_struct_fields_with_accept_fields,
          dict
        )
      end

      # Override
      def valid?(%__MODULE__{} = s) do
        Enum.all?(@base_param_struct_fields, fn {field_name, mod} ->
          Map.fetch!(s, field_name) |> AntikytheraCore.BaseParamStruct.valid_field?(mod)
        end)
      end

      def valid?(_), do: false

      defoverridable from_params: 1, from_params!: 1, new: 1, update: 2, valid?: 1
    end
  end
end
