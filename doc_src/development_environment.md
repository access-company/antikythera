# Development Environment

## Install Compilers and Build Tools

- Before anything else, do note that **an antikythera instance and its gears run in the same ErlangVM cluster**.
  Therefore, obviously, all development AND deployment environments must have the same Erlang and Elixir versions!
- We strongly recommend [asdf](https://github.com/asdf-vm/asdf) to manage this synchronization.
- Antikythera itself doesn't impose any version restrictions other than the one specified in `mix.exs`.
  Individual antikythera instance project may enforce a more fine-grained restrictions on language versions.
- Other requirements:
    - Some dependencies contain C source code and thus a reasonably new C compiler is required.
    - In macOS you may be warned by outdated GNU make version during compiling antikythera's dependencies.
      In that case install GNU make using e.g. [homebrew](https://brew.sh/).
      The installed executable is `gmake`; create a symlink named `make` in somewhere in your `$PATH`
      so that the desired version of make command is selected.
    - Install development header of [Expat](https://libexpat.github.io/), which is required by [fast_xml](https://github.com/processone/fast_xml) library.
        - In macOS this should be already installed. If not, install `expat` with homebrew.
    - On Linux you have to install `inotify-tools` to enable file system watching tools
      such as [exsync](https://github.com/falood/exsync) and [mix_test_watch](https://github.com/lpil/mix-test.watch).
- [Install asdf as explained in the official README.md](https://github.com/asdf-vm/asdf#setup)
- Install asdf plugins
    - `$ asdf plugin-add erlang`
    - `$ asdf plugin-add elixir`
    - `$ asdf plugin-add nodejs`
        - Node.js installation is optional. You do not need it if you are not using asset-related features.
- Install language versions
    - In order to invoke initial `mix deps.get`, you need to globally install reasonably new Erlang and Elixir versions.
        - `$ asdf install erlang x.y.z && asdf global erlang x.y.z`
        - `$ asdf install elixir x.y.z && asdf global elixir x.y.z`
    - Working on your antikythera instance:
        - If `.tool-versions` already exists, `$ asdf install`
        - If not,
            - `$ asdf local erlang x.y.z && asdf local elixir x.y.z`
            - then commit the generated `.tool-versions` file.
    - Working on a gear:
        - Make sure you have a valid symlink named `.tool-versions` which points to `deps/your_antikythera_instance/.tool-versions`
            - This way you can make your gear's language versions in sync with your antikythera instance.
            - If your gear is generated using [`mix antikythera.gear.new`](https://github.com/access-company/antikythera/blob/master/lib/mix/gear.new.ex),
              symlink to `.tool-versions` is automatically created.
        - `$ asdf install`


### Shell history in `iex`

- Although `iex` is able to remember commands executed in previous sessions, the feature is not enabled by default.
- It is highly recommended to set the following environment variable during development:
    - `export ERL_AFLAGS="-kernel shell_history enabled"` (for bash family)

## Prepare for Domain-based Routing

- Antikythera routes web requests by subdomains and paths. See [routing](https://hexdocs.pm/antikythera/routing.html).
- In local development, you must be able to resolve subdomain of localhost (e.g. `your-gear.localhost`) into loopback address (`127.0.0.1`).
    - The easiest way is to add a line like `127.0.0.1 your-gear.localhost` to your `/etc/hosts`.
    - Alternatively, you can setup a local DNS server (such as [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html)) to resolve all subdomains of localhost.

## Environment variables to tweak behavior of antikythera

- In your local environment you can customize some of antikythera's default settings using the following environment variables:
    - Runtime environment variables:
        - `BASE_DOMAIN`:
            - Suffix part of domain names to be used when clients interact with running gears. Defaults to `localhost`.
            - For example, when you are running `:some_gear` as `BASE_DOMAIN=somedomain iex -S mix`,
              you can browse the top page of the gear at `http://some-gear.somedomain:8080/` (assuming that the default port number is used; see below).
            - Note that when using `BASE_DOMAIN` other than `localhost`, you may need to tell the DNS resolver on the client side about the gear's domain name.
        - `PORT`:
            - Port number to receive incoming web requests from. Defaults to `8081` during `mix test`, and `8080` otherwise
              (thus one can run both `iex -S mix` and `mix test` at the same time).
            - Explicitly set this when you run multiple antikythera servers within your machine.
        - `TEST_PORT`:
            - Port number to send HTTP requests to during `blackbox_local` tests. Defaults to `8080`.
        - `NO_LISTEN`:
            - A boolean flag for disabling web server functionality of antikythera. Defaults to `false`.
            - `true` is implicitly set when using `Antikythera.Mix.Task.prepare_antikythera_instance/0` in your mix task.
        - `LOG_LEVEL`:
            - Log level of all gears. Defaults to `info`. See also [logging](https://hexdocs.pm/antikythera/logging.html).
        - `TEST_LOG_ON_TERMINAL`:
            - A boolean flag for enabling output gear log on terminal during `mix test`. Defaults to `false`.
        - `SOME_GEAR_CONFIG_JSON`:
            - Gear config of `:some_gear`. See also [gear_config](https://hexdocs.pm/antikythera/gear_config.html).
    - Compile-time environment variables: (to change the followings you need to recompile antikythera)
        - `GEAR_ACTION_TIMEOUT`:
            - Milliseconds to wait until gear action finishes. Defaults to `10000`. See also [controller](https://hexdocs.pm/antikythera/controller.html).
        - `GEAR_PROCESS_MAX_HEAP_SIZE`:
            - Maximum size of per-process heap memory in words. Defaults to `50000000` (400MB in 64-bit architecture).

- If you develop mix task, you can use the following environment variables:
    - Runtime environment variables:
        - `ANTIKYTHERA_MIX_TASK_MODE`:
            - A boolean flag whether Antikythera runs for mix task. Defaults to `false`.
            - You must set `true` even if your command is mix task.
            - If you set a value other than `local` to `ANTIKYTHERA_RUNTIME_ENV`, Antikythera thinks it was built for a release package and is deployed to a cloud.
              Then, the path to the config files will be broken, and Antikythera will try to use cloud services even if your mix task running enrivonment doesn't allow them.
              If this variable is `true`, Antikythera won't do them.
    - Compile-time environment variables: (to change the followings you need to recompile antikythera)
        - `ANTIKYTHERA_MIX_TASK_MODE`:
            - A boolean flag whether Antikythera is compiled for mix task. Defaults to `false`.
            - You must set `true` even if your command is mix task and automatically compile Antikythera.
            - If you set a value other than `local` to `ANTIKYTHERA_COMPILE_ENV`, Antikythera thinks it is built for a release package and will be deployed to a cloud.
              Then, the path to the config files will be broken, and Antikythera will try to use cloud services even if your mix task running enrivonment doesn't allow them.
              If this variable is `true`, Antikythera won't do them.
