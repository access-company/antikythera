# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.AssetStorage do
  alias Antikythera.GearName

  defmodule Behaviour do
    @moduledoc """
    Interface to work with storage of asset files.

    See `AntikytheraEal` for common information about pluggable interfaces defined in antikythera.

    All callbacks defined in this behaviour are called only within operational mix tasks;
    they are not used at runtime.

    Asset files stored in the storage may be delivered via CDN.
    It's the callback module's responsibility to properly set headers such as `cache-control` for each asset file.
    """

    @doc """
    Lists all already-stored asset files for the specified gear.
    """
    @callback list(GearName.t) :: [String.t]

    @doc """
    Lists common key prefixes of all already-stored asset files for all gears.

    Based on the key format defined in `Antikythera.Asset`,
    the prefixes are expected to be the list of gear names which have already-stored asset files.
    """
    @callback list_toplevel_prefixes() :: [String.t]

    @doc """
    Uploads the given asset file to the storage.

    Parameters:

    - `path` : File path of the asset file to upload.
    - `key`  : Upload location (typically path part of URL) for the asset file (computed by `Antikythera.Asset`).
    - `mime` : MIME type of the asset file.
    - `gzip?`: Whether gzip compression is beneficial for the asset file.
    """
    @callback upload(path :: Path.t, key :: String.t, mime :: String.t, gzip? :: boolean) :: :ok

    @doc """
    Deletes an asset file identified by the given `key`.
    """
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
