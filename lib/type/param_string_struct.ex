# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ParamStringStruct do
  @moduledoc """
  *TBD*
  """

  defmodule Preprocessor do
    @moduledoc false

    @type t :: (nil | String.t() -> Croma.Result.t() | term())

    @doc false
    defun default(mod :: v[module()]) :: Croma.Result.t(t()) do
      # The default preprocessors are defined as a capture form, which can be used in module attributes.
      case Module.split(mod) do
        # Preprocessors for Croma built-in types
        ["Croma", "Boolean"] ->
          {:ok, &__MODULE__.to_boolean/1}

        ["Croma", "Float"] ->
          {:ok, &String.to_float/1}

        ["Croma", "Integer"] ->
          {:ok, &String.to_integer/1}

        ["Croma", "NegInteger"] ->
          {:ok, &String.to_integer/1}

        ["Croma", "NonNegInteger"] ->
          {:ok, &String.to_integer/1}

        ["Croma", "Number"] ->
          {:ok, &__MODULE__.to_number/1}

        ["Croma", "PosInteger"] ->
          {:ok, &String.to_integer/1}

        ["Croma", "String"] ->
          {:ok, &__MODULE__.passthrough_string/1}

        # Preprocessors for DateTime-related types
        ["Date"] ->
          {:ok, &Date.from_iso8601/1}

        ["DateTime"] ->
          {:ok, &__MODULE__.to_datetime/1}

        ["NaiveDateTime"] ->
          {:ok, &NaiveDateTime.from_iso8601/1}

        ["Time"] ->
          {:ok, &Time.from_iso8601/1}

        # Preprocessors for nilable types
        ["Croma", "TypeGen", "Nilable" | original_mod_split] ->
          original_mod = Module.safe_concat(original_mod_split)

          original_mod
          |> default()
          |> Croma.Result.map(&generate_nilable_preprocessor(&1, original_mod))

        _ ->
          {:error, :no_default_preprocessor}
      end
    end

    @doc false
    defun to_boolean(s :: nil | String.t()) :: boolean() do
      "true" -> true
      "false" -> false
      s when is_binary(s) -> raise ArgumentError, "Invalid boolean value: #{s}"
      nil -> raise ArgumentError, "String expected, but got nil"
    end

    @doc false
    defun to_number(s :: nil | String.t()) :: number() do
      s when is_binary(s) ->
        try do
          String.to_integer(s)
        rescue
          ArgumentError -> String.to_float(s)
        end

      nil ->
        raise ArgumentError, "String expected, but got nil"
    end

    @doc false
    defun passthrough_string(s :: nil | String.t()) :: String.t() do
      s when is_binary(s) -> s
      nil -> raise ArgumentError, "String expected, but got nil"
    end

    @doc false
    defun to_datetime(s :: nil | String.t()) :: DateTime.t() do
      {:ok, dt, _tz_offset} = DateTime.from_iso8601(s)
      dt
    end

    @doc false
    defun generate_nilable_preprocessor(original_pp :: t(), original_mod :: v[module()]) :: t() do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      nilable_pp_mod = Module.concat([__MODULE__, Nilable, original_mod])

      nilable_pp_body =
        quote do
          @spec parse(nil | String.t()) :: nil | unquote(original_mod).t()
          def parse(nil), do: nil
          def parse(s), do: unquote(original_pp).(s)
        end

      :ok = ensure_module_defined(nilable_pp_mod, nilable_pp_body, Macro.Env.location(__ENV__))

      &nilable_pp_mod.parse/1
    end

    defunp ensure_module_defined(
             mod :: v[module()],
             body :: term(),
             location :: Macro.Env.t() | keyword()
           ) :: :ok do
      if :code.which(mod) == :non_existing do
        case Agent.start(fn -> nil end, name: mod) do
          {:ok, _pid} ->
            Module.create(mod, body, location)
            :ok

          {:error, _already_started} ->
            :ok
        end
      else
        :ok
      end
    end
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      fields =
        Keyword.fetch!(opts, :fields)
        |> Enum.map(fn
          {field_name, {mod, preprocessor}} = field
          when is_atom(field_name) and is_atom(mod) and is_function(preprocessor, 1) ->
            field

          {field_name, mod} = field when is_atom(field_name) and is_atom(mod) ->
            case Preprocessor.default(mod) do
              {:ok, preprocessor} -> {field_name, {mod, preprocessor}}
              {:error, :no_default_preprocessor} -> field
            end
        end)

      use Antikythera.BaseParamStruct, fields: fields
    end
  end
end
