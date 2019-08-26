# Getting Started

- Set up your [development environment](https://hexdocs.pm/antikythera/development_environment.html).
    - Basically you need to (1) install Erlang and Elixir, and (2) prepare for [domain-based routing](https://hexdocs.pm/antikythera/routing.html).
- Then, you need your own antikythera instance.
    - **Documentation about this part is in preparation. Please be patient!**
    - If you don't have one yet, you can start by using [`antikythera_instance_example`](https://github.com/access-company/antikythera_instance_example).

      ```
      $ git clone https://github.com/access-company/antikythera_instance_example.git
      $ cd antikythera_instance_example
      $ mix deps.get
      (If you encountered an error complaining about required Erlang and/or Elixir versions, run `asdf install` here)
      $ mix deps.get # fetch additional dependencies declared in antikythera_instance_example
      $ mix compile
      ```

- Now you can generate your own gear project using your antikythera instance.
    - From local clone of your antikythera instance:

      ```
      $ mix antikythera.gear.new ~/path/to/my_gear
      $ cd ~/path/to/my_gear
      # In order for versioning utility of antikythera to work, git repository and an initial commit are necessary.
      $ git init
      $ git add .
      $ git commit -m 'Initial commit'
      $ mix deps.get
      $ mix deps.get # fetch additional dependencies declared in your antikythera instance
      $ iex -S mix
      ```

    - Open `http://my-gear.localhost:8080/hello` in web browser, see if it is working.
- Congratulations! Now your first gear is up and running.
    - Take a look around and play around with it.
    - Check out documentations and see what you can do with antikythera and gears.
        - [Guide for instance administrators](./instance_administrators/) (TBD)
        - [Guide for gear developers (i.e. developers of web services)](./gear_developers/README.md)
        - [API References](https://hexdocs.pm/antikythera/api-reference.html) (To be published)
