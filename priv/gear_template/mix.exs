instance_dep = <%= instance_dep %>

try do
  deps_dir =
    # Gears use mix settings of both antikythera and antikythera instance and thus paths to these projects must be available.
    # We have to remember `deps_path()` so that gear dependencies with `:path` option can reach these projects.
    case Application.get_env(:antikythera, :compile_time_deps_dir) do
      nil -> # this gear project is the toplevel mix project
        deps_path = Mix.Project.deps_path()
        Application.put_env(:antikythera, :compile_time_deps_dir, deps_path)
        deps_path
      deps_path -> deps_path # this gear project is used by another gear as a gear dependency
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
