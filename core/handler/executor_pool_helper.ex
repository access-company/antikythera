# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.ExecutorPoolHelper do
  alias Croma.Result, as: R
  alias Antikythera.{GearName, Conn, Context}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias Antikythera.ExecutorPool.BadIdReason
  alias AntikytheraCore.MetricsUploader
  alias AntikytheraCore.Handler.{GearError, HelperModules}
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.ExecutorPool.Id, as: CoreEPoolId
  alias AntikytheraCore.ExecutorPool.WebsocketConnectionsCounter, as: WsCounter
  alias AntikytheraCore.Ets.GearActionRunnerPools
  alias AntikytheraCore.GearLog.Writer

  defun with_executor(conn           :: v[Conn.t],
                      gear_name      :: v[GearName.t],
                      helper_modules :: v[HelperModules.t],
                      f              :: ((pid, Conn.t) -> Conn.t)) :: Conn.t do
    case find_executor_pool(conn, gear_name, helper_modules) do
      {:ok, epool_id}  -> run_within_executor_pool(conn, helper_modules, epool_id, f)
      {:error, reason} -> GearError.bad_executor_pool_id(conn, reason)
    end
  end

  defunp find_executor_pool(conn      :: v[Conn.t],
                            gear_name :: v[GearName.t],
                            %HelperModules{top: top}) :: R.t(EPoolId.t, BadIdReason.t) do
    top.executor_pool_for_web_request(conn) |> CoreEPoolId.validate_association(gear_name)
  end

  defunp run_within_executor_pool(%Conn{context: context} = conn1,
                                  helper_modules :: v[HelperModules.t],
                                  epool_id       :: v[EPoolId.t],
                                  f              :: ((pid, Conn.t) -> Conn.t)) :: Conn.t do
    conn2 = %Conn{conn1 | context: %Context{context | executor_pool_id: epool_id}}
    try do
      PoolSup.Multi.transaction(GearActionRunnerPools.table_name(), epool_id, fn pid ->
        f.(pid, conn2)
      end)
    catch
      :exit, {:timeout, _} ->
        report_failure_in_checkout(helper_modules, epool_id)
        GearError.error(conn2, :timeout_in_epool_checkout, [])
    end
  end

  defp report_failure_in_checkout(%HelperModules{metrics_uploader: metrics_uploader}, epool_id) do
    data = {"web_timeout_in_epool_checkout", :sum, 1}
    MetricsUploader.submit(metrics_uploader, [data], epool_id)
  end

  defun increment_ws_count(%Conn{context: %Context{start_time: start_time, context_id: context_id, executor_pool_id: epool_id}} = conn,
                           %{pid: ws_pid} = req :: :cowboy_req.req,
                           %HelperModules{logger: logger},
                           f                    :: (() -> a)) :: :cowboy_req.req | a when a: any do
    case WsCounter.increment(epool_id, ws_pid) do
      :ok                             -> f.()
      {:error, :too_many_connections} ->
        Writer.error(logger, start_time, context_id, "Cannot establish new websocket connection: too many connections in executor pool #{inspect(epool_id)}")
        GearError.ws_too_many_connections(conn) |> CoreConn.reply_as_cowboy_res(req)
    end
  end
end
