# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.NestedMapTest do
  use Croma.TestCase, alias_as: M

  test "deep_merge/2" do
    assert M.deep_merge(%{}, %{}) == %{}
    assert M.deep_merge(%{a: 10}, %{b: 5}) == %{a: 10, b: 5}
    assert M.deep_merge(%{a: 10}, %{a: %{b: 3}}) == %{a: %{b: 3}}

    assert M.deep_merge(%{a: %{b: %{x: 1, y: 2}, c: %{z: 3}}}, %{a: %{b: %{y: 3, z: 4}}}) == %{
             a: %{b: %{x: 1, y: 3, z: 4}, c: %{z: 3}}
           }
  end

  test "force_upate/3" do
    f = fn
      nil -> 1
      x -> x + 1
    end

    catch_error(M.force_update(%{}, [], f))

    assert M.force_update(%{}, [:a], f) == %{a: 1}
    assert M.force_update(%{a: 3}, [:a], f) == %{a: 4}
    assert M.force_update(%{a: %{b: %{c: 3}}}, [:a, :b, :c], f) == %{a: %{b: %{c: 4}}}
    assert M.force_update(%{d: %{e: 1}}, [:a, :b, :c], f) == %{a: %{b: %{c: 1}}, d: %{e: 1}}
  end

  test "update_existing_in/3" do
    f = fn x -> x + 1 end

    assert M.update_existing_in(%{a: %{b: %{c: 1}}}, [:a, :b, :c], f) ==
             {:ok, %{a: %{b: %{c: 2}}}}

    assert M.update_existing_in(%{a: %{b: %{c: 1}}}, [:a, :b, :d], f) == :error
    assert M.update_existing_in(%{d: %{e: %{f: 1}}}, [:a, :b, :c], f) == :error
    assert M.update_existing_in(%{a: %{b: 1}}, [:a, :b, :c], f) == :error
    assert M.update_existing_in(%{}, [:a, :b, :c], f) == :error

    catch_error(M.update_existing_in(%{a: %{b: %{c: 1}}}, [], f))
    catch_error(M.update_existing_in(%{}, [], f))

    # callback error should be thrown out
    catch_error(M.update_existing_in(%{a: %{b: "non_int"}}, [:a, :b], f))
  end
end
