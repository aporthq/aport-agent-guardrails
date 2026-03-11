# PRD: APort Guardrail for Claude Code

**Status:** Draft — Awaiting Uchi Review  
**Branch:** `feature/claude-code-guardrail` (cloned at `/tmp/tmp.rlzab9WHmI/aport-agent-guardrails`)  
**Version Target:** v1.0.13  
**Priority:** High — motivated by HN thread [47256614](https://news.ycombinator.com/item?id=47256614) (Claude Code sandbox escape)  
**Author:** Chief of Staff  
**Research:** Full forensic codebase audit (2026-03-08) + Claude Code official docs verified  

---

## 0. Audit Trail — What Was Verified and How

Every claim in this PRD was verified from two sources:

| Claim | Verified From |
|---|---|
| Hook output format (`hookSpecificOutput`) | [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — live fetch 2026-03-08 |
| Hook input schema (`tool_name`, `tool_input`) | Same official docs — example `jq -r '.tool_input.command'` |
| Settings file format and location (`~/.claude/settings.json`) | Same official docs |
| Cursor output format (`permission: allow/deny`) | `bin/aport-cursor-hook.sh` — read directly |
| Cursor settings format (`hooks.json` with `beforeShellExecution`) | `bin/frameworks/cursor.sh` — read directly |
| Release process | `RELEASE.md` + `.github/workflows/release.yml` — read directly |
| Version sync scope | `scripts/sync-version.mjs` — read directly (Python only, not workspace packages) |
| `detect.sh` current state | `bin/lib/detect.sh` — read directly |
| `aport-resolve-paths.sh` probe list | `bin/aport-resolve-paths.sh` — read directly |
| `config.sh` `get_config_dir()` | `bin/lib/config.sh` — read directly |
| Changeset fixed group | `.changeset/config.json` — read directly |
| `mapToolToPolicy()` current coverage | `extensions/openclaw-aport/index.ts` — read directly |
| Package versions on each tag | `git show v1.0.12:packages/cursor/package.json` |
| CI publish step | `.github/workflows/release.yml` — read directly |

---

## 1. Why This Exists

A developer shared a Conductor.build session where Claude Code said "That file is outside my writable sandbox" then immediately escaped the sandbox when told to. The guardrail was advisory — inside Claude's reasoning context, where the model can be reasoned out of it.

Claude Code's `PreToolUse` hook runs as a separate process before each tool executes, outside Claude's context entirely. The model cannot reason past it. That's what this integration makes real for Claude Code users.

APort's core evaluator (`aport-guardrail-bash.sh`) already works for this. The work is the Claude Code-specific wrapper that maps Claude Code's tool names to APort policies and speaks Claude Code's exact hook protocol.

---

## 2. Claude Code Hooks — Verified from Official Docs

Source: `https://docs.anthropic.com/en/docs/claude-code/hooks` → redirects to `code.claude.com/docs/en/hooks`  
Fetched: 2026-03-08

### 2.1 Settings File

```
~/.claude/settings.json          ← user-level (applies globally, use this for APort)
.claude/settings.json            ← project-level (applies only in that directory)
```

**This is NOT `~/.cursor/hooks.json`.** Completely different location and format.

### 2.2 Settings JSON Format

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/hook.sh"
          }
        ]
      }
    ]
  }
}
```

Key facts:
- Key is `PreToolUse` (capital P, T, U) — confirmed from docs
- `matcher` is a tool name string or `"*"` for all tools
- For APort: use `"matcher": "*"` to cover all tool types (fail-closed approach)
- **Absolute paths required** — relative paths break when Claude Code runs from a different working directory

**This is NOT the Cursor format** which uses `"version": 1, "hooks": {"beforeShellExecution": [...], "preToolUse": [...]}` in `~/.cursor/hooks.json`. The installer function `_write_cursor_hooks_file()` in `bin/frameworks/cursor.sh` cannot be shared.

### 2.3 Hook Input Schema (stdin, per official docs)

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/build"
  }
}
```

Official docs example: `jq -r '.tool_input.command'` — note `tool_input` is the field name (not `input`).

### 2.4 Hook Output Schema (stdout)

**Allow:** Exit 0. No stdout output needed. Empty stdout is fine.

**Deny (exact format from official docs):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🛡️ APort: system.command.execute.v1 — rm -rf pattern blocked"
  }
}
```

**This is NOT the Cursor hook format**, which outputs:
```json
{"permission":"deny","allowed":false,"agentMessage":"...","reason":"..."}
```

These are incompatible. The hook script must output the Claude Code format.

Implementation note: output the JSON AND exit 2. Claude Code reads `hookSpecificOutput.permissionDecision`; exit 2 is a belt-and-suspenders fallback. The existing cursor hook already uses exit 2 — keep that pattern.

### 2.5 Claude Code Tool Names and `tool_input` Fields

These are the exact `tool_name` values Claude Code sends in the hook input:

| `tool_name` | Key `tool_input` field | APort Policy | Default |
|---|---|---|---|
| `Bash` | `command` | `system.command.execute.v1` | Enforce |
| `Read` | `file_path` | `data.file.read.v1` | **Allow by default** |
| `Write` | `file_path`, `content` | `data.file.write.v1` | Enforce |
| `Edit` | `file_path`, `old_string`, `new_string` | `data.file.write.v1` | Enforce |
| `MultiEdit` | `file_path`, `edits` | `data.file.write.v1` | Enforce |
| `Glob` | `pattern`, `path` | `data.file.read.v1` | **Allow by default** |
| `LS` | `path` | `data.file.read.v1` | **Allow by default** |
| `Grep` | `pattern`, `path` | `data.file.read.v1` | **Allow by default** |
| `WebSearch` | `query` | `web.fetch.v1` | Enforce |
| `WebFetch` | `url` | `web.fetch.v1` | Enforce |
| `Browser` | `url` | `web.browser.v1` | Enforce |
| `TodoRead` | *(none)* | `data.file.read.v1` | **Allow by default** |
| `TodoWrite` | `todos` | `data.file.write.v1` | Enforce |
| `Task` | `description`, `prompt` | `agent.session.create.v1` | Enforce |
| `mcp__<server>__<tool>` | varies | `mcp.tool.execute.v1` | Enforce |

**Read-family allow-by-default is intentional.** A Claude Code session that can't read files is barely functional. The HN incident was about Bash escaping a sandbox — not reads. APort's Claude Code value proposition is enforcing writes, executes, web calls, and subagents.

**Read-family tools skip the evaluator entirely** — they exit 0 immediately without calling `aport-guardrail-bash.sh`. This avoids ~40ms overhead on every file read.

**Unknown tool names fail-closed** — denied if not in the mapping table above. This is the correct safe default.

### 2.6 The `--dangerously-skip-permissions` Problem

This flag bypasses ALL hooks including `PreToolUse`. When set, APort is completely inactive. This cannot be mitigated technically — it's an intentional override. Must be documented prominently. Do not guard against it in code — just document it.

### 2.7 Current Cursor Docs Incorrectly Claims Claude Code Compatibility

`docs/frameworks/cursor.md` currently says:
> "Claude Code: ~/.claude/settings.json, same PreToolUse style. Our script accepts Cursor- and Copilot-style payloads..."
> "Same script works for VS Code + Copilot and Claude Code — see: docs/frameworks/cursor.md"

This is wrong. The cursor hook outputs `permission: allow/deny` — Claude Code expects `hookSpecificOutput.permissionDecision`. Users following this doc would get a hook that doesn't actually block anything in Claude Code (wrong output format means Claude Code ignores the denial).

The PRD must fix this. `docs/frameworks/cursor.md` needs a correction notice pointing to the dedicated Claude Code integration.

---

## 3. Codebase Forensics — Verified State of Every Relevant File

### 3.1 What Already Works (Reusable, No Changes)

| File | Status | Notes |
|---|---|---|
| `bin/aport-guardrail-bash.sh` | ✅ Reuse as-is | Core evaluator, called by all hooks |
| `bin/aport-guardrail-api.sh` | ✅ Reuse as-is | API mode evaluator |
| `bin/aport-create-passport.sh` | ✅ Reuse as-is | Passport wizard, shared across frameworks |
| `bin/aport-status.sh` | ✅ Reuse as-is | Status/audit viewer |
| `packages/core/` | ✅ Reuse as-is | `Evaluator` class, exported by all framework packages |
| `extensions/openclaw-aport/index.ts` | ✅ Mostly reuse | `mapToolToPolicy()` already handles `bash`, `read`, `write`, `edit`, `web_fetch`, `websearch`, `browser` — see gap analysis in Section 3.3 |

### 3.2 What Cannot Be Reused (Incompatible with Claude Code)

| File | Problem |
|---|---|
| `bin/aport-cursor-hook.sh` | Outputs `permission: allow/deny` — Claude Code expects `hookSpecificOutput.permissionDecision`. Also only maps `command` field, not `tool_name`. New script needed. |
| `bin/frameworks/cursor.sh` | Writes `~/.cursor/hooks.json` with Cursor format. Claude Code needs `~/.claude/settings.json` with different JSON structure. New installer needed. |
| `_write_cursor_hooks_file()` function | Cursor-format JSON. Cannot reuse. |

### 3.3 Gaps in `mapToolToPolicy()` (extensions/openclaw-aport/index.ts)

Current `mapToolToPolicy()` lowercases all input and checks. Gaps for Claude Code PascalCase tools when lowercased:

| Claude Code tool (lowercased) | Current coverage | Gap? |
|---|---|---|
| `bash` | ✅ `tool === "bash"` → `system.command.execute.v1` | No gap |
| `read` | ✅ `tool === "read"` → `data.file.read.v1` | No gap |
| `write` | ✅ `tool === "write"` → `data.file.write.v1` | No gap |
| `edit` | ✅ `tool === "edit"` → `data.file.write.v1` | No gap |
| `multiedit` | ❌ No mapping | **Gap** |
| `glob` | ❌ No mapping | **Gap** |
| `ls` | ❌ No mapping | **Gap** |
| `grep` | ❌ No mapping | **Gap** |
| `websearch` | ✅ `tool === "websearch"` → `web.fetch.v1` | No gap |
| `webfetch` | ✅ `tool === "webfetch"` → `web.fetch.v1` | No gap |
| `browser` | ✅ `tool === "browser"` → `web.browser.v1` | No gap |
| `todoread` | ❌ No mapping | **Gap** |
| `todowrite` | ❌ No mapping | **Gap** |
| `task` | ❌ No mapping | **Gap** |
| `mcp__*` (double underscore) | ❌ Existing code checks `tool.startsWith("mcp.")` (single dot) — does NOT match `mcp__*` | **Gap** |

6 gaps to fill: `multiedit`, `glob`, `ls`, `grep`, `todoread`, `todowrite`, `task`, `mcp__` prefix.

### 3.4 Path Resolver Gaps (`bin/aport-resolve-paths.sh`)

Current probe list (exact order from source):
```bash
for candidate in "$HOME/.cursor" "$HOME/.openclaw" "$HOME/.aport/langchain" "$HOME/.aport/crewai" "$HOME/.n8n"; do
```

`$HOME/.claude` is NOT in the list. Claude Code users without `OPENCLAW_PASSPORT_FILE` set would fall through to the default `$HOME/.openclaw`. Need to add `$HOME/.claude` to the probe list (first position — Claude Code-specific installs should take priority).

### 3.5 `get_config_dir()` Gap (`bin/lib/config.sh`)

Current cases:
```bash
case "$framework" in
    openclaw) echo "${APORT_OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}" ;;
    langchain) echo "${APORT_LANGCHAIN_CONFIG_DIR:-$HOME/.aport/langchain}" ;;
    crewai)    echo "${APORT_CREWAI_CONFIG_DIR:-$HOME/.aport/crewai}" ;;
    n8n)       echo "${APORT_N8N_CONFIG_DIR:-$HOME/.n8n}" ;;
    cursor)    echo "${APORT_CURSOR_CONFIG_DIR:-$HOME/.cursor}" ;;
    *)         echo "${APORT_CONFIG_DIR:-$HOME/.aport}" ;;
esac
```

`claude-code` is missing. Falls through to `$HOME/.aport` default. Must add.

### 3.6 `detect.sh` Gap

Current detection only checks:
- `pyproject.toml` for langchain/crewai
- `package.json` for openclaw
- `requirements.txt` for langchain/crewai

No Claude Code detection. Must add.

### 3.7 `bin/agent-guardrails` Error Messages

Current: `"Supported: openclaw | langchain | crewai | cursor (n8n coming soon)"`  
Must add `claude-code`.

### 3.8 Changeset Config (`.changeset/config.json`)

Current `fixed` group:
```json
"fixed":[["@aporthq/aport-agent-guardrails-core","@aporthq/aport-agent-guardrails-langchain","@aporthq/aport-agent-guardrails-crewai","@aporthq/aport-agent-guardrails-n8n","@aporthq/aport-agent-guardrails-cursor"]]
```

`@aporthq/aport-agent-guardrails-claude-code` must be added to this fixed group so it bumps in sync with all other packages when a changeset is run.

### 3.9 Release CI (`release.yml`)

Current publish step:
```yaml
npm publish -w @aporthq/aport-agent-guardrails-core --access public
npm publish -w @aporthq/aport-agent-guardrails-langchain --access public
npm publish -w @aporthq/aport-agent-guardrails-crewai --access public
npm publish -w @aporthq/aport-agent-guardrails-cursor --access public
```

Must add: `npm publish -w @aporthq/aport-agent-guardrails-claude-code --access public`

Also: the GitHub Release notes template hardcodes `cursor` install command but not `claude-code`. Must update.

---

## 4. Release Process — Exact Steps (from RELEASE.md + CI)

**CRITICAL: `npm run sync-version` does NOT update workspace `package.json` files.** It only updates Python `pyproject.toml` files. Workspace package versions are managed separately.

The release process verified from `RELEASE.md`:

```bash
# 1. All work on feature/claude-code-guardrail branch (already created)

# 2. Before opening PRs, in the feature branch:
#    a. Add changeset (drives version bump for all packages in fixed group)
npx changeset   # choose "patch", write "Add Claude Code PreToolUse hook integration"
#    b. Apply the changeset
npm run version
#       This runs: changeset version && node scripts/sync-version.mjs
#       changeset version bumps workspace package.json files (all in fixed group)
#       sync-version.mjs updates Python pyproject.toml files
#    c. Manually update CHANGELOG.md (changeset generates a fragment; incorporate it into CHANGELOG.md)
#    d. Commit everything

# 3. PR flow: feature/claude-code-guardrail → dev → staging → main

# 4. After merge to main:
git checkout main && git pull origin main
git tag v1.0.13   # MUST match package.json "version" (CI verifies this)
git push origin v1.0.13

# 5. CI auto-runs: npm publish (all packages) + PyPI publish + GitHub Release creation
```

**Version verification in CI (from release.yml):**
```yaml
TAG_VERSION="${GITHUB_REF#refs/tags/v}"
ROOT_VERSION=$(node -p "require('./package.json').version")
if [ "$TAG_VERSION" != "$ROOT_VERSION" ]; then exit 1; fi
```
If the tag doesn't match `package.json`, CI fails immediately. Always bump version before tagging.

---

## 5. What to Build — Complete File List

### 5.1 New Files

#### `bin/aport-claude-code-hook.sh` ← Primary deliverable

Runtime hook. Claude Code calls this before every tool use.

**Key implementation logic (pseudocode with exact details):**

```bash
#!/usr/bin/env bash
# APort Claude Code hook: reads tool_name + tool_input from JSON stdin,
# maps to APort policy, calls guardrail, outputs hookSpecificOutput deny or exit 0.
# Exit 0 = allow, exit 2 = block. Other exits = hook error (Claude Code may fail-open).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARDRAIL="$ROOT_DIR/bin/aport-guardrail-bash.sh"

# Path resolver: probes ~/.claude, ~/.cursor, ~/.openclaw, etc.
. "$ROOT_DIR/bin/aport-resolve-paths.sh"

# Read stdin
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0  # No input = allow (fail-open for bad input)

# Parse tool_name and tool_input (requires jq)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')

# Deny helper: outputs hookSpecificOutput JSON and exits 2
deny() {
  local reason="$1"
  jq -n --arg reason "$reason" \
    --arg event "PreToolUse" \
    '{hookSpecificOutput:{hookEventName:$event,permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 2
}

# Policy routing based on tool_name
POLICY=""
CONTEXT_JSON="{}"
case "$TOOL_NAME" in
  Bash)
    POLICY="system.command.execute"
    CONTEXT_JSON=$(echo "$TOOL_INPUT" | jq -c '{command: .command}')
    ;;
  Read|Glob|LS|Grep|TodoRead)
    # Allow by default — exit without calling evaluator (saves ~40ms per file read)
    exit 0
    ;;
  Write|Edit|MultiEdit|TodoWrite)
    POLICY="data.file.write"
    CONTEXT_JSON=$(echo "$TOOL_INPUT" | jq -c '{file_path: .file_path}')
    ;;
  WebSearch|WebFetch)
    POLICY="web.fetch"
    CONTEXT_JSON=$(echo "$TOOL_INPUT" | jq -c '{url: (.url // .query)}')
    ;;
  Browser)
    POLICY="web.browser"
    CONTEXT_JSON=$(echo "$TOOL_INPUT" | jq -c '{url: .url}')
    ;;
  Task)
    POLICY="agent.session.create"
    CONTEXT_JSON=$(echo "$TOOL_INPUT" | jq -c '{description: (.description // .prompt)}')
    ;;
  mcp__*)
    # Claude Code MCP tools use mcp__<server>__<tool> naming (double underscore)
    POLICY="mcp.tool.execute"
    CONTEXT_JSON="$TOOL_INPUT"
    ;;
  unknown|*)
    # Unknown tool: fail-closed (deny)
    deny "🛡️ APort: unknown tool '$TOOL_NAME' — fail-closed policy"
    ;;
esac

# Call core evaluator
set +e
"$GUARDRAIL" "$POLICY" "$CONTEXT_JSON" 2>/dev/null
GUARDRAIL_EXIT=$?
set -e

if [ "$GUARDRAIL_EXIT" -eq 0 ]; then
  exit 0  # Allow — no output needed
fi

# Deny: read reason from decision file
REASON="Policy denied this action."
if [ -f "$OPENCLAW_DECISION_FILE" ]; then
  R=$(jq -r '.reasons[0].message // empty' "$OPENCLAW_DECISION_FILE" 2>/dev/null)
  [ -n "$R" ] && REASON="$R"
fi
deny "🛡️ APort: $REASON"
```

#### `bin/frameworks/claude-code.sh` ← Installer

Follows pattern of `bin/frameworks/cursor.sh`. Calls `get_config_dir claude-code` (which returns `~/.claude` after adding the case). Writes `~/.claude/settings.json`.

**Critical difference from cursor installer — the JSON format:**

```bash
_write_claude_settings() {
    local file="$1"
    local cmd="$2"
    
    # Merge with existing settings.json without clobbering other settings
    if [ -f "$file" ] && command -v jq &>/dev/null; then
        EXISTING=$(cat "$file")
        if echo "$EXISTING" | jq -e '.hooks' &>/dev/null; then
            # Merge: add APort to PreToolUse array, dedup by command
            jq -c --arg cmd "$cmd" '
              (.hooks.PreToolUse // []) as $p |
              .hooks.PreToolUse = ($p | map(select(
                .hooks[0].command != $cmd
              )) | . + [{"matcher":"*","hooks":[{"type":"command","command":$cmd}]}])
            ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            return
        fi
    fi
    
    # Write fresh settings
    jq -n --arg cmd "$cmd" '{
      hooks: {
        PreToolUse: [{"matcher":"*","hooks":[{"type":"command","command":$cmd}]}]
      }
    }' > "$file"
}
```

Hook script path: `$ROOT_FOR_HOOK/bin/aport-claude-code-hook.sh` (not the cursor hook).

#### `packages/claude-code/src/index.ts` ← Thin TypeScript package

```typescript
/**
 * @aporthq/aport-agent-guardrails-claude-code
 * Claude Code: re-exports Evaluator and helpers for hook path.
 * Runtime integration is via the bash hook installed by:
 *   npx @aporthq/aport-agent-guardrails claude-code
 */

import path from 'node:path';
import os from 'node:os';
import { Evaluator } from '@aporthq/aport-agent-guardrails-core';

export { Evaluator };

/** Default path to the APort Claude Code hook script. */
export function getHookPath(): string {
  return (
    process.env.APORT_CLAUDE_CODE_HOOK_SCRIPT ??
    path.join(os.homedir(), '.claude', 'aport-claude-code-hook.sh')
  );
}
```

#### `packages/claude-code/package.json`

```json
{
  "name": "@aporthq/aport-agent-guardrails-claude-code",
  "version": "1.0.13",
  "description": "APort guardrails for Claude Code — PreToolUse hook",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "tsc",
    "clean": "rm -rf dist"
  },
  "keywords": ["aport", "claude-code", "claude", "anthropic", "guardrails", "ai-agent"],
  "author": "APort Technologies Inc.",
  "license": "Apache-2.0",
  "dependencies": {
    "@aporthq/aport-agent-guardrails-core": ">=1.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0"
  },
  "publishConfig": { "access": "public" }
}
```

`packages/claude-code/tsconfig.json`: copy from `packages/cursor/tsconfig.json` verbatim.

#### `docs/frameworks/claude-code.md` ← User docs

Sections mirroring cursor.md structure:
1. How it works (PreToolUse hook, not a prompt, why this matters)
2. Setup (`npx @aporthq/aport-agent-guardrails claude-code`)
3. What's protected (tool table from Section 2.5)
4. What's NOT protected (`--dangerously-skip-permissions`, you typing in your terminal)
5. Testing the guardrail (echo JSON to hook script manually)
6. Audit log location (`~/.claude/aport/audit.log`)
7. Suspend/resume (passport status)
8. Why this is different from `CLAUDE.md` (the whole point — link to HN 47256614)

#### `integrations/claude-code/README.md` ← Integration marker

One page: quick-start + link to `docs/frameworks/claude-code.md`.

---

### 5.2 Modified Files

#### `bin/aport-resolve-paths.sh`

Add `$HOME/.claude` to probe list **before** `$HOME/.cursor` (Claude Code users should get Claude's data dir, not Cursor's):

```bash
# Before (current):
for candidate in "$HOME/.cursor" "$HOME/.openclaw" "$HOME/.aport/langchain" "$HOME/.aport/crewai" "$HOME/.n8n"; do

# After:
for candidate in "$HOME/.claude" "$HOME/.cursor" "$HOME/.openclaw" "$HOME/.aport/langchain" "$HOME/.aport/crewai" "$HOME/.n8n"; do
```

#### `bin/lib/config.sh` — `get_config_dir()`

Add `claude-code` case **before** the `*` wildcard:

```bash
claude-code) echo "${APORT_CLAUDE_CODE_CONFIG_DIR:-$HOME/.claude}" ;;
```

#### `bin/lib/detect.sh` — `detect_frameworks_list()`

Add Claude Code detection block after the n8n/requirements.txt section:

```bash
# Claude Code: detect claude binary or ~/.claude directory
if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
    list+=(claude-code)
fi
```

**Note:** `~/.claude` directory may exist on machines that have other Anthropic tools installed. If this causes false positives in testing, fall back to checking `command -v claude` only.

#### `bin/agent-guardrails`

Two changes:
1. Error message: `"Supported: openclaw, langchain, crewai, cursor, claude-code (n8n coming soon)"`
2. n8n note: update from `"n8n coming soon"` to still say n8n, just add claude-code before it

#### `extensions/openclaw-aport/index.ts` — `mapToolToPolicy()`

Add 6 missing Claude Code tool name mappings after the existing write/edit block:

```typescript
// Claude Code tool names not yet mapped
if (tool === "multiedit") return "data.file.write.v1";
if (tool === "glob" || tool === "ls" || tool === "grep") return "data.file.read.v1";
if (tool === "todoread") return "data.file.read.v1";
if (tool === "todowrite") return "data.file.write.v1";
if (tool === "task") return "agent.session.create.v1";
// Claude Code MCP tools use mcp__ prefix (double underscore, not mcp.)
if (tool.startsWith("mcp__")) return "mcp.tool.execute.v1";
```

**Note:** The existing `if (tool.startsWith("mcp."))` check does NOT match `mcp__` (double underscore). Both lines should coexist — `mcp.` for OpenClaw tool names, `mcp__` for Claude Code.

#### `.changeset/config.json`

Add `@aporthq/aport-agent-guardrails-claude-code` to the `fixed` group:

```json
"fixed":[[
  "@aporthq/aport-agent-guardrails-core",
  "@aporthq/aport-agent-guardrails-langchain",
  "@aporthq/aport-agent-guardrails-crewai",
  "@aporthq/aport-agent-guardrails-n8n",
  "@aporthq/aport-agent-guardrails-cursor",
  "@aporthq/aport-agent-guardrails-claude-code"
]]
```

This ensures claude-code bumps in sync with all other packages on every release.

#### `.github/workflows/release.yml`

Add to publish step:
```yaml
npm publish -w @aporthq/aport-agent-guardrails-claude-code --access public
```

Add to build step:
```yaml
- name: Build workspace packages
  run: npm run build   # already builds all workspaces; claude-code will be built automatically
```

(The existing `npm run build` runs `build --workspaces --if-present` so no special step needed — just make sure `packages/claude-code/package.json` has a `"build": "tsc"` script, which it does per the package.json spec above.)

Update the GitHub Release notes template to include claude-code:
```yaml
npm install @aporthq/aport-agent-guardrails-claude-code@$VERSION
```

#### `docs/frameworks/cursor.md`

Add a correction block near the top and in the "Claude Code" section:

```markdown
> **Update (v1.0.13):** The claim that the cursor hook works for Claude Code is incorrect.
> The cursor hook outputs `permission: allow/deny` — Claude Code expects `hookSpecificOutput.permissionDecision`.
> A dedicated Claude Code integration is now available:
> ```bash
> npx @aporthq/aport-agent-guardrails claude-code
> ```
> See [docs/frameworks/claude-code.md](./claude-code.md).
```

Also update the "Using the same script in VS Code (Copilot) and Claude Code" section footer to say "For Claude Code, use the dedicated integration instead."

#### `CHANGELOG.md`

Add this section at the top (before `[1.0.12]`):

```markdown
## [1.0.13] - 2026-03-XX

### Added
- **Claude Code Integration:** Pre-action authorization via Claude Code's `PreToolUse` hook.
  - New hook script: `bin/aport-claude-code-hook.sh` — handles all Claude Code tool types
    (Bash, Write, Edit, MultiEdit, TodoWrite, WebSearch, WebFetch, Browser, Task, MCP tools)
  - New installer: `npx @aporthq/aport-agent-guardrails claude-code`
    Writes `~/.claude/settings.json` with APort hook registered for all tools via `"matcher": "*"`
  - New npm package: `@aporthq/aport-agent-guardrails-claude-code`
  - Default passport path: `~/.claude/aport/passport.json`
  - Deny format: Claude Code's official `hookSpecificOutput.permissionDecision: "deny"` schema
  - Read-family tools (Read, Glob, LS, Grep, TodoRead) are allow-by-default (exit 0 without evaluator call)
  - Fail-closed: unknown tool names are denied
  - Framework auto-detection: `detect.sh` now detects Claude Code via `claude` binary or `~/.claude` dir
  - New `docs/frameworks/claude-code.md`

### Changed
- `bin/lib/config.sh`: Added `claude-code` framework with default config dir `~/.claude`
- `bin/aport-resolve-paths.sh`: Added `~/.claude` to passport probe list (before `~/.cursor`)
- `bin/lib/detect.sh`: Added Claude Code auto-detection
- `bin/agent-guardrails`: Added `claude-code` to supported frameworks list
- `extensions/openclaw-aport/index.ts`: Added `mapToolToPolicy()` entries for Claude Code tools
  (`multiedit`, `glob`, `ls`, `grep`, `todoread`, `todowrite`, `task`, `mcp__*`)
- `.changeset/config.json`: Added claude-code package to `fixed` version group
- `docs/frameworks/cursor.md`: Corrected Claude Code compatibility claim (hook output formats are incompatible)

### Security
- Claude Code hook uses `hookSpecificOutput.permissionDecision: "deny"` + exit 2 (belt-and-suspenders)
- Fail-closed on unknown tool names
- **⚠️ Limitation:** `claude --dangerously-skip-permissions` bypasses ALL hooks including APort. Document this prominently; it cannot be mitigated in code.
```

#### `README.md`

Add to framework support table:
```markdown
| Claude Code | `npx @aporthq/aport-agent-guardrails claude-code` | `~/.claude/settings.json` (PreToolUse) |
```

---

## 6. What This Does NOT Change

```
# Zero modifications to:
bin/aport-guardrail-bash.sh      ← Core evaluator, untouched
bin/aport-guardrail-api.sh       ← API mode, untouched
bin/aport-cursor-hook.sh         ← Cursor hook, untouched (do not extend — incompatible format)
bin/frameworks/cursor.sh         ← Cursor installer, untouched
packages/core/                   ← Shared evaluator, untouched
packages/langchain/              ← Untouched
packages/crewai/                 ← Untouched
packages/cursor/                 ← Untouched
packages/n8n/                    ← Untouched
packages/deprecated-agent-guardrails/ ← Untouched
python/                          ← All Python packages untouched
extensions/openclaw-aport/       ← Only mapToolToPolicy() additions (8 lines)
```

---

## 7. Scope Estimate

| Item | New lines |
|---|---|
| `bin/aport-claude-code-hook.sh` | ~80 bash |
| `bin/frameworks/claude-code.sh` | ~80 bash (pattern from cursor.sh) |
| `packages/claude-code/src/index.ts` | ~20 TS |
| `packages/claude-code/package.json` | 20 JSON |
| `packages/claude-code/tsconfig.json` | 10 JSON (copy from cursor) |
| `docs/frameworks/claude-code.md` | ~150 markdown |
| `integrations/claude-code/README.md` | ~20 markdown |
| Modifications (all files combined) | ~30 lines total |
| **Total** | **~410 lines** |

This is a small, isolated change. Zero risk to existing framework integrations.

---

## 8. Mono-Repo vs Multi-Repo

Keep the mono-repo. The `@aporthq/aport-agent-guardrails-claude-code` package appears in npm search for "claude code guardrail" regardless of which repo it lives in. A separate repo doubles CI/release maintenance. The discoverability wins come from npm metadata, GitHub topics, and content marketing — not from having a separate GitHub URL.

**High-ROI SEO actions (5 minutes, no code):**
1. Add GitHub topics: `claude-code`, `claude-code-hooks`, `ai-guardrails`, `llm-security` to the main repo
2. Update repo description to include "Claude Code"

**Split-repo threshold:** Only justified if the integration needs a VS Code Marketplace extension (different publishing pipeline). A bash hook doesn't cross that threshold.

---

## 9. Distribution Plan (Post-Ship)

1. **Tag v1.0.13 → npm auto-publishes** `@aporthq/aport-agent-guardrails-claude-code`
2. **GitHub topics** — add `claude-code`, `claude-code-hooks` (5 minutes)
3. **HN thread 47256614** (the sandbox escape thread) — reply: "Update: we shipped the integration. `npx @aporthq/aport-agent-guardrails claude-code` registers a `PreToolUse` hook that runs before every tool call as a separate process — the model cannot reason past it. Audit log at `~/.claude/aport/audit.log`."
4. **HN thread 47185228** ("Ask HN: How do you enforce guardrails on Claude agents") — still open, perfect reply window
5. **dev.to post** — "I Fixed Claude Code's Fake Sandbox in 2 Minutes" — frames around the conductor.build incident
6. **Correct `docs/frameworks/cursor.md`** claim before shipping — avoiding public embarrassment when someone files an issue about the Claude Code claim being wrong

---

## 10. Open Questions

| Question | Recommended Default | Reason |
|---|---|---|
| `detect.sh`: use `command -v claude` only, or also `~/.claude` directory? | `command -v claude` only as primary signal | `~/.claude` may exist from other tools; binary presence is stronger signal |
| `TodoWrite` — enforce or allow by default? | Enforce (matches Write policy) | It writes to Claude Code's internal task list — low risk, but consistent with Write family |
| Passport path for Claude Code (`~/.claude/aport/passport.json`)? | Yes, use `get_config_dir claude-code` → `~/.claude` → `~/.claude/aport/passport.json` | Matches existing framework pattern |

---

*Branch at `/tmp/tmp.rlzab9WHmI/aport-agent-guardrails`, branch `feature/claude-code-guardrail`. Do not push or assign until Uchi approves.*
