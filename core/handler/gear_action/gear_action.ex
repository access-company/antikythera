# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction do
  alias Antikythera.{Conn, Context, Request, Time, GearName, PathInfo}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.{MetricsUploader, Handler.HelperModules, GearLog.Writer}

  defun split_path_to_segments(path :: v[String.t]) :: PathInfo.t do
    String.split(path, "/")
    |> tl() # neglect leading '/' but DO include the last "" due to trailing '/'
    |> Enum.map(&URI.decode_www_form/1)
  end

  defun with_logging_and_metrics_reporting(%Conn{request: %Request{sender: {_web_or_gear, sender_info}}} = conn,
                                           %HelperModules{metrics_uploader: metrics_uploader} = helper_modules,
                                           f :: (() -> Conn.t)) :: Conn.t do
    {conn2, t_end, processing_time} = with_logging(conn, helper_modules, sender_info, f)
    %Conn{status: status, context: %Context{executor_pool_id: epool_id0}} = conn2
    epool_id1 = epool_id0 || EPoolId.nopool()
    MetricsUploader.submit_with_time(metrics_uploader, t_end, make_metrics_data(status, processing_time, sender_info), epool_id1)
    conn2
  end

  defp make_metrics_data(status, processing_time, sender_info) do
    prefix = if is_atom(sender_info), do: "g2g_", else: "web_"
    request_count = {prefix <> "request_count", :request_count, status}
    response_time = {prefix <> "response_time_ms", :time_distribution, processing_time}
    [request_count, response_time]
  end

  defunp with_logging(conn        :: v[Conn.t],
                      %HelperModules{logger: logger},
                      sender_info :: v[String.t | GearName.t],
                      f           :: (() -> Conn.t)) :: {Conn.t, Time.t, non_neg_integer} do
    %Conn{context: %Context{start_time: t_start, context_id: context_id}} = conn
    log_message_base = "#{CoreConn.request_info(conn)} from=#{sender_info}"
    encoding = Conn.get_req_header(conn, "accept-encoding") || "(none)" # To see whether client accepts gzip/deflate compression or not
    Writer.info(logger, t_start, context_id, "#{log_message_base} START encoding=#{encoding}")
    %Conn{status: status} = conn2 = f.()
    t_end = Time.now()
    processing_time = Time.diff_milliseconds(t_end, t_start)
    Writer.info(logger, t_end, context_id, "#{log_message_base} END status=#{status} time=#{processing_time}ms")
    {conn2, t_end, processing_time}
  end
end
