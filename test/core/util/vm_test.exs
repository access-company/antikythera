# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.VmTest do
  use Croma.TestCase
  alias AntikytheraCore.Vm

  test "count_messages_in_all_mailboxes/0" do
    count = Vm.count_messages_in_all_mailboxes()
    assert count >= 0
  end
end
