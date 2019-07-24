# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.SecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule Antikythera.MilliSecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule Antikythera.MilliSecondsInGregorian do
  @time_epoch_offset_milliseconds (:calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}) * 1000)
  def time_epoch_offset_milliseconds(), do: @time_epoch_offset_milliseconds

  # This restriction is temporarily expanded for backward compatibility.
  # `- 999` will be removed in the future.
  use Croma.SubtypeOfInt, min: -@time_epoch_offset_milliseconds - 999
end
