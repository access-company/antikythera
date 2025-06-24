defmodule Acs.TimeoutRunner do
  use GenServer

  # Client API
  def start_link(context) do
    GenServer.start_link(__MODULE__, context)
  end

  # Server Callbacks
  def init(context) do
    {:ok, context}
  end

  def handle_call({:run, f}, _from, context) do
    safe_context =
      case context do
        :undefined -> %{}
        map -> map
      end

    :logger.set_process_metadata(safe_context)
    {:reply, f.(), context}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end
end
