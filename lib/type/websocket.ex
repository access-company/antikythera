# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Websocket.Frame do
  @moduledoc """
  Simplified data type for websocket frames.
  """

  @type close_code    :: 1000..4999
  @type close_payload :: String.t

  @type t :: :close
           | {:close, close_code, binary}
           | {:text | :binary, binary}

  defun valid?(v :: term) :: boolean do
    :close                                               -> true
    {:close, c, b} when c in 1000..4999 and is_binary(b) -> true
    {:text, b} when is_binary(b)                         -> true
    {:binary, b} when is_binary(b)                       -> true
    _                                                    -> false
  end
end

defmodule Antikythera.Websocket.FrameList do
  use Croma.SubtypeOfList, elem_module: Antikythera.Websocket.Frame
end
