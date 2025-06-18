# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.GearApplication.HttpcWithLoggingTest do
  use Croma.TestCase
  alias Antikythera.Httpc
  alias Antikythera.Httpc.Response

  # Test data
  @test_url "https://api.example.com/test"
  @test_body "test body"
  @test_headers %{"content-type" => "application/json", "authorization" => "Bearer token"}
  @test_options [timeout: 5000]
  @success_response %Response{
    status: 200,
    headers: %{"content-type" => "application/json"},
    body: ~s({"success": true}),
    cookies: %{}
  }
  @error_response {:error, :timeout}

  setup do
    :meck.new(Httpc, [:passthrough])
    on_exit(&:meck.unload/0)
  end

  # Test module for HttpcWithLogging with custom log function
  defmodule TestGear.Httpc do
    use Antikythera.GearApplication.HttpcWithLogging

    # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
    def log(method, url, body, headers, options, response, start_time, end_time, used_time) do
      calls = Process.get(:log_calls, [])
      new_call = {method, url, body, headers, options, response, start_time, end_time, used_time}
      Process.put(:log_calls, [new_call | calls])
      :ok
    end
  end

  # Test module for HttpcWithLogging without custom log function
  defmodule TestGearWithoutLogger.Httpc do
    use Antikythera.GearApplication.HttpcWithLogging
    # No log/9 function defined
  end

  # Test module with a gear logger for testing default logging
  defmodule TestGearWithGearLogger do
    defmodule Logger do
      def info(message) do
        calls = Process.get(:default_log_calls, [])
        Process.put(:default_log_calls, [message | calls])
        :ok
      end
    end

    defmodule Httpc do
      use Antikythera.GearApplication.HttpcWithLogging
      # No custom log/9 function defined - should use default logging

      # Make the function overridable and then redefine it
      defoverridable find_gear_logger_module: 0

      defp find_gear_logger_module do
        # Use test GearLogger for testing
        TestGearWithGearLogger.Logger
      end
    end
  end

  defp clear_log_calls() do
    Process.delete(:log_calls)
  end

  defp get_log_calls() do
    Process.get(:log_calls, []) |> Enum.reverse()
  end

  defp clear_default_log_calls() do
    Process.delete(:default_log_calls)
  end

  defp get_default_log_calls() do
    Process.get(:default_log_calls, []) |> Enum.reverse()
  end

  setup do
    clear_log_calls()
    clear_default_log_calls()
    :ok
  end

  test "request/5 should make HTTP call and log successful response" do
    :meck.expect(Httpc, :request, fn :get, @test_url, @test_body, headers, options ->
      assert headers == @test_headers
      assert options == @test_options
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.request(:get, @test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :get,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, url, body, headers, options, response, start_time, end_time, used_time} =
      hd(log_calls)

    assert method == :get
    assert url == @test_url
    assert body == @test_body
    assert headers == @test_headers
    assert options == @test_options
    assert response == {:ok, @success_response}
    assert is_integer(used_time) and used_time >= 0
    assert {Antikythera.Time, _, _, _} = start_time
    assert {Antikythera.Time, _, _, _} = end_time
  end

  test "request/5 should make HTTP call and log error response" do
    :meck.expect(Httpc, :request, fn :post, @test_url, @test_body, _headers, _options ->
      @error_response
    end)

    result = TestGear.Httpc.request(:post, @test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :post,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == @error_response

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, url, body, headers, options, response, _start_time, _end_time, used_time} =
      hd(log_calls)

    assert method == :post
    assert url == @test_url
    assert body == @test_body
    assert headers == @test_headers
    assert options == @test_options
    assert response == @error_response
    assert is_integer(used_time) and used_time >= 0
  end

  test "request!/5 sould make HTTP call and log successful response" do
    :meck.expect(Httpc, :request, fn :put, @test_url, @test_body, _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.request!(:put, @test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :put,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == @success_response

    log_calls = get_log_calls()
    assert length(log_calls) == 1
  end

  test "request!/5 sould raise on error response but still log" do
    :meck.expect(Httpc, :request, fn :delete, @test_url, @test_body, _headers, _options ->
      @error_response
    end)

    assert_raise(ArgumentError, fn ->
      TestGear.Httpc.request!(:delete, @test_url, @test_body, @test_headers, @test_options)
    end)

    assert :meck.called(Httpc, :request, [
             :delete,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, _body, _headers, _options, response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :delete
    assert response == @error_response
  end

  test "get/3 should call request with GET method and empty body" do
    :meck.expect(Httpc, :request, fn :get, @test_url, "", headers, options ->
      assert headers == @test_headers
      assert options == @test_options
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.get(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:get, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :get
    assert body == ""
  end

  test "get!/3 should call request! with GET method and empty body" do
    :meck.expect(Httpc, :request, fn :get, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.get!(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:get, @test_url, "", @test_headers, @test_options])
    assert result == @success_response

    log_calls = get_log_calls()
    assert length(log_calls) == 1
  end

  test "post/4 should call request with POST method and body" do
    :meck.expect(Httpc, :request, fn :post, @test_url, @test_body, headers, options ->
      assert headers == @test_headers
      assert options == @test_options
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.post(@test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :post,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :post
    assert body == @test_body
  end

  test "post!/4 should call request! with POST method and body" do
    :meck.expect(Httpc, :request, fn :post, @test_url, @test_body, _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.post!(@test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :post,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == @success_response

    log_calls = get_log_calls()
    assert length(log_calls) == 1
  end

  test "put/4 should call request with PUT method and body" do
    :meck.expect(Httpc, :request, fn :put, @test_url, @test_body, _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.put(@test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :put,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :put
    assert body == @test_body
  end

  test "patch/4 should call request with PATCH method and body" do
    :meck.expect(Httpc, :request, fn :patch, @test_url, @test_body, _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.patch(@test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :patch,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :patch
    assert body == @test_body
  end

  test "delete/3 should call request with DELETE method and empty body" do
    :meck.expect(Httpc, :request, fn :delete, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.delete(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:delete, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :delete
    assert body == ""
  end

  test "options/3 should call request with OPTIONS method and empty body" do
    :meck.expect(Httpc, :request, fn :options, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.options(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:options, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :options
    assert body == ""
  end

  test "head/3 should call request with HEAD method and empty body" do
    :meck.expect(Httpc, :request, fn :head, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGear.Httpc.head(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:head, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {method, _url, body, _headers, _options, _response, _start_time, _end_time, _used_time} =
      hd(log_calls)

    assert method == :head
    assert body == ""
  end

  test "multiple requests should be logged separately" do
    :meck.expect(Httpc, :request, fn
      :get, @test_url, "", _headers, _options -> {:ok, @success_response}
      :post, @test_url, @test_body, _headers, _options -> {:ok, @success_response}
    end)

    TestGear.Httpc.get(@test_url, @test_headers, @test_options)
    TestGear.Httpc.post(@test_url, @test_body, @test_headers, @test_options)

    log_calls = get_log_calls()
    assert length(log_calls) == 2

    [
      {method1, _url1, body1, _headers1, _options1, _response1, _start_time1, _end_time1,
       _used_time1},
      {method2, _url2, body2, _headers2, _options2, _response2, _start_time2, _end_time2,
       _used_time2}
    ] = log_calls

    assert method1 == :get
    assert body1 == ""
    assert method2 == :post
    assert body2 == @test_body
  end

  test "timing measurement should work correctly" do
    :meck.expect(Httpc, :request, fn :get, @test_url, "", _headers, _options ->
      :timer.sleep(10)
      {:ok, @success_response}
    end)

    TestGear.Httpc.get(@test_url, @test_headers, @test_options)

    log_calls = get_log_calls()
    assert length(log_calls) == 1

    {_method, _url, _body, _headers, _options, _response, start_time, end_time, used_time} =
      hd(log_calls)

    assert {Antikythera.Time, _, _, _} = start_time
    assert {Antikythera.Time, _, _, _} = end_time
    assert is_integer(used_time) and used_time >= 0
    # The used_time should be at least the sleep time (accounting for some overhead)
    assert used_time >= 10
  end

  test "default logging should work when no custom log/9 function is defined" do
    :meck.expect(Httpc, :request, fn :get, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGearWithGearLogger.Httpc.get(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:get, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    default_log_calls = get_default_log_calls()
    assert length(default_log_calls) == 1

    log_message = hd(default_log_calls)
    assert log_message =~ "HTTP GET #{@test_url}"
    assert log_message =~ "status=200"
    assert log_message =~ ~r/time=\d+ms/
    assert log_message =~ ~r/start=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    assert log_message =~ ~r/end=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

    log_calls = get_log_calls()
    assert Enum.empty?(log_calls)
  end

  test "default logging should handle error responses correctly" do
    :meck.expect(Httpc, :request, fn :post, @test_url, @test_body, _headers, _options ->
      @error_response
    end)

    result =
      TestGearWithGearLogger.Httpc.post(@test_url, @test_body, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [
             :post,
             @test_url,
             @test_body,
             @test_headers,
             @test_options
           ])

    assert result == @error_response

    default_log_calls = get_default_log_calls()
    assert length(default_log_calls) == 1

    log_message = hd(default_log_calls)
    assert log_message =~ "HTTP POST #{@test_url}"
    assert log_message =~ "error=:timeout"
    assert log_message =~ ~r/time=\d+ms/
  end

  test "TestGearWithoutLogger.Httpc should work without logging callback" do
    :meck.expect(Httpc, :request, fn :get, @test_url, "", _headers, _options ->
      {:ok, @success_response}
    end)

    result = TestGearWithoutLogger.Httpc.get(@test_url, @test_headers, @test_options)

    assert :meck.called(Httpc, :request, [:get, @test_url, "", @test_headers, @test_options])
    assert result == {:ok, @success_response}

    log_calls = get_log_calls()
    assert Enum.empty?(log_calls)
  end
end
