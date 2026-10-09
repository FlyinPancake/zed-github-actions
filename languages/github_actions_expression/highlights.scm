; Based on the queries of tree-sitter-gh-actions-expressions, with capture names
; mapped to the ones Zed themes style.

(boolean) @boolean

(null) @constant.builtin

[
  (number)
  (format_index)
] @number

[
  (string)
  (format_string)
] @string

(format_variable
  [
    "{"
    "}"
  ] @punctuation.special)

(scape_sequence) @string.escape

(context
  (identifier) @variable.special
  (#any-of? @variable.special
    "github" "env" "vars" "job" "jobs" "steps" "runner" "secrets" "strategy" "matrix" "needs"
    "inputs"))

(property
  [
    (identifier)
    (asterisk)
  ] @property)

(property_deref) @punctuation.delimiter

(index) @punctuation.delimiter

(function_call
  function: (identifier) @function)

(function_call
  [
    "("
    ")"
  ] @punctuation.bracket)

"," @punctuation.delimiter

(delimited_expression
  [
    "${{"
    "}}"
  ] @punctuation.special)

(logical_group
  [
    "("
    ")"
  ] @punctuation.bracket)

[
  (operator)
  (not)
] @operator
