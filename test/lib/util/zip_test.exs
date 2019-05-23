# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ZipTest do
  use Croma.TestCase
  alias AntikytheraCore.TmpdirTracker
  alias Antikythera.{Tmpdir, Zip}

  setup do
    on_exit(&:meck.unload/0)
  end

  @context Antikythera.Test.ConnHelper.make_conn().context
  @tmpdir   "/tmpdir"
  @src_path "/tmpdir/src.txt"
  @zip_path "/tmpdir/archive.zip"

  describe "Zip.zip/3" do
    test "returns path of resulting archive" do
      [
        {[],            ["/src.txt"],         "/src.txt"},
        {["/src_dir/"], [],                   "/src_dir/"},
        {["/src_dir/"], ["/src_dir/src.txt"], "/src_dir/src.txt"},
      ]
      |> Enum.each(fn {dirs_to_create, files_to_create, src_path} ->
        Tmpdir.make(@context, fn tmpdir ->
          zip_path = tmpdir <> "/archive.zip"
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> &1))
          Enum.each(files_to_create, &File.write!(tmpdir <> &1, "text"))
          assert Zip.zip(@context, zip_path, tmpdir <> src_path) == {:ok, zip_path}
        end)
      end)
    end

    test "returns path of resulting archive encrypted with password" do
      [
        {[],            ["/src.txt"],         "/src.txt"},
        {["/src_dir/"], [],                   "/src_dir/"},
        {["/src_dir/"], ["/src_dir/src.txt"], "/src_dir/src.txt"},
      ]
      |> Enum.each(fn {dirs_to_create, files_to_create, src_path} ->
        Tmpdir.make(@context, fn tmpdir ->
          zip_path = tmpdir <> "/archive.zip"
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> &1))
          Enum.each(files_to_create, &File.write!(tmpdir <> &1, "text"))
          assert Zip.zip(@context, zip_path, tmpdir <> src_path, [encryption: true, password: "password"]) == {:ok, zip_path}
        end)
      end)
    end

    test "returns error when tmpdir is not found" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:error, {:not_found, %{}}} end)
      :meck.expect(File, :exists?, fn _ -> flunk() end)
      assert Zip.zip(@context, @zip_path, @src_path) == {:error, {:not_found, %{}}}
    end

    test "returns error when src is outside tmpdir" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      src_path = "/another_dir/src.txt"
      :meck.expect(File, :exists?, fn _ -> flunk() end)
      assert Zip.zip(@context, @zip_path, src_path) == {:error, {:permission_denied, %{tmpdir: @tmpdir, path: src_path}}}
    end

    test "returns error when resulting archive is outside tmpdir" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      zip_path = "/another_dir/archive.zip"
      :meck.expect(File, :exists?, fn _ -> flunk() end)
      assert Zip.zip(@context, zip_path, @src_path) == {:error, {:permission_denied, %{tmpdir: @tmpdir, path: zip_path}}}
    end

    test "returns error when src is not found" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :exists?, fn
        @zip_path -> false
        @src_path -> false
      end)
      assert Zip.zip(@context, @zip_path, @src_path) == {:error, {:not_found, %{path: @src_path}}}
    end

    test "returns error when resulting archive already exists" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :exists?, fn
        @zip_path -> true
        @src_path -> true
      end)
      assert Zip.zip(@context, @zip_path, @src_path) == {:error, {:already_exists, %{path: @zip_path}}}
    end

    test "returns error when encryption is disabled and password exists" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :exists?, fn
        @zip_path -> false
        @src_path -> true
      end)
      assert Zip.zip(@context, @zip_path, @src_path, [encryption: false, password: "password"]) == {:error, {:argument_error, %{encryption: false, password: "password"}}}
    end

    test "returns error when shell command fails" do
      Tmpdir.make(@context, fn tmpdir ->
        zip_path = tmpdir <> "/archive.zip"
        src_path = tmpdir <> "/src.txt"
        :meck.expect(File, :exists?, fn
          ^zip_path -> false
          ^src_path -> true
        end)
        assert {:error, {:shell_runtime_error, _}} = Zip.zip(@context, zip_path, src_path)
      end)
    end
  end
end
