# AGENTS.md

Comprehensive working guideline for AI agents and human developers contributing to **Antikythera**.

## References

Read these before making changes. They are the source of truth; this file only summarizes them.

- [`README.md`](./README.md) — project overview, architecture, and getting started.
- [`STYLE_GUIDE.md`](./STYLE_GUIDE.md) — coding rules (the review checklist below is derived from it).
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — contribution workflow, branching, and how to test with an actual gear.
- [`.tool-versions`](./.tool-versions) — required runtime versions (Erlang `26.2.5.14`, Elixir `1.15.8-otp-26`).
- External:
    - [Antikythera documentation](https://hexdocs.pm/antikythera) / [API Reference](https://hexdocs.pm/antikythera/api-reference.html)
    - [Credo's Elixir Style Guide](https://github.com/rrrene/elixir-style-guide)
    - [`Croma.Defun`](https://hexdocs.pm/croma/Croma.Defun.html)
    - Related projects used for testing: [`testgear`](https://github.com/access-company/testgear), [`antikythera_instance_example`](https://github.com/access-company/antikythera_instance_example)

## Overview

Antikythera is an [Elixir] framework for building your own in-house PaaS.
A single cluster of [ErlangVM][Erlang] nodes (an **"antikythera instance"**) runs multiple web
services (**"gears"**) co-located within the same VMs (a "nano-services architecture"), giving gear
developers a FaaS-like development experience while eliminating per-service infrastructure overhead.
It provides a web framework (HTTP/WebSocket, domain- and path-based routing, HAML templates, CDN
support), an asynchronous job executor with built-in distributed job queues, and platform features
for multi-service/multi-tenant resource control, deployment, logging, monitoring, and configuration.

Antikythera and each gear are separate [mix](https://hexdocs.pm/mix/Mix.html) projects; all gears are
written in Elixir and inherit library dependencies defined per antikythera instance. See
[`README.md`](./README.md) for the full architecture diagram and details.

[Elixir]: https://elixir-lang.org/
[Erlang]: https://www.erlang.org/

## Commands

Run from the project root. Ensure the runtime versions in [`.tool-versions`](./.tool-versions) are active.

| Purpose | Command |
| --- | --- |
| Install dependencies | `mix deps.get` |
| Compile | `mix compile` |
| Format code | `mix format` |
| Run tests | `mix test` |
| Typecheck (success typing) | `mix dialyzer` |
| Static code analysis | `mix credo -a --strict` |
| Generate documentation | `mix docs` |
| Lint Markdown | `markdownlint-cli2 --fix "**/*.md"` |

If a dependency/compile error occurs, refresh dependencies (see [`CONTRIBUTING.md`](./CONTRIBUTING.md)):

```shell
mix deps.clean
mix deps.update --all
mix deps.get
```

> **Note — auto-generated / read-only paths.** Do **not** hand-edit files under these directories; they
> are produced by the tooling above and are git-ignored (see [`.gitignore`](./.gitignore)):
> `_build/`, `_build_local/`, `deps/` (from `mix deps.get`), `doc/` (from `mix docs`), `cover/`, `tmp/`,
> `rel_erlang-*/`, `rel_local_erlang-*/`, plus `*.beam`, `*.ez`, and `erl_crash.dump`.
> `mix.lock` is committed but should only change via `mix deps.*` commands, never by manual editing.

## Development Rules

### References

- Coding style: [`STYLE_GUIDE.md`](./STYLE_GUIDE.md) (based on [Credo's Elixir Style Guide](https://github.com/rrrene/elixir-style-guide)).
- Contribution workflow: [`CONTRIBUTING.md`](./CONTRIBUTING.md).

### Workflow highlights (from `CONTRIBUTING.md`)

- Use GitHub-flow: branch off `master`; keep branch names and commit messages descriptive and consistent with recent history.
- Implement features **with tests**, and land changes in small, loosely-coupled chunks (single responsibility) to keep reviews tractable.
- At minimum, test the behavior of modules' public interfaces.
- When a change needs an actual gear to verify, test via [`testgear`](https://github.com/access-company/testgear) and [`antikythera_instance_example`](https://github.com/access-company/antikythera_instance_example).

### Reviewer checklist (highlights from `STYLE_GUIDE.md`)

Verify each of these when writing or reviewing code:

- [ ] **Consistency:** changes are consistent within themselves and with surrounding code.
- [ ] **Typespecs:** public functions (and complex private ones) declare typespecs; prefer [`Croma.Defun`](https://hexdocs.pm/croma/Croma.Defun.html) and `v[]` argument validation where applicable (note: `v[]` validations are disabled in production builds).
- [ ] **Module names:** CamelCase even for acronyms (e.g. `Antikythera.Url`, not `Antikythera.URL`).
- [ ] **Alias order:** aliases ordered by generality — external → `Antikythera` → `AntikytheraCore` → `AntikytheraEal`; bundle same-level modules (e.g. `alias Antikythera.{GearName, GearNameStr}`).
- [ ] **`import`:** not abused; scoped and limited with `:only` when used.
- [ ] **Parentheses:** never omitted in function definitions or calls (they MAY be omitted only when invoking macros).
- [ ] **Pipe `|>`:** used only when it aids readability (complex first argument / data-transformation chains); not for trivial single calls.
- [ ] **Formatting & analysis clean:** `mix format` produces no diff, and `mix credo -a --strict` and `mix dialyzer` report no new issues.

## Definition of Done

A change is done only when **all** of the following pass, in order:

1. **Run tests** — `mix test` passes.
2. **Lint / typecheck** — `mix format` (no diff), `mix credo -a --strict`, and `mix dialyzer` all pass with no new issues. Run `markdownlint-cli2` when Markdown files are changed.
3. **Review** — the change satisfies the reviewer checklist in [Development Rules](#development-rules).
4. **Re-run after modifications** — if any files are changed while addressing steps 1–3, re-run the relevant tests, lint, and typecheck (steps 1–2) until they pass again.
