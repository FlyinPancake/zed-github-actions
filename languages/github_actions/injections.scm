; Expressions in values (`key: ... ${{ ... }}`) and bare expressions in `if:`.
; The expression grammar parses the whole `key: value` pair.
((block_mapping_pair
  value: [
    (block_node
      (block_scalar) @_value)
    (flow_node
      [
        (plain_scalar
          (string_scalar) @_value)
        (double_quote_scalar) @_value
        (single_quote_scalar) @_value
      ])
  ]
  (#match? @_value "\\$\\{\\{")) @injection.content
  (#set! injection.language "GitHub Actions Expression"))

((block_mapping_pair
  key: (flow_node) @_key
  (#eq? @_key "if")
  value: (flow_node
    (plain_scalar
      (string_scalar) @_value)
    (#not-match? @_value "\\$\\{\\{"))) @injection.content
  (#set! injection.language "GitHub Actions Expression"))
