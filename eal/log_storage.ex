# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.LogStorage do
  @moduledoc """
  Interface to work with storage of log files.
  """

  alias SolomonLib.GearName
  alias AntikytheraCore.Path, as: CorePath

  defmodule Behaviour do
    @callback list(GearName.t, String.t) :: [{String.t, non_neg_integer}]
    @callback download_urls([String.t]) :: [String.t]
    @callback upload_rotated_logs(GearName.t) :: :ok
  end

  defmodule FileSystem do
    @behaviour Behaviour

    @impl true
    defun list(gear_name :: v[GearName.t], date_str :: v[String.t]) :: [{String.t, non_neg_integer}] do
      dir = CorePath.gear_log_file_path(gear_name) |> Path.dirname()
      Path.wildcard(Path.join(dir, "#{gear_name}.log.#{date_str}??????.gz")) # match timestamp such as "20150825120000", exclude .uploaded.gz
      |> Enum.map(fn path -> {path, File.stat!(path).size} end)
    end

    @impl true
    defun download_urls(paths :: v[[String.t]]) :: [String.t] do
      Enum.map(paths, fn path -> "file://#{path}" end)
    end

    @impl true
    defun upload_rotated_logs(gear_name :: v[GearName.t]) :: :ok do
      :timer.sleep(100) # to test that Writer process prevents multiple processes from running simultaneously
      gear_log_dir = CorePath.gear_log_file_path(gear_name) |> Path.dirname()
      Path.wildcard(Path.join(gear_log_dir, "#{gear_name}.log.??????????????.gz")) # match timestamp such as "20150825120000", exclude .uploaded.gz
      |> Enum.each(fn path ->
        File.rename(path, String.replace_suffix(path, ".gz", ".uploaded.gz"))
      end)
    end
  end

  use AntikytheraEal.ImplChooser
end
