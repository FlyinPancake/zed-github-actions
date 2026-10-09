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

; Shell scripts in `run:`. The shell is picked like GitHub does: the step's
; `shell:`, then the job's `defaults.run.shell`, then the runner's default
; (PowerShell on Windows, bash elsewhere). Each level only applies when the
; levels above don't set a shell, so exactly one pattern matches each script.
;
; Unknown shells (`cmd`, custom commands, expressions) get no injection, and
; runners from a matrix are assumed to be Linux. The workflow's
; `defaults.run.shell` isn't detected: a pattern rooted at the workflow keeps too
; many partial matches alive and exceeds Zed's query match limit, which silently
; drops injections. For the same reason, step-level patterns start at the step
; and only the fallbacks start at the job.

; Step `shell: bash`
((block_sequence_item
  (block_node
    (block_mapping
      (block_mapping_pair
        key: (flow_node) @_run
        value: [
          (flow_node
            (plain_scalar) @injection.content)
          (block_node
            (block_scalar) @injection.content)
        ])) @_step))
  (#eq? @_run "run")
  (#match? @_step "(?m)^[ \\t]*shell:[ \\t]*['\"]?(?:bash|sh)\\b")
  (#set! injection.language "Shell Script"))

; Step `shell: pwsh`
((block_sequence_item
  (block_node
    (block_mapping
      (block_mapping_pair
        key: (flow_node) @_run
        value: [
          (flow_node
            (plain_scalar) @injection.content)
          (block_node
            (block_scalar) @injection.content)
        ])) @_step))
  (#eq? @_run "run")
  (#match? @_step "(?m)^[ \\t]*shell:[ \\t]*['\"]?(?:pwsh|powershell)\\b")
  (#set! injection.language "PowerShell"))

; Step `shell: python`
((block_sequence_item
  (block_node
    (block_mapping
      (block_mapping_pair
        key: (flow_node) @_run
        value: [
          (flow_node
            (plain_scalar) @injection.content)
          (block_node
            (block_scalar) @injection.content)
        ])) @_step))
  (#eq? @_run "run")
  (#match? @_step "(?m)^[ \\t]*shell:[ \\t]*['\"]?(?:python)\\b")
  (#set! injection.language "Python"))

; Job `defaults.run.shell: bash`
((block_mapping
  (block_mapping_pair
    key: (flow_node) @_steps
    value: (block_node
      (block_sequence
        (block_sequence_item
          (block_node
            (block_mapping
              (block_mapping_pair
                key: (flow_node) @_run
                value: [
                  (flow_node
                    (plain_scalar) @injection.content)
                  (block_node
                    (block_scalar) @injection.content)
                ])) @_step)))))) @_job
  (#eq? @_steps "steps")
  (#eq? @_run "run")
  (#not-match? @_step "(?m)^[ \\t]*shell:")
  (#match? @_job "defaults:[ \\t]*(?:\\n[ \\t]+run:[ \\t]*\\n(?:[ \\t]+working-directory:[^\\n]*\\n)?[ \\t]+|\\{[^\\n]*)shell:[ \\t]*['\"]?(?:bash|sh)\\b")
  (#set! injection.language "Shell Script"))

; Job `defaults.run.shell: pwsh`
((block_mapping
  (block_mapping_pair
    key: (flow_node) @_steps
    value: (block_node
      (block_sequence
        (block_sequence_item
          (block_node
            (block_mapping
              (block_mapping_pair
                key: (flow_node) @_run
                value: [
                  (flow_node
                    (plain_scalar) @injection.content)
                  (block_node
                    (block_scalar) @injection.content)
                ])) @_step)))))) @_job
  (#eq? @_steps "steps")
  (#eq? @_run "run")
  (#not-match? @_step "(?m)^[ \\t]*shell:")
  (#match? @_job "defaults:[ \\t]*(?:\\n[ \\t]+run:[ \\t]*\\n(?:[ \\t]+working-directory:[^\\n]*\\n)?[ \\t]+|\\{[^\\n]*)shell:[ \\t]*['\"]?(?:pwsh|powershell)\\b")
  (#set! injection.language "PowerShell"))

; Job `defaults.run.shell: python`
((block_mapping
  (block_mapping_pair
    key: (flow_node) @_steps
    value: (block_node
      (block_sequence
        (block_sequence_item
          (block_node
            (block_mapping
              (block_mapping_pair
                key: (flow_node) @_run
                value: [
                  (flow_node
                    (plain_scalar) @injection.content)
                  (block_node
                    (block_scalar) @injection.content)
                ])) @_step)))))) @_job
  (#eq? @_steps "steps")
  (#eq? @_run "run")
  (#not-match? @_step "(?m)^[ \\t]*shell:")
  (#match? @_job "defaults:[ \\t]*(?:\\n[ \\t]+run:[ \\t]*\\n(?:[ \\t]+working-directory:[^\\n]*\\n)?[ \\t]+|\\{[^\\n]*)shell:[ \\t]*['\"]?(?:python)\\b")
  (#set! injection.language "Python"))

; Windows runner default
((block_mapping
  (block_mapping_pair
    key: (flow_node) @_steps
    value: (block_node
      (block_sequence
        (block_sequence_item
          (block_node
            (block_mapping
              (block_mapping_pair
                key: (flow_node) @_run
                value: [
                  (flow_node
                    (plain_scalar) @injection.content)
                  (block_node
                    (block_scalar) @injection.content)
                ])) @_step)))))) @_job
  (#eq? @_steps "steps")
  (#eq? @_run "run")
  (#not-match? @_step "(?m)^[ \\t]*shell:")
  (#not-match? @_job "defaults:[ \\t]*(?:\\n[ \\t]+run:[ \\t]*\\n(?:[ \\t]+working-directory:[^\\n]*\\n)?[ \\t]+|\\{[^\\n]*)shell:")
  (#match? @_job "(?i)runs-on:[ \\t]*(?:[^\\n]*windows|\\n(?:[ \\t]+-[^\\n]*\\n)*?[ \\t]+-[^\\n]*windows)")
  (#set! injection.language "PowerShell"))

; Default
((block_mapping
  (block_mapping_pair
    key: (flow_node) @_steps
    value: (block_node
      (block_sequence
        (block_sequence_item
          (block_node
            (block_mapping
              (block_mapping_pair
                key: (flow_node) @_run
                value: [
                  (flow_node
                    (plain_scalar) @injection.content)
                  (block_node
                    (block_scalar) @injection.content)
                ])) @_step)))))) @_job
  (#eq? @_steps "steps")
  (#eq? @_run "run")
  (#not-match? @_step "(?m)^[ \\t]*shell:")
  (#not-match? @_job "defaults:[ \\t]*(?:\\n[ \\t]+run:[ \\t]*\\n(?:[ \\t]+working-directory:[^\\n]*\\n)?[ \\t]+|\\{[^\\n]*)shell:")
  (#not-match? @_job "(?i)runs-on:[ \\t]*(?:[^\\n]*windows|\\n(?:[ \\t]+-[^\\n]*\\n)*?[ \\t]+-[^\\n]*windows)")
  (#set! injection.language "Shell Script"))
