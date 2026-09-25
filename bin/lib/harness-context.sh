#!/usr/bin/env bash
# Shared context extraction helpers for command-hook harnesses.
# Keep hosted payloads minimal: policy inputs only, never raw file contents.

aport_hook_tool_name_normalize() {
    printf '%s' "${1:-}" \
        | tr -d '[:space:]' \
        | sed 's/^functions\.//' \
        | sed 's/(.*$//' \
        | tr '[:upper:]' '[:lower:]'
}

aport_hook_payload_has_malformed_tool_arguments() {
    local payload="$1"
    jq -e '
      def malformed(v):
        if v == null then false
        elif (v | type) == "object" then false
        elif (v | type) == "string" then
          (try ((v | fromjson | type) == "object") catch false) | not
        else true
        end;
      malformed(.tool_input) or malformed(.input) or malformed(.args)
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_conflicting_shell_command_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      def command_values:
        [
          .command,
          (argument_containers[] | .command, .cmd, .script, .shell_command)
        ]
        | map(select(type == "string" and length > 0));
      (command_values | unique | length) > 1
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_malformed_shell_command_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def malformed_command(v):
        v != null and (v | type) != "string";
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      malformed_command(.command) or
      any(argument_containers[]; (
        malformed_command(.command) or
        malformed_command(.cmd) or
        malformed_command(.script) or
        malformed_command(.shell_command)
      ))
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_conflicting_file_target_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def arr(v): if (v | type) == "array" then v elif v == null then [] else [v] end;
      def urlish(v): if (v | type) == "string" then (v | test("^https?://"; "i")) else false end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      . as $root |
      ([
        $root.file_path,
        $root.path,
        $root.dir_path,
        (if urlish($root.source) then null else $root.source end),
        ($root | argument_containers[] | .file_path, .path, .dir_path, .absolute_path, .notebook_path, .notebookPath, (if urlish(.source) then null else .source end))
      ] | map(select(type == "string" and length > 0)) | unique) as $scalar_targets |
      ([$root | argument_containers[] | (arr(.paths)[]), (arr(.include)[])] | map(select(type == "string" and length > 0)) | unique) as $path_targets |
      (
        ($scalar_targets | length) > 1 or
        (
          ($scalar_targets | length) == 1 and
          ($path_targets | map(select(. != $scalar_targets[0])) | length) > 0
        )
      )
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_malformed_file_target_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def urlish(v): if (v | type) == "string" then (v | test("^https?://"; "i")) else false end;
      def malformed_path(v):
        if v == null then false
        elif (v | type) == "string" then false
        elif (v | type) == "array" then any(v[]; type != "string")
        else true
        end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      . as $root |
      [
        $root.file_path,
        $root.path,
        $root.dir_path,
        (if urlish($root.source) then null else $root.source end),
        $root.matcher_context,
        ($root | argument_containers[] | .file_path, .path, .dir_path, .absolute_path, .notebook_path, .notebookPath, .matcher_context, (if urlish(.source) then null else .source end)),
        ($root | argument_containers[] | .paths, .include)
      ]
      | any(malformed_path(.))
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_conflicting_web_target_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def str(v): if v == null then "" else (v | tostring) end;
      def urlish(v): if (v | type) == "string" then (v | test("^https?://"; "i")) else false end;
      def methodish(v): if (v | type) == "string" and (v | length) > 0 then (v | ascii_upcase) else "" end;
      def url_host(v):
        str(v) as $s |
        if ($s | contains("\\") or test("[[:cntrl:]]")) then
          ""
        else
          if ($s | test("^[A-Za-z][A-Za-z0-9+.-]*://")) then
            (try (
              ($s | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<authority>[^/?#]*)").authority | sub("^.*@"; "")) as $authority |
              if ($authority | startswith("[")) then
                ($authority | capture("^\\[(?<host>[^\\]]+)\\]").host)
              else
                ($authority | split(":")[0])
              end
            ) catch "")
          else
            $s
          end
        end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      . as $root |
      ([
        $root.url,
        $root.uri,
        $root.href,
        (if urlish($root.source) then $root.source else null end),
        $root.domain,
        ($root | argument_containers[] | .url, .uri, .href, (if urlish(.source) then .source else null end), .domain)
      ] | map(select(type == "string" and length > 0)) | map(url_host(.)) | map(select(. != "")) | unique) as $hosts |
      ([
        methodish($root.method),
        methodish($root.http_method),
        methodish($root.request_method),
        ($root | argument_containers[] | methodish(.method), methodish(.http_method), methodish(.request_method))
      ] | map(select(. != "")) | unique) as $methods |
      (($hosts | length) > 1) or (($methods | length) > 1)
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_payload_has_conflicting_mcp_routing_aliases() {
    local payload="$1"
    jq -e '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def str(v): if v == null then "" else (v | tostring) end;
      def route(v):
        str(v) as $s |
        if ($s | contains("\\") or test("[[:cntrl:]]")) then
          ""
        elif ($s | test("^[A-Za-z][A-Za-z0-9+.-]*://")) then
          (try (
            ($s | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<authority>[^/?#]*)").authority | sub("^.*@"; "") | ascii_downcase)
          ) catch "")
        else
          $s
        end;
      def argument_containers:
        [
          obj(.tool_input),
          obj(.input),
          obj(.args),
          obj(obj(.tool_input).args),
          obj(obj(.tool_input).arguments),
          obj(obj(.input).args),
          obj(obj(.input).arguments),
          obj(obj(.args).args),
          obj(obj(.args).arguments)
        ];
      . as $root |
      (obj($root.mcp_context)) as $mcp |
      (($root.hook_event_name // $root.event // "") | ascii_downcase) as $event |
      ([
        $mcp.mcp_server,
        $mcp.mcp_server_name,
        $mcp.server,
        $mcp.server_name,
        $mcp.url,
        $root.mcp_server,
        $root.mcp_server_name,
        (if $event == "beforemcpexecution" then $root.server else null end),
        (if $event == "beforemcpexecution" then $root.url else null end),
        ($root | argument_containers[] | .mcp_server, .mcp_server_name, .server, .server_name)
      ] | map(select(type == "string" and length > 0)) | map(route(.)) | map(select(. != "")) | unique) as $servers |
      ([
        $mcp.mcp_tool,
        $mcp.tool,
        $mcp.tool_name,
        $root.mcp_tool,
        ($root | argument_containers[] | .mcp_tool, .tool, .name, .operation)
      ] | map(select(type == "string" and length > 0)) | unique) as $tools |
      (($servers | length) > 1) or (($tools | length) > 1)
    ' <<< "$payload" > /dev/null 2>&1
}

aport_hook_browser_context_from_payload() {
    local payload="$1"
    local base_context

    base_context="$(aport_hook_context_from_payload "$payload" web 2> /dev/null || printf '{}')"
    [ -n "$base_context" ] || base_context='{}'

    jq -c --argjson base "$base_context" '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def first_string(v): (v | map(select(type == "string" and length > 0)) | .[0] // "");
      def normalize_action(v):
        (v | ascii_downcase) as $a |
        if $a == "" then "navigate"
        elif ($a == "open" or $a == "goto" or $a == "go" or $a == "visit" or $a == "browse") then "navigate"
        else $a
        end;
      (obj(.tool_input) + obj(.input) + obj(.args)) as $ti_base |
      ($ti_base + obj($ti_base.args) + obj($ti_base.arguments)) as $ti |
      first_string([.action, .operation, .type, $ti.action, $ti.operation, $ti.type]) as $action |
      $base + {action: normalize_action($action)}
    ' <<< "$payload"
}

aport_hook_context_from_payload() {
    local payload="$1"
    local kind="$2"
    local default_tool="${3:-}"
    local event_hint="${4:-}"

    # Claude Code's own kill bound for a Bash call that carries no timeout: BASH_DEFAULT_TIMEOUT_MS, capped by
    # BASH_MAX_TIMEOUT_MS, else its documented 120000 ms. The hook inherits these from Claude Code's environment,
    # so the evidence matches the bound the command really runs under. Rounded up so it never understates.
    local claude_default_timeout=120
    if [[ "${BASH_DEFAULT_TIMEOUT_MS:-}" =~ ^[0-9]+$ ]]; then
        claude_default_timeout=$(((BASH_DEFAULT_TIMEOUT_MS + 999) / 1000))
    fi
    if [[ "${BASH_MAX_TIMEOUT_MS:-}" =~ ^[0-9]+$ ]] && (((BASH_MAX_TIMEOUT_MS + 999) / 1000 < claude_default_timeout)); then
        claude_default_timeout=$(((BASH_MAX_TIMEOUT_MS + 999) / 1000))
    fi

    jq -c --arg default_tool "$default_tool" --arg kind "$kind" --arg event_hint "$event_hint" --argjson claude_default_timeout "$claude_default_timeout" '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def str(v): if v == null then "" else (v | tostring) end;
      def arr(v): if (v | type) == "array" then v elif v == null then [] else [v] end;
      def keys_or_empty(v): if (v | type) == "object" then (v | keys | sort) else [] end;
      def first_target(v): (arr(v) | map(select(type == "string" and . != "")) | .[0] // null);
      def target_count(v): (arr(v) | map(select(type == "string" and . != "")) | length);
      def first_string(v): (v | map(select(type == "string" and . != "")) | .[0] // "");
      def positive_int(v):
        if (v | type) == "number" and v > 0 then (v | floor)
        elif (v | type) == "string" and (v | test("^[0-9]+$")) and (v | tonumber) > 0 then (v | tonumber)
        else 1
        end;
      def has_glob(v):
        arr(v)
        | map(select(type == "string" and test("[*?{}\\[]")))
        | length > 0;
      def safe_timeout(v):
        if (v | type) == "number" and v >= 0 then v
        elif (v | type) == "string" and (v | test("^[0-9]+(\\.[0-9]+)?$")) then (v | tonumber)
        else null
        end;
      def safe_timeout_ms(v):
        safe_timeout(v) as $timeout_ms |
        if $timeout_ms == null then null else ($timeout_ms / 1000) end;
      def urlish(v): if (v | type) == "string" then (v | test("^https?://"; "i")) else false end;
      def url_host(v):
        str(v) as $s |
        if ($s | contains("\\") or test("[[:cntrl:]]")) then
          ""
        else
          if ($s | test("^[A-Za-z][A-Za-z0-9+.-]*://")) then
            (try (
              ($s | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<authority>[^/?#]*)").authority | sub("^.*@"; "")) as $authority |
              if ($authority | startswith("[")) then
                ($authority | capture("^\\[(?<host>[^\\]]+)\\]").host)
              else
                ($authority | split(":")[0])
              end
            ) catch "")
          else
            $s
          end
        end;
      def clean_server(v):
        str(v) as $s |
        if ($s | test("^[A-Za-z][A-Za-z0-9+.-]*://")) then
          if ($s | contains("\\") or test("[[:cntrl:]]")) then "" else
          (try (
            ($s | capture("^(?<scheme>[A-Za-z][A-Za-z0-9+.-]*)://(?<authority>[^/?#]*)(?<tail>.*)$")) as $u |
            ($u.authority | sub("^.*@"; "")) as $authority |
            (($u.scheme | ascii_downcase) + "://" + ($authority | ascii_downcase))
          ) catch "")
          end
        else
          if ($s | contains("\\") or test("[[:cntrl:]]") or test("[/@?#]")) then "" else ($s | ascii_downcase | sub("\\.$"; "")) end
        end;
      def malformed_server(v):
        str(v) as $s |
        $s != "" and (
          ($s | contains("\\") or test("[[:cntrl:]]")) or
          (($s | test("^[A-Za-z][A-Za-z0-9+.-]*://") | not) and ($s | test("[/@?#]")))
        );
      def clean_url(v):
        str(v) as $s |
        if $s == "" then ""
        elif ($s | contains("\\") or test("[[:cntrl:]]") or (test("^https?://"; "i") | not)) then ""
        else
          (try (
            ($s | capture("^(?<scheme>[A-Za-z][A-Za-z0-9+.-]*)://(?<authority>[^/?#]*).*$")) as $u |
            ($u.authority | sub("^.*@"; "")) as $authority |
            (($u.scheme | ascii_downcase) + "://" + ($authority | ascii_downcase))
          ) catch "")
        end;
      def strip_functions_prefix(v):
        (v | tostring) as $original |
        if ($original | ascii_downcase | startswith("functions.")) then $original[10:] else $original end;
      def parse_mcp_tool_name($raw):
        strip_functions_prefix($raw) as $name |
        ($name | ascii_downcase) as $lower |
        if ($lower | startswith("mcp__")) then
          ($name | split("__")) as $parts |
          if ($parts | length) >= 3 then {server: $parts[1], tool: ($parts[2:] | join("__"))} else {} end
        elif ($lower | startswith("mcp:")) then
          ($name[4:] | split(":")) as $parts |
          if ($parts | length) >= 2 then {server: $parts[0], tool: ($parts[1:] | join(":"))} else {} end
        elif ($lower | contains("__")) then
          ($name | split("__")) as $parts |
          if ($parts | length) >= 2 then {server: $parts[0], tool: ($parts[1:] | join("__"))} else {} end
        else
          {}
        end;
      def session_operation($raw):
        (strip_functions_prefix($raw) | ascii_downcase) as $name |
        if ($name | contains("interrupt")) then "update"
        elif ($name | contains("close") or contains("stop") or contains("delete")) then "close"
        elif ($name | contains("list") or contains("status") or contains("history") or contains("wait")) then "list"
        elif ($name | contains("resume")) then "resume"
        elif ($name | contains("send") or contains("update") or contains("followup")) then "update"
        elif (
          $name == "agent" or
          $name == "task" or
          $name == "subagent" or
          $name == "subagentstart" or
          $name == "subagent_start" or
          $name == "spawnagent" or
          $name == "spawn_agent" or
          $name == "collaboration.spawnagent" or
          $name == "collaboration.spawn_agent" or
          $name == "createagent" or
          $name == "create_agent" or
          $name == "startagent" or
          $name == "start_agent"
        ) then "create"
        else "other"
        end;
      (obj(.tool_input) + obj(.input) + obj(.args)) as $raw_ti |
      ((obj($raw_ti.args) + obj($raw_ti.arguments)) + $raw_ti) as $ti |
      if $kind == "shell" then
        (
          # The raw values are bound once, so the unit-aware chain and the "carries a timeout key" guard below
          # can never disagree about which fields count.
          ($ti.timeout_seconds // $ti.timeoutSeconds // .timeout // null) as $raw_s |
          ($ti.timeout_ms // $ti.timeoutMs // .timeout_ms // .timeoutMs // null) as $raw_ms |
          ($ti.timeout // null) as $raw_tool_timeout |
          # Claude Code Bash/PowerShell/Monitor send tool_input.timeout in milliseconds;
          # every other harness sends seconds. The evaluator compares seconds.
          (if $event_hint == "claude-code" then
             (safe_timeout_ms($raw_tool_timeout) // safe_timeout($raw_s))
           else
             safe_timeout($raw_tool_timeout // $raw_s)
           end) //
          safe_timeout_ms($raw_ms) //
          # A call that carries no timeout at all runs under the harness default, and that default is what
          # the policy judges; without it a passport that sets max_execution_time denies every ordinary
          # shell command, because the rule requires context.timeout. The default applies only when the
          # call is bounded by it: not when a timeout key is present but malformed (left null, so the
          # evidence check denies), not for a background or persistent call (nothing bounds it), and not
          # for harness tools whose "timeout" is a yield window rather than a kill.
          #   claude-code Bash/PowerShell/Monitor: BASH_DEFAULT_TIMEOUT_MS (capped by BASH_MAX_TIMEOUT_MS),
          #     120000 ms when unset; computed in bash above and passed in as $claude_default_timeout.
          #   codex shell/local_shell: DEFAULT_EXEC_COMMAND_TIMEOUT_MS = 10000 ms hard kill.
          #   codex exec_command/unified_exec: the process outlives the call (write_stdin can drive it);
          #     no default, the passport must not set max_execution_time or the call must carry timeout_ms.
          #   cursor, gemini-cli, goose: their shell tools carry no timeout; treated as unbounded.
          (
            ($raw_tool_timeout != null or $raw_s != null or $raw_ms != null) as $has_timeout_key |
            (($ti.run_in_background == true) or ($ti.persistent == true) or ($ti.background == true)) as $unbounded |
            if $has_timeout_key or $unbounded then null
            elif $event_hint == "claude-code" then $claude_default_timeout
            elif $event_hint == "codex" and ($default_tool | IN("shell", "bash", "local_shell", "localshell", "container_exec", "containerexec")) then 10
            else null
            end
          )
        ) as $command_timeout |
        # `shell` is emitted only when the call names one, and it keeps the RAW value the harness sent,
        # path and all. aport_hook_shell_override_is_trusted has to see the full path: basenaming here
        # turned "/tmp/bash" into "bash" and let an attacker-controlled interpreter pass as trusted while
        # APort judged only the nominal command. The hosted enum (bash, sh, zsh, fish, powershell, cmd)
        # rejects "" and paths, so the basename is taken later, in normalize_api_context, on the way out.
        ({
          command: (
            .command // $ti.command // $ti.cmd // $ti.script // $ti.shell_command // ""
          )
        }
        + (if $command_timeout == null then {} else {timeout: $command_timeout} end)
        + (((.shell // $ti.shell // "") | tostring) as $sh | if $sh == "" then {} else {shell: $sh} end))
      elif $kind == "file_read" then
        {
          file_path: first_string([
            .file_path // .path // $ti.file_path // $ti.path // $ti.absolute_path //
            (if urlish($ti.source) then null else $ti.source end) //
            $ti.dir_path // first_target($ti.paths) // first_target($ti.include) //
            .matcher_context
          ]),
          read_target_count: (
            ([
              (if ($ti.dir_path // "") != "" then 1 else 0 end),
              target_count($ti.paths),
              target_count($ti.include)
            ] | add)
          ),
          has_directory_context: ((($ti.dir_path // "") | type) == "string" and (($ti.dir_path // "") | length) > 0),
          read_has_glob: (has_glob($ti.paths) or has_glob($ti.include) or has_glob($ti.pattern) or has_glob($ti.include_pattern))
        }
      elif $kind == "file_write" then
        (arr($ti.edits) + arr($ti.replacements) + arr($ti.changes)) as $edits |
        (($ti.notebook_path // $ti.notebookPath // null) != null) as $is_notebook |
        (($ti.command // $ti.edit_mode // $ti.editMode // .command // "") | tostring | ascii_downcase) as $write_operation |
        (positive_int($ti.expected_replacements // $ti.expectedReplacements // null)) as $replacement_count |
        (str($ti.content // $ti.text // $ti.file_text // $ti.new_source // $ti.newSource // $ti.new_string // $ti.new_str // $ti.replacement // "")) as $direct_new_unit_text |
        (
          if $is_notebook then ($direct_new_unit_text | tojson | utf8bytelength)
          else ($direct_new_unit_text | utf8bytelength)
          end
        ) as $direct_new_unit_bytes |
        (if $replacement_count > 1 then ($direct_new_unit_bytes * $replacement_count) else $direct_new_unit_bytes end) as $direct_new_bytes |
        (($edits | map(
          (positive_int(.expected_replacements // .expectedReplacements // null)) as $count |
          (str(.new_string // .newText // .new_str // .new_source // .newSource // .replacement // .text // .file_text // .content // "") | utf8bytelength) * $count
        ) | add) // 0) as $edit_new_bytes |
        (
          if (($ti.old_string // $ti.old_str // $ti.old_content // null) != null) then
            ((str($ti.old_string // $ti.old_str // $ti.old_content // "") | utf8bytelength) * $replacement_count)
          elif (($edits | map(has("old_string") or has("oldText") or has("old_str") or has("old_content")) | any) // false) then
            (($edits | map(
              (positive_int(.expected_replacements // .expectedReplacements // null)) as $count |
              (str(.old_string // .oldText // .old_str // .old_content // "") | utf8bytelength) * $count
            ) | add) // 0)
          else
            null
          end
        ) as $old_bytes |
        {
          file_path: first_string([
            .file_path // .path // $ti.file_path // $ti.notebook_path // $ti.notebookPath // $ti.path // $ti.args.file_path // $ti.args.path // $ti.absolute_path // .matcher_context // ""
          ]),
          content_length: ([$direct_new_bytes, $edit_new_bytes] | max),
          old_content_length: $old_bytes,
          write_operation: $write_operation,
          notebook: $is_notebook,
          notebook_source_line_count: (if $is_notebook then (($direct_new_unit_text | split("\n")) | length) else 0 end),
          replace_all: (($ti.replace_all // $ti.replaceAll // false) == true or (($edits | map((.replace_all // .replaceAll // false) == true) | any) // false))
        }
      elif $kind == "web" then
        (.url // $ti.url // (if urlish($ti.source) then $ti.source else null end) // "") as $raw_url |
        (.domain // $ti.domain // "") as $raw_domain |
        clean_url($raw_url) as $safe_url |
        url_host($safe_url) as $safe_host |
        url_host($raw_domain) as $domain_host |
        {
          url: $safe_url,
          domain: (if $safe_url != "" then $safe_host elif $raw_url != "" then "" else $domain_host end),
          invalid_url: ($raw_url != "" and $safe_url == ""),
          domain_mismatch: ($safe_host != "" and $domain_host != "" and $domain_host != $safe_host),
          method: (.method // $ti.method // "GET")
        }
      elif $kind == "mcp" then
        (obj(.mcp_context)) as $mcp |
        ((.hook_event_name // .event // $event_hint // "") | ascii_downcase) as $event |
        strip_functions_prefix($default_tool) as $default_tool_clean |
        ($default_tool_clean | ascii_downcase | gsub("\\s+"; "")) as $tool_key |
        ($tool_key == "readmcpresourcetool" or $tool_key == "read_mcp_resource_tool") as $is_resource_read |
        ($tool_key == "callmcptool" or $tool_key == "call_mcp_tool") as $is_generic_call |
        ($is_resource_read or $is_generic_call) as $allows_input_routing |
        (parse_mcp_tool_name($default_tool)) as $parsed |
        (
          if $event == "beforemcpexecution" and $default_tool_clean != "" and ($is_resource_read | not) and ($is_generic_call | not) then
            $default_tool_clean
          else
            null
          end
        ) as $native_tool |
        (
          $mcp.server_name // $mcp.server // $mcp.url //
          .mcp_server_name // (if (.mcp_server | type) == "string" then .mcp_server else null end) //
          (if $event == "beforemcpexecution" then (.server // .url) else null end) //
          $parsed.server //
          # Claude Code (v2.1.274+) sends mcp_server as {name, source}; use the host-reported
          # name when the tool name carries no mcp__<server>__ prefix to parse.
          (if (.mcp_server | type) == "object" and ((.mcp_server.name // "") | type) == "string" and (.mcp_server.name // "") != ""
             then .mcp_server.name else null end) //
          (if $allows_input_routing then ($ti.server // $ti.mcp_server // $ti.mcp_server_name) else null end) //
          ""
        ) as $raw_server |
        (
          safe_timeout($ti.timeout // $ti.timeout_seconds // $ti.timeoutSeconds // .timeout // null) //
          safe_timeout_ms($ti.timeout_ms // $ti.timeoutMs // .timeout_ms // .timeoutMs // null)
        ) as $mcp_timeout |
        ({
          server: clean_server($raw_server),
          mcp_server: clean_server($raw_server),
          invalid_server: malformed_server($raw_server),
          tool: (
            $mcp.tool_name // $mcp.tool // $parsed.tool // $native_tool //
            $ti.tool // $ti.mcp_tool // $ti.name // $ti.operation // .mcp_tool // .tool //
            (if $is_resource_read then "resources.read" else $default_tool end)
          ),
          mcp_tool: (
            $mcp.tool_name // $mcp.tool // $parsed.tool // $native_tool //
            $ti.tool // $ti.mcp_tool // $ti.name // $ti.operation // .mcp_tool // .tool //
            (if $is_resource_read then "resources.read" else $default_tool end)
          ),
          parameters: {},
          parameter_keys: keys_or_empty($ti),
          parameter_count: (keys_or_empty($ti) | length)
        } + (if $mcp_timeout == null then {} else {timeout: $mcp_timeout} end))
      elif $kind == "session" then
        (
          .description // .task // .message //
          $ti.description // $ti.prompt // $ti.task // $ti.message // ""
        ) as $description |
        session_operation($default_tool) as $session_operation |
        {
          description_length: (str($description) | length),
          session_operation: $session_operation,
          session_tracking: (if $event_hint == "codex" then "persistent" else "host_active_count" end),
          hook_event: (.hook_event_name // .event // ""),
          active_session_count: (.active_session_count // .current_active_sessions // null),
          parent_session_id: (.session_id // .sessionId // ""),
          session_call_id: (.tool_call_id // .toolCallId // .tool_use_id // .toolUseId // .request_id // ""),
          session_id: (
            if $session_operation == "create" then
              ""
            else
              ($ti.child_session_id // $ti.childSessionId // .subagent_id // $ti.subagent_id // $ti.agent_id // $ti.agentId // $ti.id // $ti.session_id // $ti.sessionId // .target_session_id // .targetSessionId // "")
            end
          ),
          subagent_type: (.subagent_type // $ti.subagent_type // $ti.agent_type // "")
        }
      else
        {}
      end
    ' <<< "$payload" 2> /dev/null || printf '{}'
}

aport_hook_extract_patch_paths() {
    local payload="$1"
    printf '%s' "$payload" \
        | jq -c '
          (.tool_input.command // .tool_input.patch // .command // .patch // "") |
          split("\n") |
          map(
            select(test("^\\*\\*\\* ((Update|Add|Delete) File|Move to): ")) |
            sub("^\\*\\*\\* ((Update|Add|Delete) File|Move to): "; "")
          ) |
          map(select(. != "")) |
          unique
        ' 2> /dev/null || true
}
