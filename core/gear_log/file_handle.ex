# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.FileHandle do
  alias Antikythera.Time
  alias AntikytheraCore.GearLog.{Level, Message}

  defmodule SizeCheck do
    @interval (if Antikythera.Env.compiling_for_release?(), do: 60_000, else: 100)
    @max_size (if Mix.env() == :test, do: 4_096, else: 104_857_600) # 100MB

    defun check_now?(now :: v[Time.t], last_checked_at :: v[Time.t]) :: boolean do
      @interval <= Time.diff_milliseconds(now, last_checked_at)
    end

    defun exceeds_limit?(file_path :: Path.t) :: boolean do
      %File.Stat{size: size} = File.stat!(file_path)
      @max_size < size
    end
  end

  @opaque t :: {Path.t, Time.t, File.io_device}

  defun open(file_path :: Path.t) :: t do
    :ok = File.mkdir_p(Path.dirname(file_path))
    if File.exists?(file_path) do
      rename(file_path)
    end
    {file_path, Time.now(), open_file(file_path)}
  end

  defun write({file_path, last_checked_at, io_device} = handle   :: t,
              {now, _, _, _}                          = gear_log :: Message.t) :: {:kept_open | :rotated, t} do
    if SizeCheck.check_now?(now, last_checked_at) do
      if SizeCheck.exceeds_limit?(file_path) do
        {_, _, new_io_device} = new_handle = rotate(handle)
        do_write(new_io_device, gear_log)
        {:rotated, new_handle}
      else
        do_write(io_device, gear_log)
        {:kept_open, {file_path, now, io_device}}
      end
    else
      do_write(io_device, gear_log)
      {:kept_open, handle}
    end
  end

  defunp do_write(io_device :: :file.io_device, {time, level, context_id, msg} :: Message.t) :: :ok do
    try do
      prefix = log_prefix(time, level, context_id)
      formatted_lines_str = String.split(msg, "\n", trim: true) |> Enum.map_join(&(prefix <> &1 <> "\n"))
      IO.write(io_device, formatted_lines_str)
      write_debug_log(level, formatted_lines_str)
    rescue
      _ in ErlangError -> write_debug_log(level, "The write process was skipped because it received malformed data.\n")
    end
  end

  defunp log_prefix(time :: v[Time.t], level :: v[Level.t], context_id :: v[String.t]) :: String.t do
    Time.to_iso_timestamp(time) <> " [#{level}] context=#{context_id} "
  end

  defun rotate({file_path, _, io_device} :: t) :: t do
    :ok = File.close(io_device)
    rename(file_path)
    {file_path, Time.now(), open_file(file_path)}
  end

  defunp open_file(file_path :: Path.t) :: File.io_device do
    File.open!(file_path, [:write, {:encoding, :utf8}, :compressed])
  end

  defun close({_, _, io_device} :: t) :: :ok do
    :ok = File.close(io_device)
  end

  defunp rename(file_path :: Path.t) :: :ok do
    :ok = File.rename(file_path, rotated_file_path(file_path))
  end

  defunp rotated_file_path(base_file_path :: Path.t) :: Path.t do
    import Antikythera.StringFormat
    {Time, {y, mon, d}, {h, minute, s}, _ms} = Time.now()
    now_str_with_ext = "#{y}#{pad2(mon)}#{pad2(d)}#{pad2(h)}#{pad2(minute)}#{pad2(s)}.gz"
    String.replace(base_file_path, ~R/gz\z/, now_str_with_ext)
  end

  if Antikythera.Env.compiling_for_release?() do
    defunp write_debug_log(_ :: Level.t, _ :: String.t) :: :ok, do: :ok
  else
    defunp write_debug_log(level :: v[Level.t], formatted :: v[String.t]) :: :ok do
      if Mix.env() == :dev do
        case level do
          :error -> IO.ANSI.red() <> formatted <> IO.ANSI.reset()
          :debug -> IO.ANSI.cyan() <> formatted <> IO.ANSI.reset()
          _      -> formatted
        end
        |> IO.write()
      else
        :ok # don't put logs during tests
      end
    end
  end
end
