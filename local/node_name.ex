# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.NodeName do
  defun get() :: atom do
    # The hostname part must contain "." as we are using "-name" instead of "-sname"
    # when starting distributed Erlang nodes (see also `rel/env.sh.eex`).
    # On macOS, the output of `hostname -f` might have no ".",
    # which prohibits the release script from sending RPC commands to a running release.
    # We avoid the trouble by appending ".local" to the node name.
    h0 = AntikytheraCore.Cmd.hostname()
    h1 = if String.contains?(h0, "."), do: h0, else: h0 <> ".local"
    # `String.to_atom` is safe because this module is under `AntikytheraLocal`
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom("antikythera@" <> h1)
  end
end
