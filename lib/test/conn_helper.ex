# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.ConnHelper do
  @moduledoc """
  Helper functions to construct `Antikythera.Conn` object, to be used within tests.

  Typical controller tests are executed as follows:

  1. Make a `Antikythera.Conn` object.
  2. Pass the object to the target controller action.
  3. Inspect the returned `Antikythera.Conn` object.

  You can use `make_conn/1` for the step-1 of the above procedure.
  In controller tests this module is auto-imported by `use Antikythera.Test.ControllerTestCase`.
  """

  alias Antikythera.{Time, Conn, Request, Context}

  def make_conn(opts0 \\ %{}) do
    opts = if is_map(opts0), do: opts0, else: Map.new(opts0)

    Conn.new!(
      request: make_request(opts),
      context: make_context(opts),
      status: Map.get(opts, :status, 200),
      resp_headers: Map.get(opts, :resp_headers, %{}),
      resp_cookies: Map.get(opts, :resp_cookies, %{}),
      resp_body: Map.get(opts, :resp_body, ""),
      assigns: Map.get(opts, :assigns, %{})
    )
  end

  defp make_request(opts) do
    default_headers = %{
      "accept" => "*/*",
      "host" => "localhost:#{Antikythera.Env.port_to_listen()}"
    }

    Request.new!(
      method: Map.get(opts, :method, :get),
      path_info: Map.get(opts, :path_info, ["hello", "json_api"]),
      path_matches: Map.get(opts, :path_matches, %{}),
      query_params: Map.get(opts, :query_params, %{}),
      headers: Map.get(opts, :headers, default_headers),
      cookies: Map.get(opts, :cookies, %{}),
      raw_body: Map.get(opts, :raw_body, ""),
      body: Map.get(opts, :body, ""),
      sender: Map.get(opts, :sender, {:web, "127.0.0.1"})
    )
  end

  defp make_context(opts) do
    now = Time.now()

    Context.new!(
      start_time: Map.get(opts, :start_time, now),
      context_id: Map.get(opts, :context_id, AntikytheraCore.Context.make_context_id(now)),
      gear_name: Map.get(opts, :gear_name, :testgear),
      executor_pool_id: Map.get(opts, :executor_pool_id, {:gear, :testgear}),
      gear_entry_point: Map.get(opts, :gear_entry_point, {Testgear.Controller.Hello, :hello})
    )
  end
end
