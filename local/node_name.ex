# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.NodeName do
  defun get() :: atom do
    # In OSX `hostname -f` might have no ".", which prohibits relx's script from
    # sending RPC commands to running release, as we are using "-name" instead of "-sname" in vm.args.
    # We avoid the trouble by appending ".local" to the node name.
    h0 = AntikytheraCore.Cmd.hostname()
    h1 = if String.contains?(h0, "."), do: h0, else: h0 <> ".local"
    # `String.to_atom` is safe because this module is under `AntikytheraLocal`
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom("antikythera@" <> h1)
  end
end
