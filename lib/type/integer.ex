# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.SecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule Antikythera.MilliSecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule Antikythera.MilliSecondsInGregorian do
  @time_epoch_offset_milliseconds :calendar.datetime_to_gregorian_seconds(
                                    {{1970, 1, 1}, {0, 0, 0}}
                                  ) * 1000
  def time_epoch_offset_milliseconds(), do: @time_epoch_offset_milliseconds

  # This restriction is temporarily expanded for backward compatibility.
  # `- 999` will be removed in the future.
  use Croma.SubtypeOfInt, min: -@time_epoch_offset_milliseconds - 999
end

defmodule Antikythera.MicroSecondsInGregorian do
  @time_epoch_offset_microseconds :calendar.datetime_to_gregorian_seconds(
                                    {{1970, 1, 1}, {0, 0, 0}}
                                  ) * 1000 * 1000
  def time_epoch_offset_microseconds(), do: @time_epoch_offset_microseconds

  use Croma.SubtypeOfInt, min: -@time_epoch_offset_microseconds
end

defmodule Antikythera.GearActionTimeout do
  alias Antikythera.Env

  @max_timeout Application.compile_env!(:antikythera, :gear_action_max_timeout)
  @default_timeout min(Env.gear_action_timeout(), @max_timeout)

  @moduledoc """
  Type of timeout for gear actions in milliseconds.
  A value must be a positive integer less than or equal to `#{@max_timeout}`.
  The maximum value can be configured by `:gear_action_max_timeout` config.
  The default value is determined by `Antikythera.Env.gear_action_timeout/0`,
  or the maximum value if it exceeds the maximum value.
  """

  use Croma.SubtypeOfInt, min: 1, max: @max_timeout, default: @default_timeout
end
