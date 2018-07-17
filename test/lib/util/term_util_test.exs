# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.TermUtilTest do
  use Croma.TestCase
  use ExUnitProperties

  defp assert_term_size(t) do
    size = TermUtil.size(t)
    assert is_integer(size)
    assert size >= 0
    assert TermUtil.size_smaller_or_equal?(t, size)
    if size > 0 do
      refute TermUtil.size_smaller_or_equal?(t, size - 1)
    end
    size
  end

  property "size of any term can be computed" do
    check all t <- term() do
      assert_term_size(t)
    end
  end

  test "should take binary size into account" do
    [s0, s1, s2] = Enum.map(["", "a", "ab"], &TermUtil.size/1)
    assert s0 < s1
    assert s1 < s2
  end

  defmodule SomeStruct do
    defstruct []
  end

  test "should correctly compute size of struct" do
    assert_term_size(%SomeStruct{})
  end
end
