# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma
alias Croma.Result, as: R

defmodule AntikytheraCore.Handler.BodyParser do
  alias Antikythera.Http.{RawBody, Body}
  require AntikytheraCore.Logger, as: L

  @typep ok_tuple :: {:ok, :cowboy_req.req(), RawBody.t(), Body.t()}
  @typep invalid_tuple :: {:error, :invalid_body, :cowboy_req.req()}
  @typep timeout_tuple :: {:error, :timeout}

  defun parse(req :: :cowboy_req.req()) :: ok_tuple | invalid_tuple | timeout_tuple do
    with {:ok, raw, req2} <- get_body(req),
         {:ok, parsed} <- parse_body(req2, raw),
         do: {:ok, req2, raw, parsed}
  end

  defunp get_body(req :: :cowboy_req.req()) ::
           {:ok, RawBody.t(), :cowboy_req.req()} | invalid_tuple | timeout_tuple do
    try do
      # Read up to 8MB by one invocation of :cowboy_req.read_body/2; reject request with larger body
      # default timeout (period + 1_000) is too long as period defaults to 15_000
      period = 5_000

      case :cowboy_req.read_body(req, %{period: period}) do
        {:more, _partial_body, req2} -> {:error, :invalid_body, req2}
        ok_tuple -> ok_tuple
      end
    catch
      # disconnected on the client side
      :exit, :timeout ->
        %{host: host, method: method, path: path} = req
        L.info("timeout in reading request body: #{host} #{method} #{path}")
        {:error, :timeout}
    end
  end

  defunp parse_body(req2 :: :cowboy_req.req(), raw :: v[RawBody.t()]) ::
           {:ok, Body.t()} | invalid_tuple do
    case :cowboy_req.header("content-type", req2) do
      "application/json" <> _charset -> parse_json(raw)
      "application/x-ldjson" <> _charset -> parse_json_stream(raw)
      "application/x-ndjson" <> _charset -> parse_json_stream(raw)
      "application/x-www-form-urlencoded" <> _charset -> parse_form_urlencoded(raw)
      _ -> {:ok, raw}
    end
    |> case do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :invalid_body, req2}
    end
  end

  defunp parse_json(raw :: v[RawBody.t()]) :: R.t(Body.t()) do
    # Try `decode_json_stream` to accept applications using line-delimited JSON without proper content-type (e.g. Kibana4.x)
    R.or_else(decode_json(raw), parse_json_stream(raw))
  end

  defunp parse_json_stream(raw :: v[RawBody.t()]) :: R.t([map]) do
    parsed_jsons =
      raw
      |> String.split("\n", trim: true)
      |> Enum.reduce({"", []}, fn new_line, {acc_string, acc_parsed_jsons} ->
        joined = acc_string <> new_line

        case decode_json(joined) do
          {:ok, parsed_json} -> {"", [parsed_json | acc_parsed_jsons]}
          # restoring delimiter
          _ -> {joined <> "\n", acc_parsed_jsons}
        end
      end)

    case parsed_jsons do
      {"", []} -> {:error, :empty_body}
      {"", parsed_jsons} -> {:ok, Enum.reverse(parsed_jsons)}
      _ -> {:error, :invalid_body}
    end
  end

  defunp decode_json(raw :: v[RawBody.t()]) :: R.t(Body.t()) do
    # This function is introduced to work-around issue in Poison v2.2.0:
    # number in JSON that doesn't fit into IEEE 754 double causes an `ArgumentError` (instead of returning `{:error, _}`).
    # After we migrate to a fixed version this can be removed.
    try do
      Poison.decode(raw)
    rescue
      ArgumentError -> {:error, :too_large_number}
    end
  end

  defunp parse_form_urlencoded(raw :: v[RawBody.t()]) :: R.t(Body.t()) do
    # `:cow_qs.parse_qs/1` throws on malformed binary
    R.try(fn ->
      :cow_qs.parse_qs(raw) |> Map.new()
    end)
  end
end
