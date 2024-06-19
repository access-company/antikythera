# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.ParamStringStruct do
  @moduledoc """
  Module to define a struct that represents a string parameter.

  This module is designed for parameter validation (see `Antikythera.Plug.ParamsValidator`).

  ## Usage

  To define a struct that represents a string parameter, `use` this module in a module.
  Each field in the struct is defined by the `:fields` option, as shown below.

      defmodule MyQueryParams1 do
        defmodule Limit do
          use Croma.SubtypeOfInt, min: 1, max: 1_000
        end

        use Antikythera.ParamStringStruct,
          fields: [
            item_id: Croma.PosInteger,
            since: DateTime,
            limit: {Limit, &String.to_integer/1}
          ]
      end

  The type of each field must be one of

  - Croma built-in types, such as `Croma.PosInteger`,
  - DateTime-related types: `Date`, `DateTime`, `NaiveDateTime`, and `Time`,
  - nilable types, such as `Croma.TypeGen.Nilable(Croma.PosInteger)`, or
  - module or struct with a preprocessor function, such as `Limit` in the example above.

  When defining a field with a preprocessor, the argument type must be a string or `nil`, and the result must be one of

  - a preprocessed value, or
  - a tuple `{:ok, preprocessed_value}` or `{:error, error_reason}`.

  Note that the parameter is always a string, so you need to convert it to the desired type in the preprocessor if you would like to use user-defined types.

  Now you can validate string parameters using the struct in a controller module.
  The example below shows the validation of query parameters using `MyQueryParams1`.

      use Croma

      defmodule YourGear.Controller.Example do
        use Antikythera.Controller

        plug Antikythera.Plug.ParamsValidator, :validate, query_params: MyQueryParams1

        defun some_action(%Conn{assigns: %{validated: validated}} = conn) :: Conn.t() do
          # You can access the validated query parameters as a `MyQueryParams1` struct via `validated.query_params`.
          # ...
        end
      end

  When a request with the following query parameters is sent to the controller, it is validated by `MyQueryParams1`.
  Each parameter is converted to the specified type by the preprocessor.

      /example?item_id=123&since=2025-01-01T00:00:00Z&limit=100

  You can also validate path parameters(`:path_matches`), headers, and cookies in the same way.

  ### Optional field and default value

  You can define an optional field using `Croma.TypeGen.nilable/1`.
  If an optional field is not included in the request, it is set to `nil`.

  By setting the `:default` option, you can set a default value when the parameter field is not included in the request.

      defmodule MyQueryParams2 do
        use Antikythera.ParamStringStruct,
          fields: [
            q: Croma.TypeGen.nilable(Croma.String),
            date: {Date, [default: ~D[1970-01-01]]}
          ]
      end

      plug Antikythera.Plug.ParamsValidator, :validate, query_params: MyQueryParams2

  In the example above, the request without any query parameters is allowed; `q` is set to `nil`, and `date` is set to `~D[1970-01-01]`.

  ### Naming convention

  By default, the field name in the struct is the same as the parameter key.
  You can specify a different key name scheme using the `:accept_case` option, which is the same as that of `Croma.Struct`.

      defmodule MyQueryParams3 do
        use Antikythera.ParamStringStruct,
          accept_case: :lower_camel,
          fields: [
            item_id: Croma.PosInteger  # The parameter key name "itemId" is also accepted.
          ]
      end

  ## Limitations

  The preprocessor must be specified as a capture form like `&module.function/1`.
  """

  defmodule Preprocessor do
    @moduledoc """
    Preprocessors for string parameters.
    """

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

    @doc """
    Converts a string to a boolean value.
    """
    defun to_boolean(s :: nil | String.t()) :: boolean() do
      "true" -> true
      "false" -> false
      s when is_binary(s) -> raise ArgumentError, "Invalid boolean value: #{s}"
      nil -> raise ArgumentError, "String expected, but got nil"
    end

    @doc """
    Converts a string to a number.
    """
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

    @doc """
    Converts a string to a DateTime struct.
    """
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
      opts_with_default_preprocessor =
        Keyword.put(
          opts,
          :default_preprocessor,
          &Antikythera.ParamStringStruct.Preprocessor.default/1
        )

      use Antikythera.BaseParamStruct, opts_with_default_preprocessor
    end
  end
end
