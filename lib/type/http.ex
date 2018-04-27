# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.Http do
  defmodule Method do
    use Croma.SubtypeOfAtom, values: [:get, :post, :put, :patch, :delete, :options, :connect, :trace, :head]
    @all [:get, :post, :put, :patch, :delete, :options, :connect, :trace, :head]
    def all(), do: @all

    @spec from_string(String.t) :: t
    @spec to_string(t) :: String.t
    for method <- @all do
      method_str = method |> Atom.to_string() |> String.upcase()
      def from_string(unquote(method_str)), do: unquote(method)
      def to_string(unquote(method)), do: unquote(method_str)
    end
  end

  defmodule QueryParams do
    use Croma.SubtypeOfMap, key_module: Croma.String, value_module: Croma.String, default: %{}
  end

  defmodule Headers do
    @moduledoc """
    HTTP headers as a map.

    If multiple headers in a single request/response have the same header name,
    their values are concatenated with commas.
    In case of `cookie` header values are concatenated using semicolons instead of commas.
    """

    use Croma.SubtypeOfMap, key_module: Croma.String, value_module: Croma.String, default: %{}
  end

  defmodule SetCookie do
    alias Croma.TypeGen
    use Croma.Struct, recursive_new?: true, fields: [
      value:     Croma.String,
      path:      TypeGen.nilable(SolomonLib.EncodedPath),
      domain:    TypeGen.nilable(SolomonLib.Domain),
      secure:    TypeGen.nilable(Croma.Boolean),
      http_only: TypeGen.nilable(Croma.Boolean),
      max_age:   TypeGen.nilable(Croma.Integer),
    ]

    @type options_t :: %{
      optional(:path     ) => SolomonLib.EncodedPath.t,
      optional(:domain   ) => SolomonLib.Domain.t,
      optional(:secure   ) => boolean,
      optional(:http_only) => boolean,
      optional(:max_age  ) => non_neg_integer,
    }

    defun parse!(s :: v[String.t]) :: {String.t, t} do
      [pair | attrs] = String.split(s, ~r/\s*;\s*/)
      [name, value] = String.split(pair, "=", parts: 2)
      cookie =
        Enum.reduce(attrs, %__MODULE__{value: value}, fn(attr, acc) ->
          case attr_to_opt(attr) do
            nil                   -> acc
            {opt_name, opt_value} -> Map.put(acc, opt_name, opt_value)
          end
        end)
      {name, cookie}
    end

    defp attr_to_opt(attr) do
      [name | rest] = String.split(attr, ~r/\s*=\s*/, parts: 2)
      case String.downcase(name) do
        "path"     -> {:path     , hd(rest)}
        "domain"   -> {:domain   , hd(rest)}
        "secure"   -> {:secure   , true}
        "httponly" -> {:http_only, true}
        "max-age"  -> {:max_age  , String.to_integer(hd(rest))}
        _          -> nil # version, expires or comment attribute
      end
    end
  end

  defmodule SetCookiesMap do
    use Croma.SubtypeOfMap, key_module: Croma.String, value_module: SetCookie, default: %{}
  end

  defmodule ReqCookiesMap do
    use Croma.SubtypeOfMap, key_module: Croma.String, value_module: Croma.String, default: %{}
  end

  defmodule RawBody do
    @type t :: binary

    defun valid?(v :: term) :: boolean, do: is_binary(v)

    def default(), do: ""
  end

  defmodule Body do
    @type t :: binary | [any] | %{String.t => any}

    defun valid?(v :: term) :: boolean do
      is_binary(v) or is_map(v) or is_list(v)
    end

    def default(), do: ""
  end

  defmodule Status do
    statuses = [
      continue:                        100,
      switching_protocols:             101,
      processing:                      102,
      ok:                              200,
      created:                         201,
      accepted:                        202,
      non_authoritative_information:   203,
      no_content:                      204,
      reset_content:                   205,
      partial_content:                 206,
      multi_status:                    207,
      already_reported:                208,
      multiple_choices:                300,
      moved_permanently:               301,
      found:                           302,
      see_other:                       303,
      not_modified:                    304,
      use_proxy:                       305,
      reserved:                        306,
      temporary_redirect:              307,
      permanent_redirect:              308,
      bad_request:                     400,
      unauthorized:                    401,
      payment_required:                402,
      forbidden:                       403,
      not_found:                       404,
      method_not_allowed:              405,
      not_acceptable:                  406,
      proxy_authentication_required:   407,
      request_timeout:                 408,
      conflict:                        409,
      gone:                            410,
      length_required:                 411,
      precondition_failed:             412,
      request_entity_too_large:        413,
      request_uri_too_long:            414,
      unsupported_media_type:          415,
      requested_range_not_satisfiable: 416,
      expectation_failed:              417,
      unprocessable_entity:            422,
      locked:                          423,
      failed_dependency:               424,
      upgrade_required:                426,
      precondition_required:           428,
      too_many_requests:               429,
      request_header_fields_too_large: 431,
      internal_server_error:           500,
      not_implemented:                 501,
      bad_gateway:                     502,
      service_unavailable:             503,
      gateway_timeout:                 504,
      http_version_not_supported:      505,
      variant_also_negotiates:         506,
      insufficient_storage:            507,
      loop_detected:                   508,
      not_extended:                    510,
      network_authentication_required: 511,
    ]

    defmodule Atom do
      use Croma.SubtypeOfAtom, values: Keyword.keys(statuses)
    end
    defmodule Int do
      use Croma.SubtypeOfInt, min: 100, max: 999
    end

    @type t :: Atom.t | Int.t

    defun valid?(v :: term) :: boolean do
      Int.valid?(v) or Atom.valid?(v)
    end

    @spec code(Int.t | atom) :: Int.t
    def code(int) when int in 100..999 do
      int
    end
    for {atom, code} <- statuses do
      def code(unquote(atom)), do: unquote(code)
    end
  end
end
