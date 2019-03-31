# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ClusterHostsPoller do
  @moduledoc """
  A `GenServer` that periodically fetches current members of the cluster (all existing hostnames and their lifecycle states)
  from underlying infrastructure.

  In rare occasions fetching hosts information may take longer than 5 seconds;
  we spawn dedicated process in order to keep this GenServer responsive to `call`s from other processes.
  """

  use GenServer
  alias Croma.Result, as: R
  require AntikytheraCore.Logger, as: L

  defmodule Fetcher do
    def run() do
      exit(AntikytheraEal.ClusterConfiguration.running_hosts())
    end
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    state = %{hosts: nil, fetcher: nil}
    set_timer(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, %{hosts: hosts} = state) do
    {:reply, hosts, state}
  end

  @impl true
  def handle_info(:polling_timeout, state) do
    new_state =
      case state do
        %{fetcher: nil}    -> %{state | fetcher: spawn_monitor(Fetcher, :run, [])}
        _fetcher_is_filled -> state # don't spawn more than one temporary process
      end
    set_timer(new_state)
    {:noreply, new_state}
  end
  def handle_info({:DOWN, _monitor_ref, :process, _pid, reason}, state0) do
    state1 = %{state0 | fetcher: nil}
    new_state =
      case reason do
        {:ok, new_hosts} -> %{state1 | hosts: new_hosts}
        {:error, _}      -> state1
        crash_reason     ->
          L.error("One-off fetcher process died unexpectedly! reason: #{inspect(crash_reason)}")
          state1
      end
    {:noreply, new_state}
  end

  defp set_timer(%{hosts: hosts}) do
    interval =
      case hosts do
        nil ->  10_000
        _   -> 180_000
      end
    Process.send_after(self(), :polling_timeout, interval)
  end

  #
  # Public API
  #
  defun current_hosts() :: R.t(%{String.t => boolean}) do
    case GenServer.call(__MODULE__, :get) do
      nil   -> {:error, :not_yet_initialized}
      hosts -> {:ok, hosts}
    end
  end
end
