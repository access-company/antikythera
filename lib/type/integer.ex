# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.SecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule Antikythera.MilliSecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end
