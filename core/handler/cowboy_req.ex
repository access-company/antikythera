# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.CowboyReq do
  alias Croma.Result, as: R
  alias Antikythera.{Time, GearName, PathInfo, Conn, Context}
  alias Antikythera.Http.{Method, QueryParams, Body}
  alias Antikythera.Request.PathMatches
  alias Antikythera.Context.GearEntryPoint
  alias AntikytheraCore.Conn, as: CoreConn
  alias AntikytheraCore.Handler.{GearError, BodyParser, HelperModules}
  alias AntikytheraCore.GearLog.{ContextHelper, Writer}

  @type result(a) :: {:ok, a} | {:error, :cowboy_req.req()}
  @type routing_info ::
          {GearName.t(), nil | GearEntryPoint.t(), Method.t(), PathInfo.t(), PathMatches.t()}

  defun method(req :: :cowboy_req.req()) :: result(Method.t()) do
    try do
      :cowboy_req.method(req) |> Method.from_string() |> R.pure()
    rescue
      FunctionClauseError -> {:error, :cowboy_req.reply(400, req)}
    end
  end

  defun path_info(%{path: encoded_path_string, path_info: decoded_path_info} :: :cowboy_req.req()) ::
          PathInfo.t() do
    case byte_size(encoded_path_string) do
      0 ->
        []

      len ->
        # Avoid `String.last/1` as it takes O(length_of_string)
        case binary_part(encoded_path_string, len - 1, 1) do
          # append "" due to trailing '/'; See also: `GearAction.split_path_to_segments/1`
          # The number of path components is not expected to be too large.
          # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
          "/" -> decoded_path_info ++ [""]
          _ -> decoded_path_info
        end
    end
  end

  defun query_params(req :: :cowboy_req.req(), routing_info :: routing_info) ::
          result(QueryParams.t()) do
    try do
      :cowboy_req.parse_qs(req)
      |> Map.new(fn
        {k, true} -> {k, ""}
        kv_pair -> kv_pair
      end)
      |> R.pure()
    catch
      :exit, {:request_error, :qs, _message} ->
        {:error, with_conn(req, routing_info, %{}, &GearError.bad_request/1)}
    end
  end

  defun request_body_pair(
          req1 :: :cowboy_req.req(),
          routing_info :: routing_info,
          qparams :: v[QueryParams.t()],
          helper_modules :: v[HelperModules.t()]
        ) :: result({:cowboy_req.req(), {binary, Body.t()}}) do
    case BodyParser.parse(req1) do
      {:ok, req2, raw, parsed} ->
        {:ok, {req2, {raw, parsed}}}

      {:error, :invalid_body, req2} ->
        {:error, with_conn(req2, routing_info, qparams, &GearError.bad_request/1)}

      {:error, :timeout} ->
        {:error,
         with_conn(
           req1,
           routing_info,
           qparams,
           &bad_request_with_body_timeout_logging(&1, helper_modules)
         )}
    end
  end

  defunp bad_request_with_body_timeout_logging(
           %Conn{context: %Context{context_id: context_id}} = conn,
           %HelperModules{logger: logger}
         ) :: Conn.t() do
    Writer.info(
      logger,
      Time.now(),
      context_id,
      "timeout in receiving request body: something is wrong with the client?"
    )

    GearError.bad_request(conn)
  end

  defun with_conn(
          req :: :cowboy_req.req(),
          routing_info :: routing_info,
          qparams :: v[QueryParams.t()],
          body_pair :: {binary, Body.t()} \\ {"", ""},
          f :: (Conn.t() -> Conn.t())
        ) :: :cowboy_req.req() do
    conn = CoreConn.make_from_cowboy_req(req, routing_info, qparams, body_pair)
    ContextHelper.set(conn)
    f.(conn) |> CoreConn.reply_as_cowboy_res(req)
  end
end
