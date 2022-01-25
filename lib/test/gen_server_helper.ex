# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.GenServerHelper do
  @moduledoc """
  Helper functions to be used within tests for `GenServer`s.
  """

  def receive_cast_message() do
    receive do
      {:"$gen_cast", message} -> message
    after
      5000 -> raise "No cast message!"
    end
  end

  def send_message_and_wait(server, message) do
    send(server, message)
    # wait until the server finishes processing the message using synchronous round-trip
    _ = :sys.get_state(server)
    :ok
  end
end
