# Getting Started

- Set up your [development environment](./development_environment.md).
    - Basically you need to (1) install Erlang and Elixir, and (2) prepare for [domain-based routing](./gear_developers/routing.md).
- Then, you need your own antikythera instance!
    - **Documentation about this part is in preparation. Please be patient!**
    - For now, you can start by using [antikythera_instance_example](https://github.com/access-company/antikythera_instance_example).

      ```
      $ git clone https://github.com/access-company/antikythera_instance_example.git
      $ cd antikythera_instance_example
      $ mix deps.get
      (If you encountered an error complaining about required Erlang and/or Elixir versions, run `asdf install` here)
      $ mix deps.get # fetch additional dependencies declared in antikythera_instance_example
      $ mix compile
      ```

- Now you can generate your own gear application using antikythera_instance_example!
    - From antikythera_instance_example directory:

      ```
      $ mix antikythera.gear.new ~/path/to/my_gear
      $ cd ~/path/to/my_gear
      (In order for versioning utility to work, git repository and root commit is required)
      $ git init
      $ git add .
      $ git commit -m 'Initial commit'
      $ mix deps.get
      $ mix deps.get # fetch additional dependencies declared in antikythera_instance_example
      $ iex -S mix
      ```

    - Open `http://my-gear.localhost:8080/hello` in web browser, see if it is working!
- Congratulations! Now your first gear is up and running.
    - Take a look around and play around with it.
    - Check out documentations and see what you can do with antikythera and gears.
        - [Guide for instance administrators](./instance_administrators/) (TBD)
        - [Guide for gear developers (i.e. developers of web services)](./gear_developers/)
        - [API References](https://hexdocs.pm/antikythera/api-reference.html) (To be published)
