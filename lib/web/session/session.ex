# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Session do
  @moduledoc """
  Definition of data structure to work with session.

  Gear implementations usually don't use the functions defined in this module;
  instead use

  - `Antikythera.Plug.Session`
  - interfaces in `Antikythera.Conn` (e.g. `Antikythera.Conn.get_session/2`).
  """

  defmodule State do
    use Croma.SubtypeOfAtom, values: [:update, :renew, :destroy]
  end

  use Croma.Struct,
    recursive_new?: true,
    fields: [
      state: Antikythera.Session.State,
      id: Croma.TypeGen.nilable(Croma.String),
      data: Croma.Map
    ]

  defun get(%__MODULE__{data: data}, key :: v[String.t()]) :: any do
    data[key]
  end

  defun put(%__MODULE__{data: data} = session, key :: v[String.t()], value :: any) :: t do
    %__MODULE__{session | data: Map.put(data, key, value)}
  end

  defun delete(%__MODULE__{data: data} = session, key :: v[String.t()]) :: t do
    %__MODULE__{session | data: Map.delete(data, key)}
  end

  defun clear(session :: t) :: t do
    %__MODULE__{session | data: %{}}
  end

  defun renew(session :: t) :: t do
    %__MODULE__{session | state: :renew}
  end

  defun destroy(session :: t) :: t do
    %__MODULE__{session | state: :destroy}
  end
end
