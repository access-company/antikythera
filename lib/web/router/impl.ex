# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Router.Impl do
  @moduledoc """
  Internal functions to implement request routing.
  """

  alias Antikythera.{Http.Method, PathSegment, PathInfo, Request.PathMatches, GearActionTimeout}

  @typep route_entry :: {Method.t(), String.t(), module, atom, Keyword.t(any)}
  @typep route_result_success :: {module, atom, PathMatches.t(), boolean}
  @typep route_result :: nil | route_result_success

  defun generate_route_function_clauses(
          router_module :: v[module],
          from :: v[:web | :gear],
          routing_source :: v[[route_entry]]
        ) :: Macro.t() do
    check_route_definitions(routing_source)
    routes_by_method = Enum.group_by(routing_source, fn {method, _, _, _, _} -> method end)

    Enum.flat_map(routes_by_method, fn {method, routes} ->
      Enum.map(routes, fn {_, path_pattern, controller, action, opts} ->
        route_to_clause(router_module, from, method, path_pattern, controller, action, opts)
      end)
    end) ++ [default_clause(from)]
  end

  defunp check_route_definitions(routing_source :: [route_entry]) :: :ok do
    if !path_names_uniq?(routing_source), do: raise("path names are not unique")

    Enum.each(routing_source, fn {_, path_pattern, _, _, _} ->
      check_path_pattern(path_pattern)
    end)
  end

  defunp path_names_uniq?(routing_source :: [route_entry]) :: boolean do
    Enum.map(routing_source, fn {_verb, _path, _controller, _action, opts} -> opts[:as] end)
    |> Enum.reject(&is_nil/1)
    |> unique_list?()
  end

  defunp unique_list?(l :: [String.t()]) :: boolean do
    length(l) == length(Enum.uniq(l))
  end

  defun check_path_pattern(path_pattern :: v[String.t()]) :: :ok do
    if !String.starts_with?(path_pattern, "/") do
      raise "path must start with '/': #{path_pattern}"
    end

    if byte_size(path_pattern) > 1 and String.ends_with?(path_pattern, "/") do
      raise "non-root path must not end with '/': #{path_pattern}"
    end

    if String.contains?(path_pattern, "//") do
      raise "path must not have '//': #{path_pattern}"
    end

    segments = AntikytheraCore.Handler.GearAction.split_path_to_segments(path_pattern)

    if !Enum.all?(segments, &correct_format?/1) do
      raise "invalid path format: #{path_pattern}"
    end

    if !placeholder_names_uniq?(segments) do
      raise "path format has duplicated placeholder names: #{path_pattern}"
    end

    if !wildcard_segment_comes_last?(segments) do
      raise "cannot have a wildcard '*' followed by other segments: #{path_pattern}"
    end

    :ok
  end

  defunp correct_format?(segment :: v[PathSegment.t()]) :: boolean do
    Regex.match?(~R/\A(([0-9A-Za-z.~_-]*)|([:*][a-z_][0-9a-z_]*))\z/, segment)
  end

  defunp placeholder_names_uniq?(segments :: v[PathInfo.t()]) :: boolean do
    Enum.map(segments, fn
      ":" <> name -> name
      "*" <> name -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> unique_list?()
  end

  defunp wildcard_segment_comes_last?(segments :: v[PathInfo.t()]) :: boolean do
    case Enum.reverse(segments) do
      [] -> true
      [_last | others] -> Enum.all?(others, &(!String.starts_with?(&1, "*")))
    end
  end

  defunp route_to_clause(
           router_module :: v[module],
           from :: v[:web | :gear],
           method :: v[Method.t()],
           path_pattern :: v[String.t()],
           controller :: v[module],
           action :: v[atom],
           opts :: Keyword.t(any)
         ) :: Macro.t() do
    websocket? = Keyword.get(opts, :websocket?, false)

    unless is_boolean(websocket?) do
      raise "option `:websocket?` must be boolean but given: #{websocket?}"
    end

    timeout = Keyword.get(opts, :timeout, GearActionTimeout.default())

    unless GearActionTimeout.valid?(timeout) do
      raise "option `:timeout` must be a positive integer less than or equal to #{
              GearActionTimeout.max()
            } but given: #{timeout}"
    end

    if String.contains?(path_pattern, "/*") do
      # For route with wildcard we have to define a slightly modified clause (compared with nowildcard case):
      # - `path_info` must be matched with `[... | wildcard]` pattern
      # - value of `path_matches` must be `Enum.join`ed
      path_info_arg_expr_nowildcard =
        make_path_info_arg_expr_nowildcard(router_module, path_pattern)

      path_info_arg_expr = make_path_info_arg_expr_wildcard(path_info_arg_expr_nowildcard)
      path_matches_expr = make_path_matches_expr_wildcard(path_info_arg_expr_nowildcard)

      quote do
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        def unquote(:"__#{from}_route__")(unquote(method), unquote(path_info_arg_expr)) do
          Antikythera.Router.Impl.route_clause_body(
            unquote(controller),
            unquote(action),
            unquote(path_matches_expr),
            unquote(websocket?),
            unquote(timeout)
          )
        end
      end
    else
      # For each route without wildcard, we define two clauses to match request paths with and without trailing '/'
      path_info_arg_expr = make_path_info_arg_expr_nowildcard(router_module, path_pattern)
      path_info_arg_expr2 = path_info_arg_expr ++ [""]
      path_matches_expr = make_path_matches_expr_nowildcard(path_info_arg_expr)

      quote do
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        def unquote(:"__#{from}_route__")(unquote(method), unquote(path_info_arg_expr)) do
          Antikythera.Router.Impl.route_clause_body(
            unquote(controller),
            unquote(action),
            unquote(path_matches_expr),
            unquote(websocket?),
            unquote(timeout)
          )
        end

        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        def unquote(:"__#{from}_route__")(unquote(method), unquote(path_info_arg_expr2)) do
          Antikythera.Router.Impl.route_clause_body(
            unquote(controller),
            unquote(action),
            unquote(path_matches_expr),
            unquote(websocket?),
            unquote(timeout)
          )
        end
      end
    end
  end

  defunp default_clause(from :: v[:web | :gear]) :: Macro.t() do
    quote do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      def unquote(:"__#{from}_route__")(_, _) do
        nil
      end
    end
  end

  defunp make_path_info_arg_expr_nowildcard(
           router_module :: v[module],
           path_pattern :: v[String.t()]
         ) :: [String.t() | Macro.t()] do
    String.split(path_pattern, "/", trim: true)
    |> Enum.map(fn
      # `String.to_atom` during compilation; nothing to worry about
      # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
      ":" <> placeholder -> Macro.var(String.to_atom(placeholder), router_module)
      "*" <> placeholder -> Macro.var(String.to_atom(placeholder), router_module)
      fixed -> fixed
    end)
  end

  defunp make_path_info_arg_expr_wildcard(
           path_info_arg_expr_nowildcard :: v[[String.t() | Macro.t()]]
         ) :: Macro.t() do
    wildcard = List.last(path_info_arg_expr_nowildcard)

    case length(path_info_arg_expr_nowildcard) do
      1 ->
        quote do: unquote(wildcard)

      len ->
        segments = Enum.slice(path_info_arg_expr_nowildcard, 0, len - 2)
        before_wildcard = Enum.at(path_info_arg_expr_nowildcard, len - 2)

        quote do
          # wildcard part must not be an empty list
          [unquote_splicing(segments), unquote(before_wildcard) | [_ | _] = unquote(wildcard)]
        end
    end
  end

  defunp make_path_matches_expr_nowildcard(path_info_arg_expr :: v[[String.t() | Macro.t()]]) ::
           Keyword.t(Macro.t()) do
    Enum.map(path_info_arg_expr, fn
      {name, _, _} = v -> {name, v}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defunp make_path_matches_expr_wildcard(
           path_info_arg_expr_nowildcard :: v[[String.t() | Macro.t()]]
         ) :: Keyword.t(Macro.t()) do
    {name, _, _} = var = List.last(path_info_arg_expr_nowildcard)
    wildcard_pair = {name, quote(do: Enum.join(unquote(var), "/"))}

    path_matches_expr_without_last =
      Enum.slice(path_info_arg_expr_nowildcard, 0, length(path_info_arg_expr_nowildcard) - 1)
      |> make_path_matches_expr_nowildcard

    path_matches_expr_without_last ++ [wildcard_pair]
  end

  defun route_clause_body(
          controller :: v[module],
          action :: v[atom],
          path_matches :: Keyword.t(String.t()),
          websocket? :: v[boolean],
          timeout :: v[GearActionTimeout.t()] \\ GearActionTimeout.default()
        ) :: route_result do
    if Enum.all?(path_matches, fn {_placeholder, match} -> String.printable?(match) end) do
      {controller, action, Map.new(path_matches), websocket?, timeout}
    else
      nil
    end
  end
end
