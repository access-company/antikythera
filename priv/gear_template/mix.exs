instance_dep = <%= instance_dep %>

try do
  deps_dir =
    case Application.get_env(:antikythera, :deps_dir) do
      nil ->
        deps_path = Mix.Project.deps_path()
        Application.put_env(:antikythera, :deps_dir, deps_path)
        deps_path
      deps_path -> deps_path
    end
  Code.require_file(Path.join([deps_dir, "antikythera", "mix_common.exs"]))

  defmodule <%= gear_name_camel %>.Mixfile do
    use Antikythera.GearProject, [
      antikythera_instance_dep: instance_dep,
    ]

    defp gear_name(), do: :<%= gear_name %>
    defp version()  , do: "0.0.1"
    defp gear_deps() do
      [
        # List of gear dependencies, e.g.
        # {:some_gear, [git: "git@github.com:some-organization/some_gear.git"]},
      ]
    end
  end
rescue
  _any_error ->
    defmodule AntikytheraGearInitialSetup.Mixfile do
      use Mix.Project

      def project() do
        [
          app:  :just_to_fetch_antikythera_instance_as_a_dependency,
          deps: [unquote(instance_dep)],
        ]
      end
    end
end
