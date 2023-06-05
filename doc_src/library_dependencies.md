# Dependency Management

- Elixir ships with the official build tool [`mix`](https://hexdocs.pm/mix/Mix.html) and it manages dependencies for elixir projects.
  Open source libraries written in Elixir or Erlang are basically published at [hex.pm](https://hex.pm/).
  Usually elixir/mix project specifies its dependencies in `mix.exs` file.
- In antikythera, library dependencies are defined **in your antikythera instance**.
  Gear projects inherit dependencies of their antikythera instance, and have no means of specifying non-gear dependencies.
- This is the design decision made based on the following reasons:
    - Antikythera instances host multiple gears that are independent of each other.
    - If each gear could specify its own dependencies, those dependencies would conflict and disrupt execution of other gears.
    - In cases where multiple library candidates are found for a specific purpose,
      it is beneficial to choose one of them and share it by all gears in that you can reuse knowledge of that library.
- Therefore all libraries used by both an antikythera instance and gears are managed solely by the antikythera instance.
    - Conversely, it is the duty of antikythera instance administrators to carefully choose good libraries and manage their versions.
- In order to keep gears' dependencies in-sync with your antikythera instance,
  gear developers should periodically update their gears with `$ mix deps.update antikythera_instance_name`.
    - Update cycle should be determined by how often your antikythera instance is updated.
    - Note that unless some breaking changes are introduced to your antikythera instance by e.g. updating a library to an incompatible version,
      already compiled gears should continue to work.
    - This is an essential feature of antikythera that allows you to independently update antikythera instances and its gears!
      See [Deployment](https://hexdocs.pm/antikythera/deployment.html) for details.

## Libraries available from gears

- Available libraries must be defined in your antikythera instance's `mix.exs`, just as you do in normal mix projects.
- A gear project inherits its antikythera instance's dependencies, so all libraries listed in the antikythera instance are also available to its gears.
- If you have requests of libraries to include, consult your antikythera instance administrators.

### "Indirect" dependencies

- In antikythera instances, you can declare some dependencies as `:indirect` ones like so:

  ```elixir
  {:ranch, "1.4.0" , [indirect: true]},
  ```

- As the name suggests, you can use this special option to "lock" indirect dependencies defined in your dependencies.
    - Without this, versions of indirect dependencies become ambiguous in gear projects, potentially leading to unexpected behaviors.
    - Startup of indirect dependencies as runtime OTP applications are controlled by their "parent" dependencies.
      Neither antikythera instances nor their gears explicitly start them.

## Specifying other gears as dependencies

- Although gears cannot specify dependencies in general, they can declare dependency to other gears.
- For this purpose you can specify the names of gears that your gear depends on by `gear_deps/0` in gears' `mix.exs`.
    - For example, the following `gear_deps/0` declares dependency to `gear_a` and `gear_b`

      ```elixir
      defp gear_deps() do
        [
          {:gear_a, [git: "git@github.com:your-organization/gear_a.git"]},
          {:gear_b, "1.0.0", [organization: "your-organization"]}, # Private packages; see https://hex.pm/docs/private
        ]
      end
      ```

    - Note that `gear_deps/0` function can be module private.
- If you have any gear dependencies, you should also update them periodically,
  e.g. `$ mix deps.update antikythera_instance_name gear_a gear_b`.


## Tools

- Some development/test libraries are useful and recommended to include in your antikythera instance.
- Also check out [antikythera's `mix.exs`](https://github.com/access-company/antikythera/blob/master/mix.exs) as a reference.

### Static analysis using [dialyzer](http://www.erlang.org/doc/man/dialyzer.html)

- With [dialyxir](https://github.com/jeremyjh/dialyxir), you can run typecheck of your code by `$ mix dialyzer`.
    - `dialyxir` wraps the `dialyzer`, allowing it to conveniently run from mix projects.
- See [here](http://learnyousomeerlang.com/dialyzer) for details of success typing analysis.

### [ex_doc](https://github.com/elixir-lang/ex_doc) for documentations

- With `ex_doc`, you can generate nicely rendered HTML documents from your Elixir code.
- Elixir developers are always encouraged to add `@moduledoc`/`@doc`/`@typedoc` attributes to modules/functions/types to clearly express their intentions.
- You should consider hosting your generated HTMLs at somewhere visible to your organization.

### Test coverage reports

- Test coverage reports are also essential to monitor code quality.
    - Antikythera uses [`excoveralls`](https://github.com/parroty/excoveralls) as its coverage tool.
      See the documentation of the tool for configuration options using `coveralls.json` file.
