# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.NodeName do
  defun get() :: atom do
    # In OSX `hostname -f` might have no ".", which prohibits relx's script from
    # sending RPC commands to running release, as we are using "-name" instead of "-sname" in vm.args.
    # We avoid the trouble by appending ".local" to the node name.
    h0 = AntikytheraCore.Cmd.hostname()
    h1 = if String.contains?(h0, "."), do: h0, else: h0 <> ".local"
    String.to_atom("antikythera@" <> h1)
  end
end
