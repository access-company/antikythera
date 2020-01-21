# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Handler.SystemInfoExporter do
  defmodule AccessToken do
    alias AntikytheraCore.Path, as: CorePath

    @table_name AntikytheraCore.Ets.SystemCache.table_name()
    @key        :system_info_access_token

    defun init() :: :ok do
      token = File.read!(CorePath.system_info_access_token_path())
      :ets.insert(@table_name, {@key, token})
      :ok
    end

    # This is public just to be used in testgear's test
    defun get() :: String.t do
      :ets.lookup_element(@table_name, @key, 2)
    end

    defun with_valid_token(req :: :cowboy_req.req, f :: (() -> :cowboy_req.req)) :: {:ok, :cowboy_req.req, nil} do
      valid_token = get()
      req2 =
        case :cowboy_req.header("authorization", req) do
          ^valid_token -> f.()
          _            -> :cowboy_req.reply(404, req)
        end
      {:ok, req2, nil}
    end
  end

  defmodule Versions do
    def init(req, nil) do
      AccessToken.with_valid_token(req, fn ->
        body = Application.started_applications() |> Enum.sort() |> Enum.map_join("\n", fn {name, _desc, v} -> "#{name} #{v}" end)
        :cowboy_req.reply(200, %{}, body, req)
      end)
    end
  end

  defmodule ErrorCount do
    alias Antikythera.Time
    alias AntikytheraCore.ErrorCountsAccumulator

    def init(req, :total) do
      AccessToken.with_valid_token(req, fn ->
        reply(req, ErrorCountsAccumulator.get_total())
      end)
    end

    def init(req, :per_otp_app) do
      AccessToken.with_valid_token(req, fn ->
        with_otp_app_name(req, fn otp_app_name ->
          reply(req, ErrorCountsAccumulator.get(otp_app_name))
        end)
      end)
    end

    defp with_otp_app_name(%{bindings: %{otp_app_name: s}} = req, f) do
      try do
        String.to_existing_atom(s)
      rescue
        ArgumentError -> nil
      end
      |> case do
        nil          -> :cowboy_req.reply(404, req)
        otp_app_name -> f.(otp_app_name)
      end
    end

    defp reply(req, pairs) do
      body = Enum.map_join(pairs, "\n", fn {t, n} -> Time.to_iso_timestamp(t) <> " #{n}" end)
      :cowboy_req.reply(200, %{}, body, req)
    end
  end
end
