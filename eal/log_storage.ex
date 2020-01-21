# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.LogStorage do
  alias Antikythera.GearName
  alias AntikytheraCore.Path, as: CorePath

  defmodule Behaviour do
    @moduledoc """
    Interface to work with storage of gear log files.

    See `AntikytheraEal` for common information about pluggable interfaces defined in antikythera.

    Gear's log messages are written to a file in local filesystem (by `AntikytheraCore.GearLog.Writer`).
    Log files are then rotated after certain times and then uploaded to log storage.

    Typically rotated log files are uploaded by a script that runs outside of antikythera,
    in order to correctly upload logs even after ErlangVM crashes.
    `upload_rotated_logs/1` can also be used to upload logs to the storage, but this callback is
    basically intended for on-demand (i.e. gear administrator initiated) uploads.
    """

    @doc """
    Lists already-uploaded log files, whose last log messages are generated on the specified date, of a gear.

    `date_str` is of the form of `"20180101"`.

    Returns list of pairs, where each pair consists of

    - key which identifies the log file
    - size of the log file
    """
    @callback list(gear_name :: GearName.t, date_str :: String.t) :: [{String.t, non_neg_integer}]

    @doc """
    Generates download URLs of multiple log files specified by list of keys.

    Keys can be obtained by `list/2`.
    """
    @callback download_urls(keys :: [String.t]) :: [String.t]

    @doc """
    Upload all log files which have already been rotated but not yet uploaded.
    """
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
