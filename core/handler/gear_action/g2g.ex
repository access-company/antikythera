# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.GearAction.G2g do
  alias Antikythera.G2gRequest, as: GReq
  alias Antikythera.G2gResponse, as: GRes
  alias Antikythera.{Conn, Context, GearName, GearActionTimeout, PathInfo}
  alias AntikytheraCore.{GearModule, GearTask}
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.Handler.{GearAction, GearError, HelperModules}
  alias AntikytheraCore.GearLog.ContextHelper
  require AntikytheraCore.Logger, as: L

  defun handle(
          %GReq{path: path} = req,
          context :: v[Context.t()],
          receiver_gear :: v[GearName.t()]
        ) :: GRes.t() do
    path_info = GearAction.split_path_to_segments(path)
    helper_modules = GearModule.request_helper_modules(receiver_gear)

    with_route(helper_modules, req, context, receiver_gear, path_info, fn controller,
                                                                          action,
                                                                          path_matches,
                                                                          timeout ->
      with_conn(
        req,
        context,
        receiver_gear,
        {controller, action},
        path_info,
        path_matches,
        fn conn, context ->
          GearAction.with_logging_and_metrics_reporting(conn, context, helper_modules, fn ->
            run_gear_action_within_separate_process(conn, controller, action, timeout)
          end)
        end
      )
    end)
  end

  defunp with_route(
           %HelperModules{router: router},
           %GReq{method: method} = req,
           context :: v[Context.t()],
           receiver_gear :: v[GearName.t()],
           path_info :: v[PathInfo.t()],
           f :: (module, atom, PathInfo.t(), GearActionTimeout.t() -> GRes.t())
         ) :: GRes.t() do
    case router.__gear_route__(method, path_info) do
      # New format (6-tuple) with http_streaming flag
      {controller, action, path_matches, _, _, timeout} ->
        f.(controller, action, path_matches, timeout)

      # Old format (5-tuple) without http_streaming flag - for backward compatibility
      {controller, action, path_matches, _, timeout} ->
        f.(controller, action, path_matches, timeout)

      nil ->
        with_conn(req, context, receiver_gear, nil, path_info, %{}, fn conn, _context ->
          GearError.no_route(conn)
        end)
    end
  end

  defp with_conn(req, context, receiver_gear, entry_point, path_info, path_matches, f) do
    gear_action_context = GearAction.Context.make()

    conn =
      CoreConn.make_from_g2g_req_and_context(
        req,
        context,
        receiver_gear,
        entry_point,
        path_info,
        path_matches
      )

    # Most of the time this line is unnecessary since context ID of g2g action is the same as the caller's
    # (except for test processes where no context ID may be set).
    ContextHelper.set(conn)
    f.(conn, gear_action_context) |> CoreConn.reply_as_g2g_res()
  end

  defunp run_gear_action_within_separate_process(
           conn :: v[Conn.t()],
           controller :: v[module],
           action :: v[atom],
           timeout :: v[GearActionTimeout.t()]
         ) :: Conn.t() do
    # Gear's controller action is executed within a separate process
    # in order to (1) introduce timeout and (2) handle errors in a clean way.
    mfa = {controller, :__action__, [conn, action]}

    GearTask.exec_wait(
      mfa,
      timeout,
      &CoreConn.run_before_send(&1, conn),
      fn
        {:exit, :killed}, stacktrace ->
          %{gear_name: gear_name, context_id: context_id} = conn.context
          L.error("Process killed: gear_name=#{gear_name}, context_id=#{context_id}")
          GearError.error(conn, :killed, stacktrace)

        reason, stacktrace ->
          GearError.error(conn, reason, stacktrace)
      end
    )
  end
end
