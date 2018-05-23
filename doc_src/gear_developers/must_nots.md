# What Gears Must Not Do

**Note:** This page is being updated for OSS release. Please be patient.

- (Some of the issues listed here are checked by `compile.antikythera_gear_static_analysis` every time you compile your gear's code.)
- Modules prefixed with `Antikythera` define interface functions to be used by gear implementations.
  On the other hand, modules with the other prefixes (`AntikytheraCore`, `AntikytheraEal` and `AntikytheraLocal`)
  are internal to antikythera and not for gear implementations.
  Gears must not directly depend on these antikythera-internal modules.
- All modules in a gear must be properly prefixed with the gear name, e.g. `YourGear.SomeModule` or `Mix.Tasks.YourGear.SomeTask`.
  Modules without correct prefixes are not allowed; they can cause name clashes.
- Dynamically creating atoms (e.g. make atoms from request bodies) is strictly prohibited as it _is_ memory leak.
    - Atoms are stored globally within an ErlangVM and are not garbage-collected.
      Accumulated memory resources occupied by dynamically created atoms can result in memory issue.
    - Following code in runtime context are considered problematic:
        - `String.to_atom/1` : use `String.to_existing_atom/1` instead
        - `Module.concat/1,2` : use `Module.safe_concat/1,2` instead
        - atom expression with interpolation such as `:"abc_#{foo}"`
- Scheduling of Erlang processes is controlled by antikythera.
  Gear implementations must not disturb it by manually spawning/terminating processes.
- Accessing local file system is basically of no practical use, as they will be discarded by changes in underlying infrastructure configuration.
  However the following use cases are allowed:
    - Reading files in your gear's `priv` directory.
      Files in your gear's `priv` directory are directly copied from the git repository during compilation and thus under your control.
    - Reading/writing files within temporary directory created by `Antikythera.Tmpdir.make/2`.
- Writing to `STDOUT`/`STDERR` must also be avoided since these streams are used by antikythera and not for a specific gear. Use `YourGear.Logger` instead.
