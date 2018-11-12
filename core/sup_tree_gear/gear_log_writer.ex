# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.GearLog.Writer do
  @moduledoc """
  A `GenServer` that writes log messages from each gear's `Logger` process into a gzipped file.

  This `GenServer` is spawned per gear; each of which resides in the gear's supervision tree.

  Although opened log files are regularly rotated, this `GenServer` also supports on-demand log rotation.
  After each successful log rotation, old log file is uploaded to cloud storage.
  """

  use GenServer
  alias Antikythera.{Time, ContextId, GearName}
  alias AntikytheraCore.GearLog.{FileHandle, Level, ContextHelper}
  alias AntikytheraCore.Config.Gear, as: GearConfig
  alias AntikytheraCore.Ets.ConfigCache
  alias AntikytheraCore.Alert.Manager, as: CoreAlertManager
  require AntikytheraCore.Logger, as: L
  alias AntikytheraEal.LogStorage

  defmodule State do
    use Croma.Struct, recursive_new?: true, fields: [
      min_level:   Level,
      file_handle: Croma.Tuple, # FileHandle.t
      empty?:      Croma.Boolean,
      timer:       Croma.Reference,
      uploader:    Croma.TypeGen.nilable(Croma.Pid),
    ]
  end

  def start_link([gear_name, logger_name]) do
    opts = if logger_name, do: [name: logger_name], else: []
    %GearConfig{log_level: min_level} = ConfigCache.Gear.read(gear_name)
    GenServer.start_link(__MODULE__, {gear_name, min_level}, opts)
  end

  @impl true
  def init({gear_name, min_level}) do
    handle = FileHandle.open(AntikytheraCore.Path.gear_log_file_path(gear_name))
    timer = arrange_next_rotation(nil)
    {:ok, %State{min_level: min_level, file_handle: handle, empty?: true, timer: timer}}
  end

  @impl true
  def handle_cast({_, level, _, _} = gear_log,
                  %State{min_level: min_level, file_handle: handle, timer: timer} = state) do
    if Level.write_to_log?(min_level, level) do
      case FileHandle.write(handle, gear_log) do
        {:kept_open, new_handle} -> {:noreply, %State{state | file_handle: new_handle, empty?: false}}
        {:rotated  , new_handle} ->
          # Log file is just rotated as its size has exceeded the upper limit.
          # Note that the current message is written to the newly-opened log file and thus it's not empty.
          new_timer = arrange_next_rotation(timer)
          {:noreply, %State{state | file_handle: new_handle, empty?: false, timer: new_timer}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:set_min_level, level}, state) do
    {:noreply, %State{state | min_level: level}}
  end
  def handle_cast({:rotate_and_start_upload, gear_name}, state1) do
    %State{uploader: uploader} = state2 = rotate(state1)
    if uploader do
      # Currently an uploader is working and recent log files will be uploaded => do nothing
      {:noreply, state2}
    else
      {pid, _ref} = spawn_monitor(LogStorage, :upload_rotated_logs, [gear_name])
      {:noreply, %State{state2 | uploader: pid}}
    end
  end

  @impl true
  def handle_info(:rotate, state) do
    {:noreply, rotate(state)}
  end
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, %State{state | uploader: nil}}
  end

  defp rotate(%State{file_handle: handle, empty?: empty?, timer: timer} = state0) do
    new_timer = arrange_next_rotation(timer)
    state1 = %State{state0 | timer: new_timer}
    if empty? do
      state1
    else
      %State{state1 | file_handle: FileHandle.rotate(handle), empty?: true}
    end
  end

  @impl true
  def terminate(_reason, %State{file_handle: handle}) do
    FileHandle.close(handle)
  end

  @rotate_interval (if Mix.env() == :test, do: 500, else: 7_200_000)

  defp arrange_next_rotation(timer) do
    if timer do
      Process.cancel_timer(timer)
    end
    Process.send_after(self(), :rotate, @rotate_interval)
  end

  #
  # Public API
  #
  for level <- [:debug, :info, :error] do
    defun unquote(level)(logger_name :: v[atom], msg :: v[String.t]) :: :ok do
      unquote(level)(logger_name, Time.now(), ContextHelper.get!(), msg)
    end

    if level == :error do
      # Restrict `logger_name` to `atom` instead of `GenServer.server` for alert manager name resolution
      defun unquote(level)(logger_name :: v[atom], t :: v[Time.t], context_id :: v[ContextId.t], msg :: v[String.t]) :: :ok do
        # The caller process is responsible for sending an error message to the gear's `AlertManager`,
        # in order to keep `GearLog.Writer` decoupled from the alerting functionality.
        CoreAlertManager.notify(resolve_alert_manager_name(logger_name), body(msg, context_id), t)
        GenServer.cast(logger_name, {t, unquote(level), context_id, msg})
      end
    else
      defun unquote(level)(logger_name :: v[atom], t :: v[Time.t], context_id :: v[ContextId.t], msg :: v[String.t]) :: :ok do
        GenServer.cast(logger_name, {t, unquote(level), context_id, msg})
      end
    end
  end

  defun set_min_level(gear_name :: v[GearName.t], level :: v[Level.t]) :: :ok do
    case logger_name(gear_name) do
      nil  -> :ok
      name -> GenServer.cast(name, {:set_min_level, level})
    end
  end

  defun rotate_and_start_upload_in_all_nodes(gear_name :: v[GearName.t]) :: :abcast do
    case logger_name(gear_name) do
      nil  -> :ok
      name -> GenServer.abcast(name, {:rotate_and_start_upload, gear_name})
    end
  end

  defunp logger_name(gear_name :: v[GearName.t]) :: nil | atom do
    try do
      AntikytheraCore.GearModule.logger(gear_name)
    rescue
      ArgumentError ->
        L.info("#{gear_name} isn't installed")
        nil
    end
  end

  defunp resolve_alert_manager_name(logger_name :: v[atom]) :: atom do
    [gear_top_module_str, "Logger"] = Module.split(logger_name)
    Module.safe_concat(gear_top_module_str, "AlertManager")
  end

  defp body(message, context_id) do
    "#{message}\nContext: #{context_id}"
  end
end
