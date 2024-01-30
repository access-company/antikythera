# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Test.HttpClient do
  defmacro __using__(_) do
    quote do
      @default_base_url Antikythera.Test.Config.base_url()

      alias Antikythera.Httpc

      def get(path, headers \\ %{}, options \\ []) do
        Httpc.get!(base_url() <> path, headers, options)
      end

      def post(path, body, headers \\ %{}, options \\ []) do
        Httpc.post!(base_url() <> path, body, headers, options)
      end

      def post_json(path, json, headers \\ %{}, options \\ []) do
        post(path, {:json, json}, headers, options)
      end

      def post_form(path, query, headers \\ %{}, options \\ []) do
        post(path, {:form, query}, headers, options)
      end

      def put(path, body, headers \\ %{}, options \\ []) do
        Httpc.put!(base_url() <> path, body, headers, options)
      end

      def put_json(path, json, headers \\ %{}, options \\ []) do
        put(path, {:json, json}, headers, options)
      end

      def delete(path, headers \\ %{}, options \\ []) do
        Httpc.delete!(base_url() <> path, headers, options)
      end

      def base_url(), do: @default_base_url

      defoverridable base_url: 0
    end
  end
end
