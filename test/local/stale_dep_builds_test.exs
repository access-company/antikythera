# Copyright(c) 2015-2026 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraLocal.StaleDepBuildsTest do
  use Croma.TestCase
  import ExUnit.CaptureIO, only: [capture_io: 1]

  @moduletag :tmp_dir

  defp write_lock!(dir) do
    File.write!(Path.join(dir, "mix.lock"), """
    %{
      "certifi": {:hex, :certifi, "2.18.0", "checksum", [:rebar3], [], "hexpm", "outer_checksum"},
      "croma": {:hex, :croma, "0.13.0", "checksum", [:mix], [], "hexpm", "outer_checksum"},
      "my_renamed_dep": {:hex, :my_renamed_package, "1.0.0", "checksum", [:mix], [], "hexpm", "outer_checksum"},
      "my_git_dep": {:git, "git@github.com:example/my_git_dep.git", "0123456789abcdef", []},
    }
    """)
  end

  defp write_app_file!(dir, build_dir, env, app, vsn) do
    ebin_dir = Path.join([dir, build_dir, env, "lib", "#{app}", "ebin"])
    File.mkdir_p!(ebin_dir)
    content = :io_lib.format("~p.~n", [{:application, app, [vsn: String.to_charlist(vsn)]}])
    File.write!(Path.join(ebin_dir, "#{app}.app"), content)
    Path.dirname(ebin_dir)
  end

  test "remove/1 should remove builds whose versions differ from mix.lock under both build dirs",
       %{tmp_dir: dir} do
    write_lock!(dir)
    stale_test = write_app_file!(dir, "_build", "test", :certifi, "2.15.0")
    stale_dev = write_app_file!(dir, "_build", "dev", :certifi, "2.15.0")
    stale_local = write_app_file!(dir, "_build_local", "prod", :certifi, "2.15.0")
    unreadable = write_app_file!(dir, "_build", "dev", :croma, "0.13.0")
    File.write!(Path.join([unreadable, "ebin", "croma.app"]), "garbage")
    without_vsn = write_app_file!(dir, "_build_local", "dev", :croma, "0.13.0")
    File.write!(Path.join([without_vsn, "ebin", "croma.app"]), "{application, croma, []}.\n")
    stale_renamed = write_app_file!(dir, "_build", "test", :my_renamed_dep, "0.9.0")
    up_to_date = write_app_file!(dir, "_build", "test", :croma, "0.13.0")
    git_dep = write_app_file!(dir, "_build", "test", :my_git_dep, "0.1.0")
    not_in_lock = write_app_file!(dir, "_build", "test", :my_gear, "0.0.1")
    without_app_file = Path.join([dir, "_build_local", "prod", "lib", "croma"])
    File.mkdir_p!(without_app_file)

    output = capture_io(fn -> assert StaleDepBuilds.remove(dir) == :ok end)

    refute File.exists?(stale_test)
    refute File.exists?(stale_dev)
    refute File.exists?(stale_local)
    refute File.exists?(unreadable)
    refute File.exists?(without_vsn)
    refute File.exists?(stale_renamed)
    assert File.exists?(up_to_date)
    assert File.exists?(git_dep)
    assert File.exists?(not_in_lock)
    assert File.exists?(without_app_file)
    assert output =~ ~s|Removing stale build of certifi (built: "2.15.0", locked: 2.18.0)|
    assert output =~ ~s|Removing stale build of croma (built: nil, locked: 0.13.0)|
  end
end
