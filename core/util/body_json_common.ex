# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.BodyJsonCommon do
  @moduledoc """
  Common functions for `Antikythera.BodyJsonStruct`, `Antikythera.BodyJsonMap` and `Antikythera.BodyJsonList`.
  """

  defmodule PreprocessorGenerator do
    @moduledoc false
    @type t :: (nil | AntikytheraCore.BaseParamStruct.json_value_t() -> Croma.Result.t() | term)

    defun generate(mod :: v[module]) :: Croma.Result.t(t()) do
      if :code.get_mode() == :interactive do
        Code.ensure_compiled!(mod)
      end

      cond do
        function_exported?(mod, :from_params, 1) -> {:ok, &mod.from_params/1}
        function_exported?(mod, :new, 1) -> {:ok, &mod.new/1}
        true -> {:error, :no_default_preprocessor}
      end
    end
  end

  @common_default_preprocessor &Function.identity/1

  defun extract_preprocessor_or_default(mod :: {module, PreprocessorGenerator.t()} | module) ::
          {module, PreprocessorGenerator.t()} do
    {mod, preprocessor} = mod_with_preprocessor
    when is_atom(mod) and is_function(preprocessor, 1) ->
      mod_with_preprocessor

    mod when is_atom(mod) ->
      case PreprocessorGenerator.generate(mod) do
        {:ok, preprocessor} -> {mod, preprocessor}
        {:error, :no_default_preprocessor} -> {mod, @common_default_preprocessor}
      end
  end
end
