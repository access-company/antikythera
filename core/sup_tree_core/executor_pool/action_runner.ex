# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ExecutorPool.ActionRunner do
  @moduledoc """
  A `GenServer` (whose lifecycle is managed by `PoolSup.Multi`) that executes gears' controller actions.
  """

  use GenServer
  alias Antikythera.{Env, Conn}
  alias Antikythera.Context.GearEntryPoint
  alias AntikytheraCore.GearProcess
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.Handler.GearError
  require AntikytheraCore.Logger, as: L

  def start_link(arg) do
    # `GenServer.start_link/3` would be warned by dialyzer as `:max_heap_size` is currently not included in its typespec
    :gen_server.start_link(__MODULE__, arg, [spawn_opt: [max_heap_size: GearProcess.max_heap_size()]])
  end

  @impl true
  def init(arg) do
    {:ok, arg}
  end

  @impl true
  def handle_call({:run, conn, entry_point}, _from, state) do
    {:reply, run_action(conn, entry_point), state}
  end

  defp run_action(conn, {controller, action}) do
    try do
      {:ok, controller.__action__(conn, action)}
    catch
      :error, e      -> {:error, {:error, e     }, System.stacktrace()}
      :throw, value  -> {:error, {:throw, value }, System.stacktrace()}
      :exit , reason -> {:error, {:exit , reason}, System.stacktrace()}
    after
      Antikythera.GearApplication.ConfigGetter.cleanup_configs_in_process_dictionary()
    end
  end

  @impl true
  def handle_info(msg, state) do
    # On rare occasions this GenServer receives a message by :ssl module due to timeout in hackney, and it shouldn't trigger alert.
    L.info("received an unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  #
  # Public API
  #
  defun run(pid :: v[pid], conn :: v[Conn.t], entry_point :: v[GearEntryPoint.t]) :: Conn.t do
    false = Process.flag(:trap_exit, true)
    try do
      case GenServer.call(pid, {:run, conn, entry_point}, Env.gear_action_timeout()) do
        {:ok, conn2}                 -> CoreConn.run_before_send(conn2, conn)
        {:error, reason, stacktrace} -> GearError.error(conn, reason, stacktrace)
      end
    catch
      :exit, {:timeout, _} ->
        # We must kill `pid` which is still-running; PoolSup will spawn a new process if necessary.
        # Note that it's within `PoolSup.Multi.transaction/4` and thus we need to manually unlink `pid`.
        Process.unlink(pid)
        Process.exit(pid, :kill)
        GearError.error(conn, :timeout, [])
      :exit, {:killed, {GenServer, :call, [^pid | _]}} ->
        # `pid` has been brutally killed by someone, probably due to heap limit violation.
        # We additionally consume the EXIT message in mailbox, just to be sure that it won't result in memory leak.
        receive do
          {:EXIT, ^pid, :killed} -> :ok
        after
          0 -> :ok
        end
        GearError.error(conn, :timeout, [])
    after
      Process.flag(:trap_exit, false)
    end
  end
end
