# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ZipTest do
  use Croma.TestCase
  alias AntikytheraCore.TmpdirTracker
  alias Antikythera.Tmpdir

  setup do
    on_exit(&:meck.unload/0)
  end

  @context Antikythera.Test.ConnHelper.make_conn().context
  @tmpdir   "/tmpdir"
  @src_path "src.txt"
  @zip_path "archive.zip"
  @src_full_path @tmpdir <> "/" <> @src_path
  @zip_full_path @tmpdir <> "/" <> @zip_path

  describe "Zip.FileName.valid?/1" do
    test "Exclude paths suffixed with /" do
      assert Zip.FileName.valid?("file.ex")
      assert Zip.FileName.valid?("file.")
      refute Zip.FileName.valid?("file\n")
      refute Zip.FileName.valid?("dir/")
      refute Zip.FileName.valid?("dir/.")
      refute Zip.FileName.valid?("dir/..")
      assert Zip.FileName.valid?("dir/...")
    end
  end

  describe "Zip.zip/3" do
    test "returns path of resulting archive" do
      for(
        {dirs_to_create, files_to_create, src_path} <- [
          {[],           ["src.txt"],         "src.txt"},
          {["src_dir/"], [],                  "src_dir/"},
          {["src_dir/"], ["src_dir/src.txt"], "src_dir/src.txt"},
        ],
        zip_path <- [
          "archive.zip",
          "zip_dir/archive.zip",
        ]
      ) do
        Tmpdir.make(@context, fn tmpdir ->
          zip_full_path = tmpdir <> "/" <> zip_path
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> "/" <> &1))
          Enum.each(files_to_create, &File.write!(tmpdir <> "/" <> &1, "text"))
          assert Zip.zip(@context, tmpdir, zip_path, src_path) == {:ok, zip_full_path}
          assert File.exists?(zip_full_path)
        end)
      end
    end

    test "returns path of resulting archive with .zip if no extension was assigned" do
      Tmpdir.make(@context, fn tmpdir ->
        zip_path = "no_extension"
        zip_full_path = tmpdir <> "/" <> zip_path <> ".zip"
        src_full_path = tmpdir <> "/" <> @src_path
        File.write!(src_full_path, "text")
        assert Zip.zip(@context, tmpdir, zip_path, @src_path) == {:ok, zip_full_path}
        assert File.exists?(zip_full_path)
      end)
    end

    test "returns path of resulting archive encrypted with password" do
      for(
        {dirs_to_create, files_to_create, src_path} <- [
          {[],           ["src.txt"],         "src.txt"},
          {["src_dir/"], [],                  "src_dir/"},
          {["src_dir/"], ["src_dir/src.txt"], "src_dir/src.txt"},
        ],
        zip_path <- [
          "archive.zip",
          "zip_dir/archive.zip",
        ]
      ) do
        Tmpdir.make(@context, fn tmpdir ->
          zip_full_path = tmpdir <> "/" <> zip_path
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> "/" <> &1))
          Enum.each(files_to_create, &File.write!(tmpdir <> "/" <> &1, "text"))
          assert Zip.zip(@context, tmpdir, zip_path, src_path, [encryption: true, password: "password"]) == {:ok, zip_full_path}
          assert File.exists?(zip_full_path)
        end)
      end
    end

    test "returns error when a directory exists with same name as resulting archive" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :dir?, fn
        @tmpdir        -> true
        @zip_full_path -> true
      end)
      assert Zip.zip(@context, @tmpdir, @zip_path, @src_path) == {:error, {:is_dir, %{path: @zip_full_path}}}
    end

    test "returns error when input file name is suffixed with / while it is a file" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      invalid_src_path = @src_path <> "/"
      :meck.expect(File, :exists?, fn @src_full_path -> true end)
      :meck.expect(File, :dir?, fn
        @tmpdir        -> true
        @zip_full_path -> false
        @src_full_path -> false
      end)
      assert Zip.zip(@context, @tmpdir, @zip_path, invalid_src_path) == {:error, {:not_dir, %{path: @src_full_path}}}
    end

    test "returns error when tmpdir is not found" do
      :meck.expect(File, :exists?, fn _ -> flunk() end)
      assert Zip.zip(@context, @tmpdir, @zip_path, @src_path) == {:error, :not_found}
    end

    test "returns error when src is outside tmpdir" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      invalid_src_path = "/another_dir" <> "/" <> @src_path
      assert Zip.zip(@context, @tmpdir, @zip_path, invalid_src_path) == {:error, {:permission_denied, %{tmpdir: @tmpdir, path: invalid_src_path}}}
    end

    test "returns error when resulting archive is outside tmpdir" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      invalid_zip_path = "/another_dir" <> "/" <> @zip_path
      assert Zip.zip(@context, @tmpdir, invalid_zip_path, @src_path) == {:error, {:permission_denied, %{tmpdir: @tmpdir, path: invalid_zip_path}}}
    end

    test "returns error when src is not found" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :dir?, fn
        @tmpdir        -> true
        @zip_full_path -> false
        @src_full_path -> false
      end)
      assert Zip.zip(@context, @tmpdir, @zip_path, @src_path) == {:error, {:not_found, %{path: @src_full_path}}}
    end

    test "returns error when zip path is through existing file name" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      invalid_zip_path = @src_path <> "/" <> "beneath_the_file.zip"
      invalid_zip_full_path = @tmpdir <> "/" <> invalid_zip_path
      :meck.expect(File, :dir?, fn
        @tmpdir                -> true
        ^invalid_zip_full_path -> false
      end)
      :meck.expect(File, :mkdir_p, fn @src_full_path -> {:error, :eexist} end)
      assert Zip.zip(@context, @tmpdir, invalid_zip_path, @src_path) == {:error, {:not_dir, %{path: invalid_zip_full_path}}}
    end

    test "returns error when encryption is disabled and password exists" do
      :meck.expect(TmpdirTracker, :get, fn _ -> {:ok, @tmpdir} end)
      :meck.expect(File, :dir?, fn
        @tmpdir        -> true
        @zip_full_path -> false
        @src_full_path -> false
      end)
      :meck.expect(File, :exists?, fn @src_full_path -> true end)
      [
        {[encryption: false, password: "password"], %{encryption: false, password: "password"}},
        {[encryption: true,  password: ""],         %{encryption: true,  password: ""}},
        {[encryption: true],                        %{encryption: true}},
      ] |> Enum.each(fn {invalid_args, expected} ->
        assert Zip.zip(@context, @tmpdir, @zip_path, @src_path, invalid_args) == {:error, {:argument_error, expected}}
      end)
    end

    test "returns error when shell command fails" do
      Tmpdir.make(@context, fn tmpdir ->
        src_full_path = tmpdir <> "/" <> @src_path
        :meck.expect(File, :exists?, fn ^src_full_path -> true end)
        assert {:error, :shell_runtime_error} = Zip.zip(@context, tmpdir, @zip_path, @src_path)
      end)
    end
  end
end
