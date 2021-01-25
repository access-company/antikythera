# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Cmd do
  defun hostname() :: String.t() do
    {host, 0} = System.cmd("hostname", ["-f"])
    String.trim_trailing(host)
  end
end
