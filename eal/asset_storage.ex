# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.AssetStorage do
  @moduledoc """
  Interface to work with storage of asset files.

  This module and its callbacks are used only during operational mix tasks; they are not used in runtime.

  Asset files stored in the storage are delivered via CDN.
  It's the implementation module's responsibility to properly set headers such as `cache-control` for each asset file.
  """

  alias Antikythera.GearName

  defmodule Behaviour do
    @callback list(GearName.t) :: [String.t]
    @callback list_toplevel_prefixes() :: [String.t]
    @callback upload(path :: Path.t, key :: String.t, mime :: String.t, gzip? :: boolean) :: :ok
    @callback delete(key :: String.t) :: :ok
  end

  defmodule NoOp do
    @behaviour Behaviour

    @impl true
    def list(_gear_name), do: []

    @impl true
    def list_toplevel_prefixes(), do: []

    @impl true
    def upload(_path, _key, _mime, _gzip?), do: :ok

    @impl true
    def delete(_key), do: :ok
  end

  use AntikytheraEal.ImplChooser
end
