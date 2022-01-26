# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Handler.HelperModules do
  use Croma.Struct,
    recursive_new?: true,
    fields: [
      top: Croma.Atom,
      router: Croma.Atom,
      logger: Croma.Atom,
      metrics_uploader: Croma.Atom
    ]
end
