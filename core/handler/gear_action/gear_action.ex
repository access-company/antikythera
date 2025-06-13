# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction do
  alias Antikythera.{Conn, Context, Request, Time, GearName, PathInfo}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.Handler.{GearAction, HelperModules}
  alias AntikytheraCore.{MetricsUploader, GearLog.Writer, EndTime}

  @http_headers_to_log Application.compile_env!(:antikythera, :http_headers_to_log)

  defun split_path_to_segments(path :: v[String.t()]) :: PathInfo.t() do
    String.split(path, "/")
    # neglect leading '/' but DO include the last "" due to trailing '/'
    |> tl()
    |> Enum.map(&URI.decode_www_form/1)
  end

  defun with_logging_and_metrics_reporting(
          %Conn{request: %Request{sender: {_web_or_gear, sender_info}}} = conn,
          context :: v[GearAction.Context.t()],
          %HelperModules{metrics_uploader: metrics_uploader} = helper_modules,
          f :: (-> Conn.t())
        ) :: Conn.t() do
    {conn2, t_end, processing_time} = with_logging(conn, context, helper_modules, sender_info, f)
    %Conn{status: status, context: %Context{executor_pool_id: epool_id0}} = conn2
    epool_id1 = epool_id0 || EPoolId.nopool()

    MetricsUploader.submit_with_time(
      metrics_uploader,
      t_end,
      make_metrics_data(status, processing_time, sender_info),
      epool_id1
    )

    conn2
  end

  defp make_metrics_data(status, processing_time, sender_info) do
    prefix = if is_atom(sender_info), do: "g2g_", else: "web_"

    [
      # If status is not given at this point it's due to a bug in the gear's action.
      {prefix <> "request_count", :request_count, status || 500},
      {prefix <> "response_time_ms", :time_distribution, processing_time}
    ]
  end

  defunp with_logging(
           conn :: v[Conn.t()],
           context :: v[GearAction.Context.t()],
           %HelperModules{logger: logger},
           sender_info :: v[String.t() | GearName.t()],
           f :: (-> Conn.t())
         ) :: {Conn.t(), Time.t(), non_neg_integer} do
    %GearAction.Context{
      start_monotonic_time: start_monotonic_time,
      start_time_for_log: start_time_for_log
    } = context

    %Conn{context: %Context{context_id: context_id}} = conn
    log_message_base = "#{CoreConn.request_info(conn)} from=#{sender_info}"

    headers =
      @http_headers_to_log
      |> Enum.map_join(fn key -> " #{key}=#{Conn.get_req_header(conn, key) || "(none)"}" end)

    Writer.info(logger, start_time_for_log, context_id, "#{log_message_base} START#{headers}")
    %Conn{status: status} = conn2 = f.()
    end_time = EndTime.now()
    processing_time = end_time.monotonic - start_monotonic_time

    Writer.info(
      logger,
      end_time.gear_log,
      context_id,
      "#{log_message_base} END status=#{status} time=#{processing_time}ms"
    )

    {conn2, end_time.antikythera_time, processing_time}
  end
end
