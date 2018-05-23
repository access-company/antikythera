# Gear Config

**Note:** This page is being updated for OSS release. Please be patient.

- In general web services need some kind of "secret token"s, such as API key for external services.
  Also, it's sometimes useful to change configurations on the fly (i.e. without changing source code and without deployment).
- For these purposes antikythera provides "gear config".
    - You can think of gear config as something like environment variables for gears.
    - Each gear's gear config is an arbitrary JSON object.

## Getting gear config

- From gear implementation, gear config is accessble by:
    - `YourGear.get_all_env/0`: Returns a map of JSON-parsed gear config.
    - `YourGear.get_env/2`: A convenience to just return a single value for the given key in gear config.
      Use this when you just want a single value; if you need multiple values use `get_all_env/0` for better performance.

## Setting gear config

- In cloud (dev/prod environment):
    - **(TBD)**
    - After update, new values of gear config become visible from gear code, running within multiple ErlangVM nodes, in about a few minutes.
- In local machine
    - Use environment variable to specify gear config for your locally-running antikythera.
      For instance, set `SOME_GEAR_CONFIG_JSON` for `some_gear` and so on.
- During tests:
    - You can use `Antikythera.Test.GearConfigHelper.set_config/1` to manipulate gear config from test code.
