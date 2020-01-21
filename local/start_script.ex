# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraLocal.StartScript do
  alias Antikythera.Env
  alias AntikytheraLocal.{Cmd, NodeName}

  defun run(command :: v[String.t], release_dir :: Path.t) :: :ok do
    env = [
      {"ANTIKYTHERA_RUNTIME_ENV", "local"                       },
      {"MIX_ENV"                , "prod"                        },
      {"RELX_REPLACE_OS_VARS"   , "true"                        },
      {"NODENAME"               , Atom.to_string(NodeName.get())},
      {"COOKIE"                 , "local"                       },
    ]
    Cmd.exec_and_output_log!("sh", ["bin/#{Env.antikythera_instance_name()}", command], env: env, cd: release_dir)
  end
end
