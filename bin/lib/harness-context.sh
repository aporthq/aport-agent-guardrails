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

aport_hook_context_from_payload() {
    local payload="$1"
    local kind="$2"
    local default_tool="${3:-}"
    local event_hint="${4:-}"

    jq -c --arg default_tool "$default_tool" --arg kind "$kind" --arg event_hint "$event_hint" '
      def obj(v):
        if (v | type) == "object" then v
        elif (v | type) == "string" then (try (v | fromjson) catch {})
        else {}
        end;
      def str(v): if v == null then "" else (v | tostring) end;
      def arr(v): if (v | type) == "array" then v elif v == null then [] else [v] end;
      def keys_or_empty(v): if (v | type) == "object" then (v | keys | sort) else [] end;
      def first_target(v): (arr(v) | map(select(type == "string" and . != "")) | .[0] // "");
      def target_count(v): (arr(v) | map(select(type == "string" and . != "")) | length);
      def has_glob(v):
        arr(v)
        | map(select(type == "string" and test("[*?\\[]")))
        | length > 0;
      def safe_timeout(v):
        if (v | type) == "number" and v >= 0 then v
        elif (v | type) == "string" and (v | test("^[0-9]+(\\.[0-9]+)?$")) then (v | tonumber)
        else null
        end;
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
            (($u.tail | split("?") | .[0] // "") | split("#") | .[0] // "") as $path |
            (($u.scheme | ascii_downcase) + "://" + ($authority | ascii_downcase) + $path)
          ) catch "")
          end
        else
          $s
        end;
      def clean_url(v):
        clean_server(v);
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
        if ($name | contains("close") or contains("stop") or contains("delete") or contains("interrupt")) then "close"
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
      (obj(.tool_input) + obj(.input) + obj(.args)) as $ti |
      if $kind == "shell" then
        {
          command: (
            .command // $ti.command // $ti.cmd // $ti.script // $ti.shell_command // ""
          )
        }
      elif $kind == "file_read" then
        {
          file_path: (
            .file_path // .path // $ti.file_path // $ti.path // $ti.absolute_path //
            (if urlish($ti.source) then null else $ti.source end) //
            $ti.dir_path // first_target($ti.paths) // first_target($ti.include) //
            .matcher_context // ""
          ),
          read_target_count: (
            if ($ti.dir_path // "") != "" then 1
            else ([target_count($ti.paths), target_count($ti.include)] | add)
            end
          ),
          read_has_glob: (has_glob($ti.paths) or has_glob($ti.include) or has_glob($ti.pattern) or has_glob($ti.include_pattern))
        }
      elif $kind == "file_write" then
        {
          file_path: (
            .file_path // .path // $ti.file_path // $ti.path // $ti.absolute_path // .matcher_context // ""
          ),
          content_length: (str($ti.content // $ti.text // $ti.new_string // $ti.replacement // "") | length),
          old_content_length: (str($ti.old_string // $ti.old_content // "") | length)
        }
      elif $kind == "web" then
        (.url // $ti.url // (if urlish($ti.source) then $ti.source else null end) // "") as $raw_url |
        (.domain // $ti.domain // "") as $raw_domain |
        clean_url($raw_url) as $safe_url |
        url_host($safe_url) as $safe_host |
        url_host($raw_domain) as $domain_host |
        {
          url: $safe_url,
          domain: (if $safe_url != "" then $safe_host else $raw_domain end),
          invalid_url: ($raw_url != "" and $safe_url == ""),
          domain_mismatch: ($safe_host != "" and $domain_host != "" and $domain_host != $safe_host),
          method: (.method // $ti.method // "GET")
        }
      elif $kind == "mcp" then
        (obj(.mcp_context)) as $mcp |
        ((.hook_event_name // .event // $event_hint // "") | ascii_downcase) as $event |
        (strip_functions_prefix($default_tool) | ascii_downcase | gsub("\\s+"; "")) as $tool_key |
        ($tool_key == "readmcpresourcetool" or $tool_key == "read_mcp_resource_tool") as $is_resource_read |
        ($tool_key == "callmcptool" or $tool_key == "call_mcp_tool") as $is_generic_call |
        ($is_resource_read or $is_generic_call) as $allows_input_routing |
        (parse_mcp_tool_name($default_tool)) as $parsed |
        {
          server: clean_server(
            $mcp.server_name // $mcp.server // $mcp.url //
            .mcp_server_name // .mcp_server //
            (if $event == "beforemcpexecution" then (.server // .url) else null end) //
            $parsed.server //
            (if $allows_input_routing then ($ti.server // $ti.mcp_server // $ti.mcp_server_name) else null end) //
            ""
          ),
          mcp_server: clean_server(
            $mcp.server_name // $mcp.server // $mcp.url //
            .mcp_server_name // .mcp_server //
            (if $event == "beforemcpexecution" then (.server // .url) else null end) //
            $parsed.server //
            (if $allows_input_routing then ($ti.server // $ti.mcp_server // $ti.mcp_server_name) else null end) //
            ""
          ),
          tool: (
            $mcp.tool_name // $mcp.tool // $parsed.tool //
            $ti.tool // $ti.mcp_tool // $ti.name // $ti.operation // .mcp_tool // .tool //
            (if $is_resource_read then "resources.read" else $default_tool end)
          ),
          mcp_tool: (
            $mcp.tool_name // $mcp.tool // $parsed.tool //
            $ti.tool // $ti.mcp_tool // $ti.name // $ti.operation // .mcp_tool // .tool //
            (if $is_resource_read then "resources.read" else $default_tool end)
          ),
          timeout: safe_timeout($ti.timeout // $ti.timeout_seconds // $ti.timeoutSeconds // $ti.timeout_ms // $ti.timeoutMs // .timeout // null),
          parameter_keys: keys_or_empty($ti),
          parameter_count: (keys_or_empty($ti) | length)
        }
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
          active_session_count: (.active_session_count // .current_active_sessions // $ti.active_session_count // $ti.current_active_sessions // null),
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
