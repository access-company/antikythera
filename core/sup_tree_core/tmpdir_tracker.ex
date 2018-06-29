# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.TmpdirTracker do
  @moduledoc """
  A GenServer that keeps track of user pids of temporary directories.

  Temporary directories are created via calls to `Antikythera.Tmpdir.make/2`.
  This GenServer communicates with the caller process and monitors its death to make sure that the directories are eventually deleted.

  Currently we do not impose upper limit on volume and I/O usage
  since number of concurrently running processes is capped by executor pools.
  As a result we also skip checking association of "executor pool" and "calling code (gear)".
  """

  use GenServer
  alias Croma.Result, as: R
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Path, as: CorePath

  defmodule State do
    defmodule Map do
      use Croma.SubtypeOfMap, key_module: Croma.Pid, value_module: Croma.String
    end

    use Croma.Struct, recursive_new?: true, fields: [
      gear_tmp_dir: Croma.String,
      map:          Map,
    ]
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    {:ok, %State{gear_tmp_dir: CorePath.gear_tmp_dir(), map: %{}}}
  end

  @impl true
  def handle_call({:request, pid, epool_id}, _from, %State{map: map} = state) do
    if Map.has_key?(map, pid) do
      {:reply, {:error, :already_have_one}, state}
    else
      tmpdir = tmpdir_path(state, pid, epool_id)
      new_state = %State{state | map: Map.put(map, pid, tmpdir)}
      Process.monitor(pid)
      {:reply, {:ok, tmpdir}, new_state}
    end
  end

  defp tmpdir_path(%State{gear_tmp_dir: gear_tmp_dir}, pid, epool_id) do
    Path.join([gear_tmp_dir, EPoolId.to_string(epool_id), Integer.to_string(:erlang.phash2(pid))])
  end

  @impl true
  def handle_cast({:finished, pid}, state) do
    {:noreply, remove_dir(state, pid)}
  end

  @impl true
  def handle_info({:DOWN, _mon, :process, pid, _reason}, state) do
    {:noreply, remove_dir(state, pid)}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defunp remove_dir(%State{map: map1} = state, pid :: v[pid]) :: State.t do
    case Map.pop(map1, pid) do
      {nil   , _   } -> state
      {tmpdir, map2} ->
        File.rm_rf!(tmpdir)
        %State{state | map: map2}
    end
  end

  #
  # Public API
  #
  defun request(epool_id :: v[EPoolId.t]) :: R.t(Path.t) do
    GenServer.call(__MODULE__, {:request, self(), epool_id})
    |> R.map(fn tmpdir ->
      File.mkdir_p!(tmpdir)
      tmpdir
    end)
  end

  defun finished() :: :ok do
    GenServer.cast(__MODULE__, {:finished, self()})
  end
end
