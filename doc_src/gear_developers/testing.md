# Testing

**Note:** This page is being updated for OSS release. Please be patient.

## Libraries

- You can write tests for your gear using standard [`ExUnit` test framework](https://hexdocs.pm/ex_unit/ExUnit.html).
- [`StreamData`](https://github.com/whatyouhide/stream_data) (powerful property-based testing library) is also available out of the box.
  Consider using property-based style, especially when testing side-effect free functions.
- For testing purposes antikythera provides some helpers.
  See modules prefixed with `Antikythera.Test.`.
  Note that those modules are solely for test code; don't use these modules in your production code.

## Whitebox/blackbox testing and test modes

- Antikythera defines the following two ways to run your gear's tests.
    - Start an ErlangVM to run both production code and test code of your gear.
      This type of test execution is called **whitebox testing** as test code may touch the internal of the gear implementation.
    - Start an ErlangVM to run only test code which interacts with an already-running ErlangVM that is executing your gear's production code.
      The tests in this mode check behavior of the target only through public interface of your gear (e.g. HTTP) and thus it's called **blackbox testing**.
- Running tests
    - whitebox tests:
        - `$ mix test`
    - blackbox tests:
        - `$ TEST_MODE=blackbox_local mix test`
            - Test against locally running ErlangVM; `Antikythera.Test.Config.base_url/0` points to your gear's URL in your local environment.
        - `$ TEST_MODE=blackbox_dev mix test`
            - Test against dev environment; `Antikythera.Test.Config.base_url/0` points to your gear's URL in the antikythera dev environment.
        - `$ TEST_MODE=blackbox_prod mix test`
            - Test against prod environment; `Antikythera.Test.Config.base_url/0` points to your gear's URL in the antikythera prod environment.
- You can specify when to run each of your tests by putting [tags](https://hexdocs.pm/ex_unit/ExUnit.Case.html#module-tags).
    - `@tag :blackbox` : runs during both whitebox and blackbox testing
    - `@tag :blackbox_only` : runs during blackbox testing; omitted during whitebox testing
    - (no tag) : runs during whitebox testing; omitted during blackbox testing
- Recommendation on which tag to use
    - In general, your tests can be classified based on the following properties:
        - target interface
            1. internal (Elixir) function
            2. interface which users consume, such as HTTP
        - interaction with external service(s) during test
            1. do not use any external service
            2. use stubbed/mocked version of external service(s) to test in isolation
            3. use real external service(s) for integration testing
    - Use the following table as a general rule of thumb.

      target interface | external services | whitebox testing | blackbox testing | tag
      ---------------- | ----------------- | ---------------- | ---------------- | ---
      a (Elixir)   | a (no)   | O | X | none
      a (Elixir)   | b (stub) | O | X | none
      a (Elixir)   | c (yes)  | X | X | (high- and low-level concepts are mixed; don't write this kind of tests!)
      b (end-user) | a (no)   | O | O | `@blackbox`
      b (end-user) | b (stub) | O | X | none
      b (end-user) | c (yes)  | X | O | `@blackbox_only`

- Reference: See also `Antikythera.Test.Config`

## Secret in testing

- Sometimes tests require certain kind of secret that should not be hardcoded in tests.
    - e.g. API key for an external service
- To pass such information to test runner process, antikythera defines `WHITEBOX_TEST_SECRET_JSON` and `BLACKBOX_TEST_SECRET_JSON` environment variable.
- In your test cases you can obtain contents of the environment variable via
  `Antikythera.Test.Config.whitebox_test_secret/0` or `Antikythera.Test.Config.blackbox_test_secret/0` which returns JSON-parsed variable.
