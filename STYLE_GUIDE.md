# Antikythera Style Guide

Overall policy:

1. Be consistent within a chunk of your changes.
2. Be consistent with surrounding code.
3. Make use of this (and linked) Style Guides when in doubt.
4. Ask and discuss!

## Guidelines

We are *mostly* following [Credo's Elixir Style Guide](https://github.com/rrrene/elixir-style-guide).

Styles marked as **preferred** in the Credo's guide are mostly used.

If you find yourself lost about coding style, always search in existing code for similarities.
Or just ask in a Pull Request or [Users ML](https://groups.google.com/forum/#!forum/antikythera_users).

As a side-reading, [A community driven style guide for Elixir](https://github.com/levionessa/elixir_style_guide) is also available.
We are not compliant with all of it, but it provides good advices.

Note: Although we are mostly following its style guide,
we are not completely relying on [Credo](https://github.com/rrrene/credo) static analysis.

## Alignment

Align parts of multiline code with similar patterns.
This is really important for human eyes in terms of readability.

Example:

```elixir
case nested_tuple do
  {:ok   , {:matched_value, bound_var}} -> do_something(bound_var)
  {:ok   , {not_matched   , _        }} -> do_something_else(not_matched)
  {:error, reason                     } -> handle_error(reason)
end

def multi_clause_fun({:ok   , "short"           }, :normal), do: :ok
def multi_clause_fun({:ok   , "relatively_long" }, _      ), do: {:error, :too_long}
def multi_clause_fun({:error, {:invalid, String}}, _      ), do: {:error, :invalid}
```

Without alignments, code chunks become less readable.
As a guideline, 3 or more lines of similar statements could use alignments.
But this is not a strict rule.

Aligning code does not have significant drawbacks, so always try to align and beautify your code.

## Typespec

Typespecs are useful for both documentation purpose and success typing analysis ([dialyzer](http://erlang.org/doc/man/dialyzer.html)).
So it's preferred to explicitly declare typespecs of functions, especially for public ones.

We are utilizing [`Croma.Defun`](https://hexdocs.pm/croma/Croma.Defun.html) series for easy typespec notations.

Example:

```elixir
@type timed_id_t :: {pos_integer, reference}

defun five_params_fun(key      :: v[atom],
                      some_str :: v[String.t],
                      key_list :: [atom],
                      timed_id :: timed_id_t,
                      state    :: v[map]) :: :ok | {:error, term} do
  # Do something
end
```

Also, use `v[]` validation where applicable. See [`Croma.Defun`](https://hexdocs.pm/croma/Croma.Defun.html) for details.
Note that validations of arguments by `v[]` are disabled when compiling for production environment.

Do not hesitate to put typespecs on complicated private functions too.

## Module names

For module names we simply use CamelCase even if they contain acronyms.
For instance we use `Antikythera.Url`, not `Antikythera.URL`.
This is to eliminate exceptional case in our naming rules,
which leads to easier conversions between module aliases and strings.

## Order of module aliases

Module aliases **MUST** be ordered in their generality;
modules with general use cases **MUST** come above modules with limited use cases.

1. External modules
2. `Antikythera`
3. `AntikytheraCore`
4. `AntikytheraEal`

For sub-modules under namespaces listed above, there is no specific order defined.

You SHOULD bundle modules of the same level:

```elixir
alias Antikythera.{GearName, GearNameStr}
```

## Do not abuse `import`

`import`ing a module will allow you to use its functions without `SomeModule.` prefix.
However it SHOULD NOT be abused because it can lead to name conflicts.

- Use only when you are absolutely sure it is safe and useful there.
- Limit its targets with `:only` option.
- Consider limiting its scope by placing it inside a specific scope.

## Function calling syntax

You MUST NOT omit parentheses in function calls.

```elixir
# Okay
result = zero_arity_function()
result = one_arity_function(arg1)

# Not okay as it gets warned by elixir compiler
result = zero_arity_function

# Not okay (less readable especially when some args are long and not pipe-ready)
result = some_function arg1, arg2, arg3, arg4

# Okay
result = some_function(arg1, arg2, arg3, arg4)
```

Also you MUST NOT omit parentheses when you define functions.
Note that you MAY omit parentheses when invoking macros.

## Using `|>` operator

Pipe operator improves code readability when 1st argument is a complex expression
because it reorders expressions in the evaluation order.

```elixir
# You have to read inside-out, as function arguments are evaluated before function invocation
Enum.sort(Enum.filter(list, &some_predicate/1))

# Much readable as you can now naturally follow the evaluation order from left to right
Enum.filter(list, &some_predicate/1) |> Enum.sort()
```

Also pipe operator makes separation between "data" and "its transformation" clearer.

```elixir
list
|> Enum.map(some_func)
|> Enum.filter(some_predicate)
|> Enum.reduce(acc0, some_reducer)
```

If you have neither of the above benefits in mind, you SHOULD NOT use pipe operator.

```elixir
# absurd
keys = some_map |> Map.keys()

# simple enough
keys = Map.keys(some_map)
```
