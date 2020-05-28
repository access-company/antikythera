# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.EnumUtilTest do
  use Croma.TestCase

  test "map_with_context/3" do
    # if previous item was an even number, double the current item. otherwise keep the current item
    f = fn item, context ->
      new_context = rem(item, 2) == 0

      new_item =
        case context do
          true -> item * 2
          false -> item
        end

      {new_item, new_context}
    end

    assert EnumUtil.map_with_context([1, 2, 3, 4, 5, 6], true, f) == [2, 2, 6, 4, 10, 6]
    assert EnumUtil.map_with_context([2, 2, 4, 4, 6, 6], false, f) == [2, 4, 8, 8, 12, 12]
    assert EnumUtil.map_with_context([1, 1, 2, 3, 5, 8], true, f) == [2, 1, 2, 6, 5, 8]
    assert EnumUtil.map_with_context([], true, f) == []
    assert EnumUtil.map_with_context(1..6, true, f) == [2, 2, 6, 4, 10, 6]

    catch_error(EnumUtil.map_with_context("non_enum", true, f))
    catch_error(EnumUtil.map_with_context(["callback", "incompatible", "items"], true, f))
    catch_error(EnumUtil.map_with_context([1, 2, 3], "unsupported context", f))
  end
end
