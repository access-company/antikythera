# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.GearLog.ContextHelperTest do
  use Croma.TestCase

  alias Antikythera.{Conn, Context}

  describe "set/1" do
    test "should set ContextId from Conn.t" do
      conn = Antikythera.Test.ConnHelper.make_conn()
      ContextHelper.set(conn)
      assert ContextHelper.get!() == conn.context.context_id
    end

    test "should set ContextId from Context.t" do
      %Conn{context: context} = Antikythera.Test.ConnHelper.make_conn()

      ContextHelper.set(context)
      assert ContextHelper.get!() == context.context_id
    end

    test "should set ContextId from ContextId" do
      %Conn{context: %Context{context_id: context_id}} = Antikythera.Test.ConnHelper.make_conn()

      ContextHelper.set(context_id)
      assert ContextHelper.get!() == context_id
    end
  end
end
