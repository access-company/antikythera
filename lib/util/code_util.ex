# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.CodeUtil do
  @moduledoc """
  Utilities involving `Code` module, used for metaprogramming.
  """

  @doc """
  Fetches function document from already existing module.

  Used when annotating a function with the same doc attribute as that of another function.
  """
  defun doc_by_mfa!(module :: v[module], function :: v[atom], arity :: v[non_neg_integer]) :: String.t do
    case Code.get_docs(module, :docs) |> List.keyfind({function, arity}, 0) do
      {{^function, ^arity}, _line, _def, _args, doc} when is_binary(doc) -> doc
      _otherwise                                                         -> raise(ArgumentError, "Not found: #{inspect(module)}.#{function}/#{arity}")
    end
  end
end
