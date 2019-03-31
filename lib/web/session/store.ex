# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Session.Store do
  @moduledoc """
  Behaviour of session store.
  """

  @type session_id :: nil | String.t
  @type session_kv :: %{String.t => any}

  @callback load(session_id) :: {session_id, session_kv}
  @callback save(session_id, session_kv) :: String.t
  @callback delete(session_id) :: :ok
end
