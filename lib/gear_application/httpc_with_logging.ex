# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.HttpcWithLogging.Logger do
  @moduledoc """
  Behavior for customizing HTTP request logging in `HttpcWithLogging`.

  This behavior defines an optional callback for HTTP request logging.
  When you `use Antikythera.GearApplication.HttpcWithLogging`, the behavior
  is automatically applied to your module, but implementing the callback is optional.
  """

  alias Antikythera.{Http, Httpc}
  alias Httpc.{ReqBody, Response}
  alias Croma.Result, as: R

  @callback log(
              method :: Http.Method.t(),
              url :: Antikythera.Url.t(),
              body :: ReqBody.t(),
              headers :: Http.Headers.t(),
              options :: Keyword.t(),
              response :: R.t(Response.t()),
              start_time :: Antikythera.Time.t(),
              end_time :: Antikythera.Time.t(),
              used_time :: non_neg_integer()
            ) :: :ok

  @optional_callbacks log: 9
end

defmodule Antikythera.GearApplication.HttpcWithLogging do
  @moduledoc """
  Helper module to create HTTP client wrapper with logging functionality.

  This module provides a wrapper around `Antikythera.Httpc` that automatically includes
  logging capabilities for HTTP requests. When a gear application creates a dedicated
  HTTP client module that `use`s this module, it generates HTTP client functions that
  automatically log HTTP requests using the gear's configured logging mechanism.

  ## Usage

  Create a dedicated HTTP client module in your gear application:

      defmodule MyGear.Httpc do
        use Antikythera.GearApplication.HttpcWithLogging
      end

  This will add HTTP client functions with automatic logging directly to `MyGear.Httpc`.

  ## Generated Functions

  The module that uses `HttpcWithLogging` will have the same interface as
  `Antikythera.Httpc` but with automatic logging:

  - `request/5` - Make HTTP request with logging
  - `request!/5` - Make HTTP request with logging, raising on error
  - `get/3`, `post/4`, `put/4`, etc.
  - `get!/3`, `post!/4`, `put!/4`, etc.

  ## Example

      # In your gear controller:
      response = MyGear.Httpc.get("https://api.example.com/data")

  This will automatically log the HTTP request using your gear's logging configuration,
  and invoke any custom logging callback defined directly in your HTTP client module
  (if present).

  ## Custom Logging Callback

  To customize HTTP request logging, simply implement the optional `log/9` callback:

      defmodule MyGear.Httpc do
        use Antikythera.GearApplication.HttpcWithLogging

        @impl true
        def log(method, url, body, headers, options, response, start_time, end_time, used_time) do
          # Custom logging logic here
          # This will be called for each HTTP request made via this HTTP client
        end
      end

  The `@behaviour` declaration is automatically added when you `use` this module,
  and the `log/9` callback is optional - you only need to implement it if you want
  custom logging behavior.

  The `log/9` callback receives:
  - `method` - HTTP method atom (`:get`, `:post`, etc.)
  - `url` - Request URL string
  - `body` - Request body
  - `headers` - Request headers map
  - `options` - Request options keyword list
  - `response` - Response result (success or error)
  - `start_time` - Request start time
  - `end_time` - Request end time
  - `used_time` - Request duration in milliseconds

  If no custom logging behavior is implemented, the module will fall back to using
  the gear's default logger (if available) to log basic HTTP request information.
  """

  alias Antikythera.{Http, Httpc}
  alias Httpc.{ReqBody, Response}
  alias Croma.Result, as: R

  defmacro __using__(_) do
    # Generate method functions outside of the quote to avoid variable scoping issues
    get_methods =
      for method <- [:get, :delete, :options, :head] do
        quote do
          defun unquote(method)(
                  url :: Antikythera.Url.t(),
                  headers :: Http.Headers.t() \\ %{},
                  options :: Keyword.t() \\ []
                ) :: R.t(Response.t()) do
            request(unquote(method), url, "", headers, options)
          end

          defun unquote(:"#{method}!")(
                  url :: Antikythera.Url.t(),
                  headers :: Http.Headers.t() \\ %{},
                  options :: Keyword.t() \\ []
                ) :: Response.t() do
            request!(unquote(method), url, "", headers, options)
          end
        end
      end

    body_methods =
      for method <- [:post, :put, :patch] do
        quote do
          defun unquote(method)(
                  url :: Antikythera.Url.t(),
                  body :: ReqBody.t(),
                  headers :: Http.Headers.t() \\ %{},
                  options :: Keyword.t() \\ []
                ) :: R.t(Response.t()) do
            request(unquote(method), url, body, headers, options)
          end

          defun unquote(:"#{method}!")(
                  url :: Antikythera.Url.t(),
                  body :: ReqBody.t(),
                  headers :: Http.Headers.t() \\ %{},
                  options :: Keyword.t() \\ []
                ) :: Response.t() do
            request!(unquote(method), url, body, headers, options)
          end
        end
      end

    quote do
      @behaviour Antikythera.GearApplication.HttpcWithLogging.Logger

      alias Antikythera.{Http, Httpc}
      alias Httpc.{ReqBody, Response}
      alias Croma.Result, as: R

      defun request(
              method :: v[Http.Method.t()],
              url :: v[Antikythera.Url.t()],
              body :: v[ReqBody.t()],
              headers :: v[Http.Headers.t()] \\ %{},
              options :: Keyword.t() \\ []
            ) :: R.t(Response.t()) do
        start_monotonic = System.monotonic_time(:millisecond)
        start_time = Antikythera.Time.now()

        response = Httpc.request(method, url, body, headers, options)

        end_time = Antikythera.Time.now()
        used_time = System.monotonic_time(:millisecond) - start_monotonic

        invoke_gear_logger(
          method,
          url,
          body,
          headers,
          options,
          response,
          start_time,
          end_time,
          used_time
        )

        response
      end

      defun request!(
              method :: v[Http.Method.t()],
              url :: v[Antikythera.Url.t()],
              body :: v[ReqBody.t()],
              headers :: v[Http.Headers.t()] \\ %{},
              options :: Keyword.t() \\ []
            ) :: Response.t() do
        request(method, url, body, headers, options) |> R.get!()
      end

      defunp invoke_gear_logger(
               method :: v[Http.Method.t()],
               url :: v[Antikythera.Url.t()],
               body :: v[ReqBody.t()],
               headers :: v[Http.Headers.t()],
               options :: Keyword.t(),
               response :: R.t(Response.t()),
               start_time :: Antikythera.Time.t(),
               end_time :: Antikythera.Time.t(),
               used_time :: non_neg_integer()
             ) :: :ok do
        # Call custom log function if implemented (optional callback)
        if function_exported?(__MODULE__, :log, 9) do
          try do
            apply(__MODULE__, :log, [
              method,
              url,
              body,
              headers,
              options,
              response,
              start_time,
              end_time,
              used_time
            ])
          rescue
            _ ->
              :ok
          end
        else
          default_gear_log(method, url, response, start_time, end_time, used_time)
        end

        :ok
      end

      defunp find_gear_logger_module() :: module() | nil do
        try do
          # Extract the gear module name from __MODULE__
          gear_name = __MODULE__ |> Module.split() |> hd()
          logger_module = Module.safe_concat([gear_name, Logger])

          if function_exported?(logger_module, :info, 1) do
            logger_module
          else
            nil
          end
        rescue
          _ ->
            nil
        end
      end

      defunp default_gear_log(
               method :: v[Http.Method.t()],
               url :: v[Antikythera.Url.t()],
               response :: R.t(Response.t()),
               start_time :: Antikythera.Time.t(),
               end_time :: Antikythera.Time.t(),
               used_time :: non_neg_integer()
             ) :: :ok do
        case find_gear_logger_module() do
          nil ->
            :ok

          logger_module ->
            status_info =
              case response do
                {:ok, %{status: status}} -> "status=#{status}"
                {:error, reason} -> "error=#{inspect(reason)}"
              end

            start_time_str = Antikythera.Time.to_iso_timestamp(start_time)
            end_time_str = Antikythera.Time.to_iso_timestamp(end_time)

            log_message =
              "HTTP #{String.upcase(to_string(method))} #{url} #{status_info} time=#{used_time}ms start=#{start_time_str} end=#{end_time_str}"

            logger_module.info(log_message)
        end

        :ok
      end

      unquote_splicing(get_methods)

      unquote_splicing(body_methods)
    end
  end
end
