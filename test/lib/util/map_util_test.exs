# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.MapUtilTest do
  use Croma.TestCase

  test "difference/2" do
    m1 = %{a: 1, b: 2, c: 3}
    m2 = %{a: 1, c: 2, d: 4, e: 5}

    assert MapUtil.difference(%{}, %{}) == {%{}, %{}, %{}}
    assert MapUtil.difference(m1, %{}) == {m1, %{}, %{}}
    assert MapUtil.difference(%{}, m2) == {%{}, %{}, m2}

    {r1, r2, r3} = MapUtil.difference(m1, m2)
    assert r1 == %{b: 2}
    assert r2 == %{c: {3, 2}}
    assert r3 == %{d: 4, e: 5}
  end

  test "update_existing/3" do
    f = fn x -> x + 1 end

    assert MapUtil.update_existing(%{a: 1}, :a, f) == {:ok, %{a: 2}}
    assert MapUtil.update_existing(%{a: 1}, :b, f) == :error
    assert MapUtil.update_existing(%{}, :a, f) == :error
    # use `NestedMap.update_existing_in/3`
    assert MapUtil.update_existing(%{a: %{b: 1}}, [:a, :b], f) == :error

    catch_error(MapUtil.update_existing(%{a: "non_int"}, :a, f))
  end
end
