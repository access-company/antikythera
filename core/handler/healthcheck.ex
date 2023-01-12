# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraCore.Handler.Healthcheck do
  require AntikytheraCore.Logger, as: L

  defmodule Initialized do
    @behaviour :cowboy_handler
    @impl true
    def init(req, nil) do
      {:ok, :cowboy_req.reply(200, %{}, "healthcheck: OK", req), nil}
    end
  end

  defmodule Uninitialized do
    @behaviour :cowboy_handler
    @impl true
    def init(req, nil) do
      L.info("healthcheck: not yet initialized... returning 400")

      # We have to close the connection (i.e. not to keep-alive the connection for the next healthcheck request)
      # so that changes in cowboy routing take effect after initialization finished.
      {:ok,
       :cowboy_req.reply(400, %{"connection" => "close"}, "healthcheck: still initializing", req),
       nil}
    end
  end
end
