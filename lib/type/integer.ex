# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule SolomonLib.SecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end

defmodule SolomonLib.MilliSecondsSinceEpoch do
  use Croma.SubtypeOfInt, min: 0
end
