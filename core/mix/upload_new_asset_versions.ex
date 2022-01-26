# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Mix.Tasks.AntikytheraCore.UploadNewAssetVersions do
  @shortdoc "Uploads assets to asset storage so that they can be delivered via CDN"

  @moduledoc """
  #{@shortdoc}.

  This mix task is invoked during gear deployment from within each gear project.
  """

  use Mix.Task
  alias AntikytheraEal.AssetStorage
  alias AntikytheraCore.Mix.AssetList

  def run(_) do
    Mix.Task.run("loadpaths")
    gear_name = Mix.Project.config()[:app]

    case all_assets(gear_name) do
      nil -> :ok
      mapping -> do_run(gear_name, mapping)
    end
  end

  defp all_assets(gear_name) do
    gear_name_camel = gear_name |> Atom.to_string() |> Macro.camelize()
    # the module is not yet loaded, it's inevitable to make a new atom here
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    mod = Module.concat(gear_name_camel, "Asset")

    try do
      {:module, ^mod} = Code.ensure_loaded(mod)
      mod.all()
    rescue
      _nonexisting_module_or_undefined_function -> nil
    end
  end

  defp do_run(gear_name, mapping) do
    try do
      existing_assets = AssetStorage.list(gear_name) |> MapSet.new()
      pairs = Enum.map(mapping, fn {path, url} -> {path, url_to_key(url)} end)

      for {path, key} <- pairs, key not in existing_assets do
        do_upload(path, key)
      end

      keys = Enum.map(pairs, fn {_path, key} -> key end)
      AssetList.write!(gear_name, keys)
    after
      {_, 0} = System.cmd("git", ["clean", "-f"])
      {_, 0} = System.cmd("git", ["checkout", "."])
    end
  end

  defp url_to_key(url) do
    URI.parse(url).path |> String.replace_prefix("/", "")
  end

  defp do_upload(path_from_static, key) do
    {type, sub, _} = :cow_mimetypes.web(path_from_static)
    mime = "#{type}/#{sub}"
    path_from_project_top = Path.join(["priv", "static", path_from_static])
    gzip? = gzip?(mime)
    AssetStorage.upload(path_from_project_top, key, mime, gzip?)
    IO.puts("uploaded #{path_from_project_top} as key=#{key} mime=#{mime} gzip?=#{gzip?}")
  end

  # The following list is taken from CloudFront's documentation:
  # http://docs.aws.amazon.com/ja_jp/AmazonCloudFront/latest/DeveloperGuide/ServingCompressedFiles.html
  mime_types_to_compress = ~W(
    application/eot
    application/font
    application/font-sfnt
    application/javascript
    application/json
    application/opentype
    application/otf
    application/pkcs7-mime
    application/truetype
    application/ttf
    application/vnd.ms-fontobject
    application/x-font-opentype
    application/x-font-truetype
    application/x-font-ttf
    application/x-httpd-cgi
    application/x-javascript
    application/x-mpegurl
    application/x-opentype
    application/x-otf
    application/x-perl
    application/x-ttf
    application/xhtml+xml
    application/xml
    application/xml+rss
    font/eot
    font/opentype
    font/otf
    font/ttf
    image/svg+xml
    text/css
    text/csv
    text/html
    text/javascript
    text/js
    text/plain
    text/richtext
    text/tab-separated-values
    text/x-component
    text/x-java-source
    text/x-script
    text/xml
  )

  Enum.each(mime_types_to_compress, fn mime ->
    defp gzip?(unquote(mime)), do: true
  end)

  defp gzip?(_), do: false
end
