# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.CoreConfigPoller do
  @moduledoc """
  Periodically polls antikythera's config file and apply changes to the cache (in ETS table).

  Note that core config is loaded in `AntikytheraCore.start/2` and thus
  this `GenServer`'s responsibility is to keep up with the latest changes.
  """

  use GenServer
  alias AntikytheraCore.Config.Core, as: CoreConfig

  @interval 120_000

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    # Assuming that core config is already loaded in `AntikytheraCore.start/2`, we don't have to hurry here.
    {:ok, %{last_changed_at: 0}, @interval}
  end

  @impl true
  def handle_info(:timeout, %{last_changed_at: t} = state1) do
    state2 = %{state1 | last_changed_at: CoreConfig.load(t)}
    {:noreply, state2, @interval}
  end
end
