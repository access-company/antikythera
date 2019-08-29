# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.FileHandle do
  alias Antikythera.{Time, ContextId}
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

  @opaque t :: {Path.t, Time.t, File.io_device, boolean}

  defun open(file_path :: Path.t, opts :: Keyword.t \\ []) :: t do
    write_to_terminal? = Keyword.get(opts, :write_to_terminal, determine_write_to_terminal())
    :ok = File.mkdir_p(Path.dirname(file_path))
    if File.exists?(file_path) do
      rename(file_path)
    end
    {file_path, Time.now(), open_file(file_path), write_to_terminal?}
  end

  defun write({file_path, last_checked_at, io_device, write_to_terminal?} = handle   :: t,
              {now, _, _, _}                                              = gear_log :: Message.t) :: {:kept_open | :rotated, t} do
    if SizeCheck.check_now?(now, last_checked_at) do
      if SizeCheck.exceeds_limit?(file_path) do
        {_, _, new_io_device, _} = new_handle = rotate(handle)
        do_write(new_io_device, gear_log, write_to_terminal?)
        {:rotated, new_handle}
      else
        do_write(io_device, gear_log, write_to_terminal?)
        {:kept_open, {file_path, now, io_device, write_to_terminal?}}
      end
    else
      do_write(io_device, gear_log, write_to_terminal?)
      {:kept_open, handle}
    end
  end

  defunp do_write(io_device :: :file.io_device, {time, level, context_id, msg} :: Message.t, write_to_terminal? :: boolean) :: :ok do
    prefix = log_prefix(time, level, context_id)
    formatted_lines_str = String.split(msg, "\n", trim: true)
      |> Enum.reduce("", fn(s, acc) -> acc <> prefix <> s <> "\n" end)
    :ok = IO.binwrite(io_device, formatted_lines_str)
    if write_to_terminal?, do: write_debug_log(level, formatted_lines_str), else: :ok
  end

  defunp log_prefix(time :: v[Time.t], level :: v[Level.t], context_id :: v[ContextId.t]) :: String.t do
    Time.to_iso_timestamp(time) <> " [" <> Atom.to_string(level) <> "] context=" <> context_id <> " "
  end

  defun rotate({file_path, _, io_device, write_to_terminal?} :: t) :: t do
    :ok = File.close(io_device)
    rename(file_path)
    {file_path, Time.now(), open_file(file_path), write_to_terminal?}
  end

  defunp open_file(file_path :: Path.t) :: File.io_device do
    File.open!(file_path, [:write, :compressed])
  end

  defun close({_, _, io_device, _} :: t) :: :ok do
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

  defunp write_debug_log(level :: v[Level.t], formatted :: v[String.t]) :: :ok do
    case level do
      :error -> IO.ANSI.red() <> formatted <> IO.ANSI.reset()
      :debug -> IO.ANSI.cyan() <> formatted <> IO.ANSI.reset()
      _      -> formatted
    end
    |> IO.binwrite()
  end

  def determine_write_to_terminal() do
    !Antikythera.Env.compiling_for_release?() && Mix.env() == :dev
  end
end
