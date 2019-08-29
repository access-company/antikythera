# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ReductionLogWriter do
  @moduledoc """
  A `GenServer` that logs processes with increasing reduction.
  """

  use GenServer
  alias AntikytheraCore.GearLog.FileHandle
  alias Antikythera.{Time, ContextId}

  @interval        1000
  @dump_size       20
  @rotate_interval 7_200_000

  defmodule State do
    use Croma.Struct, recursive_new?: true, fields: [
      file_handle: Croma.Tuple, # FileHandle.t
      empty?:      Croma.Boolean,
      timer:       Croma.Reference,
      reduction:   Croma.Map,
    ]
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  @impl true
  def init([]) do
    handle = FileHandle.open(AntikytheraCore.Path.core_log_file_path("reduction"), write_to_terminal: false)
    timer = arrange_next_rotation(nil)
    reduction = get_reduction_map()
    {:ok, %State{file_handle: handle, empty?: true, timer: timer, reduction: reduction}, @interval}
  end

  @impl true
  def handle_info(:timeout, %State{file_handle: handle, timer: timer, reduction: prev_reduction} = state) do
    {message, reduction} = build_log(prev_reduction)
    msg = {Time.now(), :info, ContextId.system_context(), message}
    case FileHandle.write(handle, msg) do
      {:kept_open, new_handle} -> {:noreply, %State{state | file_handle: new_handle, empty?: false, reduction: reduction}, @interval}
      {:rotated  , new_handle} ->
        # Log file is just rotated as its size has exceeded the upper limit.
        # Note that the current message is written to the newly-opened log file and thus it's not empty.
        new_timer = arrange_next_rotation(timer)
        {:noreply, %State{state | file_handle: new_handle, empty?: false, timer: new_timer, reduction: reduction}, @interval}
    end
  end
  def handle_info(:rotate, state) do
    {:noreply, rotate(state), @interval}
  end

  defp rotate(%State{file_handle: handle, empty?: empty?, timer: timer} = state0) do
    new_timer = arrange_next_rotation(timer)
    state1 = %State{state0 | timer: new_timer}
    if empty? do
      state1
    else
      %State{state1 | file_handle: FileHandle.rotate(handle), empty?: true}
    end
  end

  @impl true
  def terminate(_reason, %State{file_handle: handle}) do
    FileHandle.close(handle)
  end

  defp arrange_next_rotation(timer) do
    if timer do
      Process.cancel_timer(timer)
    end
    Process.send_after(self(), :rotate, @rotate_interval)
  end

  defp build_log(prev_reduction) do
    log_time = Antikythera.Time.to_iso_timestamp(Antikythera.Time.now())
    current_reduction = get_reduction_map()
    msg =
      make_diff(current_reduction, prev_reduction)
      |> Enum.take(@dump_size)
      |> Enum.reduce(log_time, fn(diff, acc) ->
        acc <> "\n" <> inspect(diff)
      end)
    {msg, current_reduction}
  end

  defp get_reduction_map() do
    # If the second argument (number of processes to be acquired) is too small,
    # the difference in reduction cannot be calculated correctly. But if it is
    # too large, the load is high. So sufficiently large value is specified.
    # The number of processes in a normal production environment is less than 5,000.
    :recon.proc_count(:reductions, 20_000) |> Map.new(fn {pid, count, other} -> {pid, {count, other}} end)
  end

  defp make_diff(current, prev) do
    current
    |> Enum.map(fn {pid, {count, other}} ->
      prev_cnt = Map.get(prev, pid, {0, nil}) |> elem(0)
      {pid, {count - prev_cnt, other}}
    end)
    |> Enum.sort_by(fn {_pid, {c, _}} -> c end, &>=/2)
  end
end
