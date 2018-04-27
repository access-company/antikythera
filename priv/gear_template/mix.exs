instance_dep = <%= instance_dep %>

try do
  parent_dir = Path.expand("..", __DIR__)
  deps_dir =
    case Path.basename(parent_dir) do
      "deps" -> parent_dir                 # this gear project is used by another gear as a gear dependency
      _      -> Path.join(__DIR__, "deps") # this gear project is the toplevel mix project
    end
  Code.require_file(Path.join([deps_dir, "solomon", "mix_common.exs"]))

  defmodule <%= gear_name_camel %>.Mixfile do
    use Solomon.GearProject, [
      solomon_instance_dep: instance_dep,
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
