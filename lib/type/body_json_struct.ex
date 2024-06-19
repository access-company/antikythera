# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonStruct do
  @moduledoc """
  Module to define a struct that represents the JSON body of a request.

  This module is designed for request body validation (see `Antikythera.Plug.ParamsValidator`).

  ## Usage

  To define a struct that represents the JSON body of a request, `use` this module in a module.
  Each field in the struct is defined by the `:fields` option, as shown below.

      defmodule MyBody1 do
        use Antikythera.BodyJsonStruct,
          fields: [
            item_id: Croma.PosInteger,
            tags: Croma.TypeGen.list_of(Croma.String),
            expires_at: {DateTime, &Antikythera.ParamStringStruct.Preprocessor.to_datetime/1}
          ]
      end

  The type of each field must be one of

  - modules having `valid?/1` function, such as `Croma.PosInteger`, `Croma.TypeGen.list_of(Croma.String)`, modules defined by `Antikythera.BodyJsonMap` or `Antikythera.BodyJsonList`, or
  - structs with a preprocessor function, such as `DateTime` in the example above.

  When defining a field with a preprocessor, the argument type must be a JSON value type or `nil`,
  and the result must be one of

  - a preprocessed value, or
  - a tuple `{:ok, preprocessed_value}` or `{:error, error_reason}`.

  Now you can validate a JSON request body using the struct in a controller module.

      use Croma

      defmodule YourGear.Controller.Example do
        use Antikythera.Controller

        plug Antikythera.Plug.ParamsValidator, :validate, body: MyBody1

        defun some_action(%Conn{assigns: %{validated: validated}} = conn) :: Conn.t() do
          # You can access the validated JSON body as a `MyBody1` struct via `validated.body`.
          # ...
        end
      end

  When a request with the following JSON body is sent to the controller, it is validated by `MyBody1`.
  The `expires_at` field is converted to a `DateTime` struct by the `Antikythera.ParamStringStruct.Preprocessor.to_datetime/1` preprocessor.

      {
        "item_id": 123,
        "tags": ["tag1", "tag2"],
        "expires_at": "2025-01-01T00:00:00Z"
      }

  ### Struct nesting

  You can define a nested struct using another struct as a field type without a preprocessor.

      defmodule MyBody2 do
        defmodule GeoLocation do
          use Antikythera.BodyJsonStruct,
            fields: [
              latitude: Croma.Float,
              longitude: Croma.Float
            ]
        end

        use Antikythera.BodyJsonStruct,
          fields: [
            item_id: Croma.PosInteger,
            location: GeoLocation
          ]
      end

  In the example above, `MyBody2` allows the following JSON body and the `location` field is converted to a `GeoLocation` struct.

      {
        "item_id": 123,
        "location": {
          "latitude": 35.699793,
          "longitude": 139.774113
        }
      }

  ### Optional field and default value

  You can define an optional field using `Croma.TypeGen.nilable/1`.
  If an optional field is missing in the JSON body, it is set to `nil`.

  By setting the `:default` option, you can set a default value when the field is missing in the JSON body.

      defmodule MyBody3 do
        use Antikythera.BodyJsonStruct,
          fields: [
            timezone: {Croma.String, [default: "UTC"]},
            date: {Date, &Date.from_iso8601/1, [default: ~D[1970-01-01]]}
          ]
      end

  In the example above, `MyBody3` allows the empty JSON object body `{}`, with each field set to the default value.

  ### Naming convention

  By default, the field name in the struct and the key name in the JSON body are the same.
  You can specify a different key name scheme using the `:accept_case` option, which is the same as that of `Croma.Struct`.

      defmodule MyBody4 do
        use Antikythera.BodyJsonStruct,
          accept_case: :lower_camel,
          fields: [
            long_name_field: Croma.String  # The key name "longNameField" is also accepted in the JSON body.
          ]
      end

  ## Limitations

  The preprocessor must be specified as a capture form like `&module.function/1`.
  """

  alias Antikythera.BaseParamStruct

  defmodule Preprocessor do
    @moduledoc false

    @type t :: (nil | BaseParamStruct.json_value_t() -> Croma.Result.t() | term())

    @doc false
    defun default(mod :: v[module()]) :: Croma.Result.t(t()) do
      if :code.get_mode() == :interactive do
        true = Code.ensure_loaded?(mod)
      end

      cond do
        function_exported?(mod, :from_params, 1) -> {:ok, &mod.from_params/1}
        function_exported?(mod, :new, 1) -> {:ok, &mod.new/1}
        true -> {:error, :no_default_preprocessor}
      end
    end
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts_with_default_preprocessor =
        Keyword.put(
          opts,
          :default_preprocessor,
          &Antikythera.BodyJsonStruct.Preprocessor.default/1
        )

      use Antikythera.BaseParamStruct, opts_with_default_preprocessor
    end
  end
end
