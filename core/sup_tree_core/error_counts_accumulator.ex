# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.ErrorCountsAccumulator do
  @moduledoc """
  A `GenServer` to hold number of errors reported to each OTP application's alert manager process (implemented by `AntikytheraCore.Alert.Manager`).

  Error counts are reported by `AntikytheraCore.Alert.ErrorCountReporter` installed in `AntikytheraCore.Alert.Manager`.
  The received error counts are stored with `otp_app_name` and the timestamp (in minute).
  Error counts accumulated in this `GenServer` can be fetched via HTTP: see `AntikytheraCore.Handler.SystemInfoExporter.ErrorCount`.

  At the beginning of each minute,
  - newly-received error counts become visible from `get/1` and `get_total/0`, and
  - error counts having too old timestamps are cleaned up from the process state.
  """

  use GenServer
  alias Antikythera.{MapUtil, Time, GearName}

  @type results :: [{Time.t, non_neg_integer}]

  defmodule State do
    defmodule CountByMinute do
      use Croma.SubtypeOfMap, key_module: Time, value_module: Croma.PosInteger
    end

    defmodule CountByMinuteByApp do
      use Croma.SubtypeOfMap, key_module: Croma.Atom, value_module: CountByMinute
    end

    use Croma.Struct, recursive_new?: true, fields: [
      now_minute: Time,
      counts:     CountByMinuteByApp,
    ]

    @type results :: AntikytheraCore.ErrorCountsAccumulator.results

    @minutes_to_retain 10

    defun add(%__MODULE__{now_minute: now_minute, counts: counts} = state, otp_app_name :: v[atom], count :: v[pos_integer]) :: t do
      new_map =
        case counts[otp_app_name] do
          nil -> %{now_minute => count}
          m   -> Map.put(m, now_minute, count)
        end
      %__MODULE__{state | counts: Map.put(counts, otp_app_name, new_map)}
    end

    defun advance_to_next_minute(%__MODULE__{now_minute: now_minute, counts: counts1}, now :: v[Time.t]) :: t do
      next    = Time.truncate_to_minute(now)
      t_old   = Time.shift_minutes(now_minute, -@minutes_to_retain)
      counts2 = MapUtil.map_values(counts1, fn {_, m} -> Map.delete(m, t_old) end)
      %__MODULE__{now_minute: next, counts: counts2}
    end

    defun get(%__MODULE__{now_minute: now_minute, counts: counts}, otp_app_name :: v[:antikythera | GearName.t]) :: results do
      m = Map.get(counts, otp_app_name, %{})
      construct_results(m, now_minute)
    end

    defun get_total(%__MODULE__{now_minute: now_minute, counts: counts}) :: results do
      counts_by_min =
        Enum.flat_map(counts, fn {_, m} -> m end)
        |> Enum.group_by(fn {t, _} -> t end, fn {_, n} -> n end)
        |> MapUtil.map_values(fn {_, l} -> Enum.sum(l) end)
      construct_results(counts_by_min, now_minute)
    end

    defunp construct_results(m :: v[CountByMinute.t], now_minute :: v[Time.t]) :: results do
      Enum.map(-@minutes_to_retain .. -1, fn minus_minute ->
        t = Time.shift_minutes(now_minute, minus_minute)
        case m[t] do
          nil -> {t, 0}
          n   -> {t, n}
        end
      end)
    end
  end

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  @impl true
  def init(:ok) do
    now = Time.now()
    schedule_timer_for_beginning_of_next_minute(now)
    {:ok, %State{now_minute: Time.truncate_to_minute(now), counts: %{}}}
  end

  @impl true
  def handle_call({:get, otp_app_name}, _from, state) do
    {:reply, State.get(state, otp_app_name), state}
  end
  def handle_call(:get_total, _from, state) do
    {:reply, State.get_total(state), state}
  end

  @impl true
  def handle_cast({:submit, otp_app_name, count}, state) do
    {:noreply, State.add(state, otp_app_name, count)}
  end

  @impl true
  def handle_info(:beginning_of_minute, state) do
    now = Time.now()
    schedule_timer_for_beginning_of_next_minute(now)
    {:noreply, State.advance_to_next_minute(state, now)}
  end

  defp schedule_timer_for_beginning_of_next_minute({Time, _ymd, {_h, _m, seconds}, millis}) do
    millis_to_next_minute = 60_000 - (seconds * 1_000 + millis)
    Process.send_after(self(), :beginning_of_minute, millis_to_next_minute)
  end

  #
  # Public API
  #
  defun get(otp_app_name :: v[:antikythera | GearName.t]) :: results do
    GenServer.call(__MODULE__, {:get, otp_app_name})
  end

  defun get_total() :: results do
    GenServer.call(__MODULE__, :get_total)
  end

  defun submit(otp_app_name :: v[:antikythera | GearName.t], count :: v[pos_integer]) :: :ok do
    GenServer.cast(__MODULE__, {:submit, otp_app_name, count})
  end
end
