# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Mix.TaskTest do
  use Croma.TestCase

  alias AntikytheraCore.GearLog.ContextHelper

  describe "set_node_id_to_gear_log_context/1" do
    test "should set node_id to AntikytheraCore.GearLog.ContextHelper" do
      node_id = "My-Node-Id"
      Task.set_node_id_to_gear_log_context(node_id)
      [_, actual_node_id, _] = ContextHelper.get!() |> String.split("_")
      assert actual_node_id == node_id
    end

    test "should cause error if node_id is invalid" do
      node_id = "Invalid_Node_Id"
      catch_error(Task.set_node_id_to_gear_log_context(node_id))
    end
  end
end
