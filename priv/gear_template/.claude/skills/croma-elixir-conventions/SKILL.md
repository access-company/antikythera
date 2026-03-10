---
name: croma-elixir-conventions
description: >-
  This skill should be used when writing Elixir modules in Elixir projects that use Croma.
  TRIGGER when: creating new .ex files, writing new modules/functions, writing defun/defunp/defmodule,
  writing private or public Elixir functions, or editing existing Elixir code in projects with `use Croma`.
  Also trigger when: the user asks to write a function that takes typed parameters and returns typed values in Elixir.
  DO NOT TRIGGER when: reading/reviewing code without modifications, or non-Elixir tasks.
user-invocable: false
---

# Croma Elixir Conventions

When writing Elixir code in projects that use Croma, follow these conventions:

## Module Structure

- Start files with `use Croma` before the `defmodule`.

## Function Definitions

- Use `defun` / `defunp` instead of `def` / `defp`.
- **Prefer `case`/`cond` over multi-clause functions** when branching on a single argument's value. This keeps a single `defun`/`defunp` with `v[]` validation:
  ```elixir
  # Good - single defunp with case, gets v[] validation
  defunp calculate_discount(price :: v[non_neg_integer()], membership_level :: v[atom()]) :: v[non_neg_integer()] do
    case membership_level do
      :gold   -> round(price * 0.7)
      :silver -> round(price * 0.85)
      _       -> price
    end
  end

  # Avoid - loses v[] validation, multiple clauses for simple value dispatch
  @spec calculate_discount(non_neg_integer(), atom()) :: non_neg_integer()
  defp calculate_discount(price, :gold), do: round(price * 0.7)
  defp calculate_discount(price, :silver), do: round(price * 0.85)
  defp calculate_discount(price, _), do: price
  ```

## Type Validation with `v[]`

- **Always** wrap arguments and return types with `v[]` for runtime type validation. This applies to all types including union types and nilable types. **Do not hesitate** to use `v[]` on unions — it works correctly:
  ```elixir
  defun my_func(name :: v[String.t()], count :: v[non_neg_integer()]) :: v[String.t()] do
  defun find_name(user_id :: v[String.t()]) :: v[nil | String.t()] do
  defunp do_lookup(id :: v[String.t()]) :: v[nil | Terminal.t()] do
  defunp classify(value :: v[String.t()]) :: v[:small | :large] do
  ```
- **Do NOT use `v[]`** on single literal atom return types (e.g., `:ok`) — causes a compile warning:
  ```elixir
  defun pretty_print(str :: v[String.t()]) :: :ok do  # Good
  defun pretty_print(str :: v[String.t()]) :: v[:ok] do  # Bad
  ```
- **Do NOT use `v[]`** on types without Croma's `valid?/1` (e.g., `DateTime.t()`, `Keyword.t()`, `term()`) — causes `UndefinedFunctionError` or `RuntimeError`:
  ```elixir
  defun process(dt :: DateTime.t()) :: v[String.t()] do  # Good
  defun process(dt :: v[DateTime.t()]) :: v[String.t()] do  # Bad
  defun process(arg :: v[{:ok, term()} | :timeout]) :: term() do  # Good
  defun process(arg :: v[{:ok, term()} | :timeout]) :: v[term()] do  # Bad
  ```

## Return Types

- For `{:ok, value} | {:error, reason}`, use `alias Croma.Result, as: R` and `R.t(value_type)`:
  ```elixir
  alias Croma.Result, as: R
  defun validate(name :: v[String.t()]) :: v[R.t(map())] do
  ```
- Only add the alias when the module actually uses `R.t()`.

## Example

```elixir
use Croma

defmodule MyApp.UserValidator do
  alias Croma.Result, as: R

  defun validate(username :: v[String.t()], age :: v[non_neg_integer()]) ::
          v[R.t(map())] do
    {:ok, %{username: username, age: age}}
  end

  defunp check_length(value :: v[String.t()]) :: v[:ok | {:error, String.t()}] do
    if String.length(value) > 0, do: :ok, else: {:error, "empty"}
  end
end
```
