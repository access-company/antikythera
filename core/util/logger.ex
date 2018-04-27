# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Logger do
  defmacro info(message) do
    if Antikythera.Env.compiling_for_release?() do
      emit_log(__CALLER__.module, message, :info)
    else
      quote bind_quoted: [message: message] do
        _ = message # suppress unused variable warnings
        :ok
      end
    end
  end

  defmacro error(message) do
    emit_log(__CALLER__.module, message, :error)
  end

  defp emit_log(module, message, level) do
    quote bind_quoted: [module: module, message: message, level: level] do
      :ok = Logger.bare_log(level, message, [module: module])
    end
  end
end
