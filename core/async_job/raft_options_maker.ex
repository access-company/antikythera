# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.AsyncJob.RaftOptionsMaker do
  @behaviour RaftFleet.PerMemberOptionsMaker

  defun make(name :: v[atom]) :: [RaftedValue.option] do
    dir = Path.join(AntikytheraCore.Path.raft_persistence_dir_parent(), Atom.to_string(name))
    [persistence_dir: dir]
  end
end
