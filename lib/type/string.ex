# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma
alias Croma.Result, as: R

defmodule Antikythera.VersionStr do
  @moduledoc """
  Format of versions of antikythera instances and gears.

  The format rule is a stricter variant of [semantic versioning](https://semver.org/);
  pre-release part and build metadata part are filled with information
  from the current git commit (committer date and commit hash, respectively).
  This way we always make a new version for each new git commit,
  which enables both antikythera instances and gears to be deployed on a per-commit basis.
  The actual version strings are created by
  `Antikythera.MixCommon.version_with_last_commit_info/1` defined in `mix_common.exs` file.

  Note that the current format prohibits multi-digits numbers as major/minor/patch version;
  this is just to simplify deployment and not an intrinsic limitation.
  """

  use Croma.SubtypeOfString, pattern: ~R/\A\d\.\d\.\d-\d{14}\+[0-9a-f]{40}\z/
end

defmodule Antikythera.Domain do
  @moduledoc """
  Domain name format, originally defined in [RFC1034](https://tools.ietf.org/html/rfc1034#section-3.5).

  - It accepts 1 to 63 letters label in top-level domains as per original syntax definition.
  - It accepts all-numeric top-level domains as opposed to the restriction in [RFC3696](https://tools.ietf.org/html/rfc3696#section-2).
      - If it is the sole part of domain name, (e.g. http://2130706433)
        client applications will most likely parse them as 32-bit integer representation of IPv4 address.
  """
  @pattern_body "((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)*(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
  def pattern_body(), do: @pattern_body

  use Croma.SubtypeOfString, pattern: ~r/\A#{@pattern_body}\z/
end

defmodule Antikythera.CowboyWildcardDomain do
  use Croma.SubtypeOfString, pattern: ~r/\A:_\.#{Antikythera.Domain.pattern_body()}\z/
end

defmodule Antikythera.DomainList do
  use Croma.SubtypeOfList, elem_module: Antikythera.Domain, max_length: 10
end

defmodule Antikythera.PathSegment do
  @moduledoc """
  A type module to represent URI-encoded segment of URL path.

  See [RFC3986](https://tools.ietf.org/html/rfc3986#section-3.3) for the specifications of URI path.
  Note that this module accepts empty strings.
  """

  @charclass "[0-9A-Za-z\-._~%!$&'()*+,;=:@]"
  def charclass(), do: @charclass

  use Croma.SubtypeOfString, pattern: ~r|\A#{@charclass}*\z|
end

defmodule Antikythera.PathInfo do
  # percent-decoded, any string is allowed in each segment
  use Croma.SubtypeOfList, elem_module: Croma.String
end

defmodule Antikythera.UnencodedPath do
  @segment_charclass "[^/?#]"
  def segment_charclass(), do: @segment_charclass

  use Croma.SubtypeOfString, pattern: ~r"\A/(#{@segment_charclass}+/)*(#{@segment_charclass}+)?\z"
end

defmodule Antikythera.EncodedPath do
  alias Antikythera.PathSegment, as: Segment

  use Croma.SubtypeOfString,
    pattern: ~r"\A/(#{Segment.charclass()}+/)*(#{Segment.charclass()}+)?\z"
end

defmodule Antikythera.Url do
  @moduledoc """
  URL format, originally defined in [RFC1738](https://tools.ietf.org/html/rfc1738),
  and updated in [RFC3986](https://tools.ietf.org/html/rfc3986) as a subset of URI.

  - Only accepts `http` or `https` as scheme.
  - IPv4 addresses in URLs must be 4-part-dotted-decimal formats.
      - e.g. 192.168.0.1
      - See [here](https://tools.ietf.org/html/rfc3986#section-3.2.2)
  - IPv6 addresses are not supported currently.
  """

  alias Antikythera.Domain
  alias Antikythera.IpAddress.V4, as: IpV4

  @type t :: String.t()

  captured_ip_pattern = "(?<ip_str>(\\d{1,3}\\.){3}\\d{1,3})"
  host_pattern = "(#{captured_ip_pattern}|#{Domain.pattern_body()})"
  path_pattern = "((/[^/\\s?#]+)*/?)?"

  @pattern ~r"\Ahttps?://([^\s:]+(:[^\s:]+)?@)?#{host_pattern}(:\d{1,5})?#{path_pattern}(\?([^\s#]*))?(#[^\s]*)?\z"
  def pattern(), do: @pattern

  defun valid?(v :: term) :: boolean do
    s when is_binary(s) ->
      case Regex.named_captures(@pattern, s) do
        %{"ip_str" => ""} -> true
        %{"ip_str" => ip_str} -> IpV4.parse(ip_str) |> R.ok?()
        nil -> false
      end

    _ ->
      false
  end
end

defmodule Antikythera.Email do
  @moduledoc """
  Email address format, defined in [RFC5321](https://tools.ietf.org/html/rfc5321),
  and [RFC5322](https://tools.ietf.org/html/rfc5322).
  There are some differences from original RFCs for simplicity:

  - Leading, trailing and/or consecutive '.'s in local parts are allowed.
  - Double-quoted local parts are not allowed.
  - '[]'-enclosed IP address literals in domain parts are not allowed.
  - Total length of domain parts are not limited to 255.
  """

  use Croma.SubtypeOfString,
    pattern: ~r"\A[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]{1,64}@#{Antikythera.Domain.pattern_body()}\z"
end

defmodule Antikythera.NodeId do
  @pattern_string "[0-9A-Za-z.-]+"
  def pattern_string(), do: @pattern_string

  use Croma.SubtypeOfString, pattern: ~r/\A#{@pattern_string}\z/
end

defmodule Antikythera.ContextId do
  @system_context "antikythera_system"
  def system_context(), do: @system_context

  use Croma.SubtypeOfString,
    pattern:
      ~r/\A(\d{8}-\d{6}\.\d{3}_#{Antikythera.NodeId.pattern_string()}_\d+\.\d+\.\d+|#{
        @system_context
      })\z/
end

defmodule Antikythera.ImfFixdate do
  @moduledoc """
  An IMF-fixdate format of date/time. Used in HTTP headers.
  Only 'GMT' is allowed as timezone string.
  """

  days_of_week = "(Mon|Tue|Wed|Thu|Fri|Sat|Sun)"
  months_of_year = "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"

  use Croma.SubtypeOfString,
    pattern: ~r/\A#{days_of_week}, \d\d #{months_of_year} \d\d\d\d \d\d:\d\d:\d\d GMT\z/
end

defmodule Antikythera.GearName do
  @moduledoc """
  Type module to represent gear names as atoms.
  """

  alias Antikythera.GearNameStr

  @type t :: atom

  defun valid?(v :: term) :: boolean do
    a when is_atom(a) -> GearNameStr.valid?(Atom.to_string(a))
    _ -> false
  end
end

defmodule Antikythera.GearNameStr do
  use Croma.SubtypeOfString, pattern: ~R/\A[a-z][0-9a-z_]{2,31}\z/
end

defmodule Antikythera.TenantId do
  @notenant "notenant"
  defun notenant() :: String.t(), do: @notenant

  use Croma.SubtypeOfString, pattern: ~r/\A(?!^#{@notenant}$)[0-9A-Za-z_]{3,32}\z/
end
