inputs =
  Enum.flat_map(
    ["{mix,.formatter}.exs", "{lib,web,test}/**/*.{ex,exs}"],
    &Path.wildcard(&1, match_dot: true)
  ) -- ["web/router.ex"]

[
  inputs: inputs,
  locals_without_parens: [defun: 2, defunp: 2, defunpt: 2, defpt: 2, plug: :*]
]
