# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.ZipTest do
  use Croma.TestCase
  alias Antikythera.{Tmpdir, Zip}

  setup do
    on_exit(&:meck.unload/0)
  end

  @context Antikythera.Test.ConnHelper.make_conn().context

  describe "Zip.zip/3" do
    test "returns path of resulting archive" do
      [
        {[],            ["/src.txt"],         "/src.txt"},
        {["/src_dir/"], [],                   "/src_dir/"},
        {["/src_dir/"], ["/src_dir/src.txt"], "/src_dir/src.txt"},
      ]
      |> Enum.each(fn {dirs_to_create, files_to_write, path_to_archive} ->
        Tmpdir.make(@context, fn tmpdir ->
          zip_path = tmpdir <> "/archive.zip"
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> &1))
          Enum.each(files_to_write, &File.write!(tmpdir <> &1, "text"))
          assert Zip.zip(@context, zip_path, tmpdir <> path_to_archive) == {:ok, zip_path}
        end)
      end)
    end

    test "returns path of resulting archive encrypted with password" do
      [
        {[],            ["/src.txt"],         "/src.txt"},
        {["/src_dir/"], [],                   "/src_dir/"},
        {["/src_dir/"], ["/src_dir/src.txt"], "/src_dir/src.txt"},
      ]
      |> Enum.each(fn {dirs_to_create, files_to_write, path_to_archive} ->
        Tmpdir.make(@context, fn tmpdir ->
          zip_path = tmpdir <> "/archive.zip"
          Enum.each(dirs_to_create, &File.mkdir_p!(tmpdir <> &1))
          Enum.each(files_to_write, &File.write!(tmpdir <> &1, "text"))
          assert Zip.zip(@context, zip_path, tmpdir <> path_to_archive, [encryption: true, password: "password"]) == {:ok, zip_path}
        end)
      end)
    end
  end
end
