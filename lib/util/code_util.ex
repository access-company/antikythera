# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.CodeUtil do
  @moduledoc """
  Utilities involving `Code` module, used for metaprogramming.
  """

  @doc """
  Fetches function document from already existing module.

  Used when annotating a function with the same doc attribute as that of another function.
  """
  defun doc_by_mfa!(module :: v[module], function :: v[atom], arity :: v[non_neg_integer]) ::
          String.t() do
    {:docs_v1, _anno, _beam_lang, _format, _moduledoc, _meta, docs} = Code.fetch_docs(module)

    case List.keyfind(docs, {:function, function, arity}, 0) do
      {_tuple3, _anno, _signature, %{"en" => doc}, _meta} -> doc
      _otherwise -> raise(ArgumentError, "Not found: #{inspect(module)}.#{function}/#{arity}")
    end
  end
end
