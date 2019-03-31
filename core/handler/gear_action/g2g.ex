# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.G2g do
  alias Antikythera.G2gRequest , as: GReq
  alias Antikythera.G2gResponse, as: GRes
  alias Antikythera.{Env, Conn, Context, GearName}
  alias AntikytheraCore.{GearModule, GearTask}
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.Handler.{GearAction, GearError, HelperModules}
  alias AntikytheraCore.GearLog.ContextHelper

  defun handle(%GReq{path: path} = req,
               context       :: v[Context.t],
               receiver_gear :: v[GearName.t]) :: GRes.t do
    path_info = GearAction.split_path_to_segments(path)
    helper_modules = GearModule.request_helper_modules(receiver_gear)
    with_route(helper_modules, req, context, receiver_gear, path_info, fn(controller, action, path_matches) ->
      with_conn(req, context, receiver_gear, {controller, action}, path_info, path_matches, fn conn ->
        GearAction.with_logging_and_metrics_reporting(conn, helper_modules, fn ->
          run_gear_action_within_separate_process(conn, controller, action)
        end)
      end)
    end)
  end

  defp with_route(%HelperModules{router: router}, %GReq{method: method} = req, context, receiver_gear, path_info, f) do
    case router.__gear_route__(method, path_info) do
      {controller, action, path_matches, _} -> f.(controller, action, path_matches)
      nil                                   -> with_conn(req, context, receiver_gear, nil, path_info, %{}, &GearError.no_route/1)
    end
  end

  defp with_conn(req, context, receiver_gear, entry_point, path_info, path_matches, f) do
    conn = CoreConn.make_from_g2g_req_and_context(req, context, receiver_gear, entry_point, path_info, path_matches)
    # Most of the time this line is unnecessary since context ID of g2g action is the same as the caller's
    # (except for test processes where no context ID may be set).
    ContextHelper.set(conn)
    f.(conn) |> CoreConn.reply_as_g2g_res()
  end

  defunp run_gear_action_within_separate_process(conn :: v[Conn.t], controller :: v[module], action :: v[atom]) :: Conn.t do
    # Gear's controller action is executed within a separate process
    # in order to (1) introduce timeout and (2) handle errors in a clean way.
    mfa = {controller, :__action__, [conn, action]}
    GearTask.exec_wait(
      mfa, Env.gear_action_timeout(), &CoreConn.run_before_send(&1, conn),
      fn(reason, stacktrace) -> GearError.error(conn, convert_error_reason(reason), stacktrace) end)
  end

  defp convert_error_reason({:exit, :killed}), do: :killed
  defp convert_error_reason(reason          ), do: reason
end
