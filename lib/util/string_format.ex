# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.StringFormat do
  defun pad2(int :: non_neg_integer) :: String.t do
    i when i <  10 -> <<"0", Integer.to_string(i) :: binary-size(1)>>
    i when i < 100 -> Integer.to_string(i)
  end

  defun pad3(int :: non_neg_integer) :: String.t do
    i when i <   10 -> <<"00", Integer.to_string(i) :: binary-size(1)>>
    i when i <  100 -> <<"0" , Integer.to_string(i) :: binary-size(2)>>
    i when i < 1000 -> Integer.to_string(i)
  end
end
