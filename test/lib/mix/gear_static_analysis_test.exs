defmodule Mix.Tasks.Compile.GearStaticAnalysisTest do
  use Croma.TestCase

  setup do
    :meck.expect(Mix.Project, :config, fn ->
      [{:antikythera_gear, [use_antikythera_internal_modules?: false]} | :meck.passthrough([])]
    end)

    on_exit(fn -> :meck.unload(Mix.Project) end)
  end

  defp make_tmp_ex_file_path(%{tmp_dir: tmp_dir} = _context) do
    ex_file_path = Path.join(tmp_dir, "test.ex")
    [ex_file_path: ex_file_path]
  end

  # Gear name is `antikythera` in the following tests
  describe "find_issues_in_file/1" do
    @describetag :tmp_dir

    setup :make_tmp_ex_file_path

    test "should detect naming module which is not prefixed with the gear name", %{
      ex_file_path: ex_file_path
    } do
      File.write!(ex_file_path, """
      defmodule Foo do
        def bar(), do: :buz
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "module name `Foo` is not prefixed with the gear name"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect implementing non-gear-specific protocol for non-gear-specific type", %{
      ex_file_path: ex_file_path
    } do
      File.write!(ex_file_path, """
      defimpl Foo, for: Bar do
        def bar(), do: :buz
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "implementing non-gear-specific protocol for non-gear-specific type can affect other projects and is thus prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect directly using Gettext", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        use Gettext
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "directly invoking `use Gettext` is not allowed (`use Antikythera.Gettext` instead)"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect disturbing execution of ErlangVM", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: System.halt()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "disturbing execution of ErlangVM is strictly prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect writing to STDOUT/STDERR", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: IO.inspect(:hello)
      end
      """)

      assert [
               {:warning, ^ex_file_path, _meta,
                "writing to STDOUT/STDERR is not allowed in prod environment (use each gear's logger instead)"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect spawning processes", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: Task.async(fn -> :ok end)
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "spawning processes in gear's code is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect calling :os.cmd/1", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: :os.cmd("ls")
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "calling :os.cmd/1 in gear's code is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect calling System.cmd/3", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: System.cmd("ls", [], into: IO.stream())
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "calling System.cmd/3 in gear's code is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect spawning processes by local call", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: spawn(fn -> :ok end)
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "spawning processes in gear's code is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect using AntikytheraCore.*", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: AntikytheraCore.Ets.init_all()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "direct use of `AntikytheraCore.*` is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect using AntikytheraEal.*", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: AntikytheraEal.AlertMailer.MemoryInbox.clean()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "direct use of `AntikytheraEal.*` is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect using AntikytheraLocal.*", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: AntikytheraLocal.NodeName.get()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta, "direct use of `AntikytheraLocal.*` is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect using Antikythera.Test.*", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: Antikythera.Test.Config.init()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "using `Antikythera.Test.*` in production code is prohibited"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect using Antikythera.Mix.Task.*", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: Antikythera.Mix.Task.prepare_antikythera_instance()
      end
      """)

      assert [
               {:error, ^ex_file_path, _meta,
                "`Antikythera.Mix.Task.*` can only be used in mix tasks"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end

    test "should detect directly using :hackney", %{ex_file_path: ex_file_path} do
      File.write!(ex_file_path, """
      defmodule Antikythera.Dummy do
        def foo(), do: :hackney.get("https://example.com")
      end
      """)

      assert [
               {:warning, ^ex_file_path, _meta,
                "directly depending on `:hackney` is not allowed (for `Antikythera.Httpc` use other options; for initialization of HTTP client library in your mix tasks use `Antikythera.Mix.Task.prepare_antikythera_instance/0`)"}
             ] = GearStaticAnalysis.find_issues_in_file(ex_file_path)
    end
  end
end
