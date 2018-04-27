# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma
alias Croma.Result, as: R
alias Antikythera.Time

defmodule Antikythera.IsoTimestamp do
  @moduledoc """
  A strict subset of ISO8601 format of timestamp.
  """

  @type t :: String.t

  defun valid?(v :: term) :: boolean do
    t when is_binary(t) -> Time.from_iso_timestamp(t) |> R.ok?()
    _                   -> false
  end
end

defmodule Antikythera.IsoTimestamp.Basic do
  @moduledoc """
  ISO8601 basic format.
  """

  @type t :: String.t

  defun valid?(v :: term) :: boolean do
    t when is_binary(t) -> Time.from_iso_basic(t) |> R.ok?()
    _                   -> false
  end
end
