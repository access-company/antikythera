# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Asset do
  @retention_days 90
  def retention_days(), do: @retention_days

  @moduledoc """
  Definition of macro to make mapping of asset URLs from their file paths.

  If a gear invokes `static_prefix/0` in its `Router` module, antikythera automatically serves static assets
  (such as HTML, CSS, JS, images) under `priv/static/` directory (see `Antikythera.Router` for detail).
  Although this is handy it's suboptimal in cloud environments.
  Instead, in cloud environments, static assets can be delivered from CDN service.
  Using CDN for assets has the following benefits:

  - faster page load
  - less resource consumption (CPU, network bandwidth, etc.) in both ErlangVMs and load balancers
  - more fine-grained control on asset versions

  To keep track of modifications in asset files, we use MD5 digest of file contents:
  download URLs contain MD5 hashes in their paths.
  This way we can serve multiple versions of a single asset file.

  When a gear is deployed, antikythera's auto-deploy script uploads each asset to cloud storage
  (if the file has modification since last deploy) so that they are readily served by CDN.
  Each asset is served in gzip-compressed format if its file extension indicates that gzip compression can be beneficial.
  Also, assets are configured to accept CORS with e.g. `XMLHttpRequest`.
  When downloaded, each asset comes with a relatively long `max-age` in `cache-control` response header
  so that the data can be reused as long as its content (and thus MD5 digest) does not change.

  This module provides `__using__/2` macro that

  - enables asset serving via CDN
  - generates functions that absorb differences in asset download URLs

  ## Usage

  Define a module that `use`s `Antikythera.Asset` as follows:

      defmodule YourGear.Asset do
        use Antikythera.Asset
      end

  Then `YourGear.Asset` has the following functions.

  - `url/1` : given a file path relative to `priv/static/` directory, returns a URL to download the file
  - `all/0` : returns all pairs of file path and download URL as a map

  If you want antikythera's auto-deploy script to perform asset preparation
  BEFORE compilations of your gear (including `YourGear.Asset` module),
  set up asset preparation methods as described in `Mix.Tasks.Antikythera.PrepareAssets`.

  You can now freely use the module for e.g.

  - HAML templates that refers to asset files
  - WebAPI that returns the URLs of the latest assets in your preferred format (JSON, javascript, etc.)

  With `YourGear.Asset` as above, antikythera's auto-deploy script uploads asset files to cloud storage
  so that they are readily served by CDN.

  ## Asset URLs during development

  If you are using tools such as [webpack-dev-server](https://github.com/webpack/webpack-dev-server)
  during development, you may want your browser to download assets from a web server other than locally-running antikythera.
  In this case, pass `:base_url_during_development` option to `__using__/2` so that `url/1` and `all/0`
  return URLs that point to the specified endpoint.

  ## Retention/cleanup policy for asset files

  An asset file uploaded to cloud storage during deployment of a certain gear version
  becomes "obsolete" when a newly-deployed gear version no longer uses it
  (the file has been either modified, removed or renamed).

  Antikythera keeps track of whether each asset file is obsolete or not.
  Then, antikythera periodically removes asset files
  that have been obsolete for more than #{@retention_days} days.
  The retention period (chosen such that each period includes several deployments of each gear)
  should be long enough for clients to switch from older assets to newer ones.
  """

  @priv_static_dir Path.join("priv", "static")

  alias AntikytheraCore.GearModule

  defmacro __using__(opts) do
    gear_name = Mix.Project.config()[:app]
    check_caller_module(gear_name, __CALLER__.module)
    case list_asset_file_paths() do
      []    -> :ok
      paths ->
        mapping = make_mapping(gear_name, paths, opts)
        make_module_body_ast(mapping)
    end
  end

  defp check_caller_module(gear_name, mod) do
    gear_name_camel = gear_name |> Atom.to_string() |> Macro.camelize()
    case Module.split(mod) do
      [^gear_name_camel, "Asset"] -> :ok
      _                           -> raise "`use #{inspect(__MODULE__)}` is usable only in `#{gear_name_camel}.Asset`"
    end
  end

  # Also used from `antikythera.prepare_assets` task
  def list_asset_file_paths() do
    Path.wildcard(Path.join(@priv_static_dir, "**"))
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, @priv_static_dir))
  end

  defp make_mapping(gear_name, paths, opts) do
    url_fn = make_url_fn(gear_name, opts)
    Map.new(paths, fn path -> {path, url_fn.(path)} end)
  end

  defp make_url_fn(gear_name, opts) do
    if Antikythera.Env.compiling_for_cloud?() do
      # serve assets using CDN (:cowboy_static may be available but it's not related to the URL mapping we are creating)
      &url_cloud(&1, gear_name)
    else
      case Keyword.get(opts, :base_url_during_development) do
        nil ->
          case static_prefix(gear_name) do
            nil    -> raise "neither Router's `static_prefix` nor `:base_url_during_development` are given, cannot make asset download URL"
            prefix ->
              # serve assets using :cowboy_static (make path-only URL)
              fn path -> "#{prefix}/#{path}" end
          end
        base_url0 ->
          # serve assets using something like webpack-dev-server
          base_url = String.replace_suffix(base_url0, "/", "")
          fn path -> "#{base_url}/#{path}" end
      end
    end
  end

  defp url_cloud(path, gear_name) do
    base_url      = Application.fetch_env!(:antikythera, :asset_cdn_endpoint)
    md5           = :erlang.md5(File.read!(Path.join(@priv_static_dir, path))) |> Base.encode16(case: :lower)
    extension     = Path.extname(path)
    path_with_md5 = String.replace_suffix(path, extension, "_#{md5}#{extension}")
    "#{base_url}/#{gear_name}/#{path_with_md5}"
  end

  defp static_prefix(gear_name) do
    try do
      mod = GearModule.router_unsafe(gear_name) # during compilation, safe to generate a new atom
      mod.static_prefix()
    rescue
      UndefinedFunctionError -> nil
    end
  end

  defp make_module_body_ast(mapping) do
    quote bind_quoted: [mapping: Macro.escape(mapping)] do
      # file modifications are tracked by `PropagateFileModifications`; `@external_resource` here would be redundant
      Enum.each(mapping, fn {path, url} ->
        def url(unquote(path)), do: unquote(url)
      end)
      def all(), do: unquote(Macro.escape(mapping))
    end
  end
end
