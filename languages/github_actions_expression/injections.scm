(function_call
  function: (identifier) @_function
  (#eq? @_function "fromJSON")
  arguments: (arguments
    .
    (string
      (string_content) @injection.content
      (#set! injection.language "JSON"))))
