# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.Cmd do
  defun exec_and_output_log!(cmd :: v[String.t], cmd_args :: [String.t], opts :: Keyword.t \\ []) :: :ok do
    case System.cmd(cmd, cmd_args, opts) do
      {output, 0} -> IO.puts(output)
      {output, _} -> raise "Nonzero exit code returned by `#{cmd} #{inspect(cmd_args)}`: output=#{output}"
    end
  end
end
