# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Vm do
  defun count_messages_in_all_mailboxes() :: non_neg_integer do
    Enum.reduce(Process.list(), 0, fn pid, acc ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> len + acc
        # `pid` doesn't exist anymore
        nil -> acc
      end
    end)
  end
end
