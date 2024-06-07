# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.BodyJsonStruct do
  @moduledoc """
  *TBD*
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
