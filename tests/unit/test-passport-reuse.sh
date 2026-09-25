#!/bin/bash
# Unit test: reuse a passport that another framework already has on this device.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d)}"
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
unset APORT_CLAUDE_CODE_CONFIG_DIR APORT_CURSOR_CONFIG_DIR APORT_CODEX_CONFIG_DIR APORT_AGENT_ID APORT_API_KEY APORT_API_URL \
    APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM APORT_REUSE_PASSPORT_FROM_CLI \
    APORT_NONINTERACTIVE CI APORT_GUARDRAIL_MODE APORT_GUARDRAIL_MODE_CLI APORT_HOSTED_AGENT_ID_CLI

# shellcheck source=../../bin/lib/config.sh
source "$REPO_ROOT/bin/lib/config.sh"
# shellcheck source=../../bin/lib/quick-hosted.sh
source "$REPO_ROOT/bin/lib/quick-hosted.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A local passport from cursor and a hosted one from codex.
mkdir -p "$HOME/.cursor/aport" "$HOME/.aport/codex/aport" "$HOME/.claude"
printf '{"passport_id":"local-cursor","spec_version":"oap/1.0","capabilities":[]}\n' > "$HOME/.cursor/aport/passport.json"
cat > "$HOME/.aport/codex/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT_MODE=enforce
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef
APORT_API_KEY=apk_test_key
EOF

# 1. Listing excludes the framework being installed and reports both kinds.
listing="$(aport_list_device_passports claude-code)"
[[ "$listing" == *"cursor|local|$HOME/.cursor/aport/passport.json"* ]] || fail "cursor local passport not listed: $listing"
[[ "$listing" == *"codex|hosted|ap_1234567890abcdef1234567890abcdef"* ]] || fail "codex hosted passport not listed: $listing"
[[ "$(aport_list_device_passports cursor)" != *"cursor|"* ]] || fail "current framework must be excluded"
[[ "$(aport_list_device_passports claude-code local)" != *"|hosted|"* ]] || fail "kind filter local must drop hosted entries"

# 2. Applying a local passport copies it into the target config dir, mode 600, and marks the wizard to be skipped.
aport_apply_reused_passport "cursor|local|$HOME/.cursor/aport/passport.json" "$HOME/.claude"
[[ -f "$HOME/.claude/aport/passport.json" ]] || fail "passport not copied"
grep -q local-cursor "$HOME/.claude/aport/passport.json" || fail "copied passport has wrong content"
mode="$(stat -f '%Lp' "$HOME/.claude/aport/passport.json" 2> /dev/null || stat -c '%a' "$HOME/.claude/aport/passport.json")"
[[ "$mode" = "600" ]] || fail "passport mode is $mode, expected 600"
[[ "${APORT_PASSPORT_REUSED:-}" = "1" ]] || fail "APORT_PASSPORT_REUSED not set"
[[ "${APORT_PASSPORT_REUSED_FROM:-}" = "cursor" ]] || fail "APORT_PASSPORT_REUSED_FROM not set"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM

# 3. Applying a hosted passport exports the id, key and URL from the source framework.
aport_apply_reused_passport "codex|hosted|ap_1234567890abcdef1234567890abcdef" "$HOME/.claude"
[[ "${APORT_AGENT_ID:-}" = "ap_1234567890abcdef1234567890abcdef" ]] || fail "APORT_AGENT_ID not exported"
[[ "${APORT_API_KEY:-}" = "apk_test_key" ]] || fail "APORT_API_KEY not exported"
[[ "${APORT_API_URL:-}" = "https://api.aport.io" ]] || fail "APORT_API_URL not exported"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL

# 4. Non-interactive: no opt-in means no reuse and no prompt.
export APORT_NONINTERACTIVE=1
rm -f "$HOME/.claude/aport/passport.json"
if aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null; then fail "should fall through to local without opt-in"; fi
[[ ! -f "$HOME/.claude/aport/passport.json" ]] || fail "must not copy without --reuse-from"
unset APORT_PASSPORT_REUSE_DECIDED

# 5. Non-interactive with --reuse-from=<framework> (local): copied, wizard skipped, hosted path not taken.
export APORT_REUSE_PASSPORT_FROM_CLI=cursor
if aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null; then fail "local reuse must return 1 (local path)"; fi
[[ -f "$HOME/.claude/aport/passport.json" ]] || fail "--reuse-from=cursor did not copy the passport"
[[ "${APORT_PASSPORT_REUSED:-}" = "1" ]] || fail "wizard skip flag missing after --reuse-from"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI

# 6. Non-interactive with --reuse-from=<framework> (hosted): configured as hosted.
export APORT_REUSE_PASSPORT_FROM_CLI=codex
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "hosted reuse must return 0"
[[ "${APORT_AGENT_ID:-}" = "ap_1234567890abcdef1234567890abcdef" ]] || fail "hosted reuse did not export the agent id"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSED_FROM

# 7. --reuse-from with a bare agent id or a path works without any framework state.
line="$(aport_resolve_reuse_ref ap_abcdefabcdefabcdefabcdefabcdefab claude-code)"
[[ "$line" = "cli|hosted|ap_abcdefabcdefabcdefabcdefabcdefab" ]] || fail "agent id ref not resolved: $line"
line="$(aport_resolve_reuse_ref "$HOME/.cursor/aport/passport.json" claude-code)"
[[ "$line" = "cli|local|$HOME/.cursor/aport/passport.json" ]] || fail "path ref not resolved: $line"
if aport_resolve_reuse_ref nonexistent claude-code 2> /dev/null; then fail "unknown ref must fail"; fi
# A file in the cwd named like a framework never shadows the framework, and a non-passport path is refused.
mkdir -p "$HOME/shadow" && printf 'echo not a passport\n' > "$HOME/shadow/codex" && printf '{"x":1}\n' > "$HOME/shadow/junk.json"
line="$(cd "$HOME/shadow" && aport_resolve_reuse_ref codex claude-code)"
[[ "$line" = "codex|hosted|ap_1234567890abcdef1234567890abcdef" ]] || fail "framework name must win over a same-named file: $line"
if (cd "$HOME/shadow" && aport_resolve_reuse_ref "./junk.json" claude-code 2> /dev/null); then fail "a non-passport JSON path must be refused"; fi
# An explicit --reuse-from that cannot be honoured stops the install instead of minting a new passport.
if (
    export APORT_NONINTERACTIVE=1 APORT_REUSE_PASSPORT_FROM_CLI=cursr
    unset APORT_PASSPORT_REUSE_DECIDED
    aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null 2> /dev/null
); then fail "an unresolvable --reuse-from must exit non-zero"; fi
unset APORT_PASSPORT_REUSE_DECIDED

# 8. --mode=local with --reuse-from=<framework> uses that framework's local passport even when it also has a
#    hosted mode file, and never configures the hosted one.
printf '{"passport_id":"local-codex","spec_version":"oap/1.0","capabilities":[]}\n' > "$HOME/.aport/codex/aport/passport.json"
export APORT_GUARDRAIL_MODE_CLI=local APORT_REUSE_PASSPORT_FROM_CLI=codex
if aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null; then fail "mode=local must return 1"; fi
[[ -z "${APORT_AGENT_ID:-}" ]] || fail "mode=local must not configure a hosted passport"
grep -q local-codex "$HOME/.claude/aport/passport.json" || fail "mode=local must copy the framework's local passport"
rm -f "$HOME/.aport/codex/aport/passport.json"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_GUARDRAIL_MODE_CLI

# 9. The wizard gate honours the skip flag.
# shellcheck source=../../bin/lib/agentsmd.sh
source "$REPO_ROOT/bin/lib/agentsmd.sh"
export APORT_PASSPORT_REUSED=1
run_passport_wizard() { fail "wizard must not run when a passport was reused"; }
setup_from_agentsmd_or_wizard
unset APORT_PASSPORT_REUSED

# 10. An explicit --reuse-from wins over the framework's own saved hosted config (stale key replacement).
mkdir -p "$HOME/.claude/aport"
cat > "$HOME/.claude/aport/guardrail-mode.env" << 'EOF2'
APORT_GUARDRAIL_MODE=api
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_1234567890abcdef1234567890abcdef
APORT_API_KEY=apk_stale_key
EOF2
export APORT_NONINTERACTIVE=1 APORT_REUSE_PASSPORT_FROM_CLI=codex
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "explicit hosted reuse must return 0"
[[ "${APORT_API_KEY:-}" = "apk_test_key" ]] || fail "explicit --reuse-from must replace the stale key, got ${APORT_API_KEY:-unset}"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSED_FROM
echo "PASS: explicit reuse precedence"

# 11. An explicit --reuse-from also wins over an agent id inherited from the environment, and the two explicit
#     flags together are refused rather than silently ordered.
export APORT_NONINTERACTIVE=1 APORT_REUSE_PASSPORT_FROM_CLI=codex APORT_AGENT_ID=ap_0ld0ld0ld0ld0ld0ld0ld0ld0ld0ld0l
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "explicit reuse must return 0 with an inherited agent id"
[[ "${APORT_AGENT_ID:-}" = "ap_1234567890abcdef1234567890abcdef" ]] || fail "explicit --reuse-from must beat an inherited APORT_AGENT_ID, got ${APORT_AGENT_ID:-unset}"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_PASSPORT_REUSED_FROM
if (
    export APORT_HOSTED_AGENT_ID_CLI=ap_abcdefabcdefabcdefabcdefabcdefab
    aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null 2> /dev/null
); then fail "--reuse-from with --agent-id must be refused"; fi
unset APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSE_DECIDED
echo "PASS: explicit reuse beats an inherited agent id"

# 12. The interactive menu never offers to copy over a passport the framework already has, and an explicit
#     request that does overwrite keeps the old file as .bak.
unset APORT_NONINTERACTIVE CI
printf '{"passport_id":"hand-tuned","spec_version":"oap/1.0","capabilities":[]}\n' > "$HOME/.claude/aport/passport.json"
rm -f "$HOME/.claude/aport/guardrail-mode.env"
menu_out="$(
    export APORT_GUARDRAIL_MODE_CLI=local
    unset APORT_PASSPORT_REUSE_DECIDED
    aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" <<< "1" 2>&1 || true
)"
[[ "$menu_out" != *"Existing APort passports"* ]] || fail "mode=local must not show the reuse menu when a passport already exists"
grep -q hand-tuned "$HOME/.claude/aport/passport.json" || fail "the existing passport must be left alone by the menu"
unset APORT_PASSPORT_REUSE_DECIDED
export APORT_NONINTERACTIVE=1 APORT_REUSE_PASSPORT_FROM_CLI=cursor
if aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null; then fail "local reuse must return 1"; fi
grep -q local-cursor "$HOME/.claude/aport/passport.json" || fail "explicit --reuse-from must replace the passport"
grep -q hand-tuned "$HOME/.claude/aport/passport.json.bak" || fail "the replaced passport must be kept as .bak"
rm -f "$HOME/.claude/aport/passport.json.bak"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI
echo "PASS: menu leaves an existing passport alone; explicit overwrite keeps a backup"

# 13. A planted symlink at the destination is refused, like every other passport write path.
mkdir -p "$HOME/victim" "$HOME/.gemini/aport"
printf '{"passport_id":"victim"}\n' > "$HOME/victim/secret.json"
ln -s "$HOME/victim/secret.json" "$HOME/.gemini/aport/passport.json"
if aport_apply_reused_passport "cursor|local|$HOME/.cursor/aport/passport.json" "$HOME/.gemini" 2> "$TEST_DIR/symlink.err"; then fail "a symlinked destination must be refused"; fi
grep -q victim "$HOME/victim/secret.json" || fail "the symlink target must be untouched"
grep -qi "symlink" "$TEST_DIR/symlink.err" || fail "the refusal must say why: $(cat "$TEST_DIR/symlink.err")"
rm -f "$HOME/.gemini/aport/passport.json"
echo "PASS: symlinked destination refused"

# 14. A bare agent id is not a local passport, so --mode=local --reuse-from=<agent id> fails clearly.
if aport_resolve_reuse_ref ap_abcdefabcdefabcdefabcdefabcdefab claude-code local 2> /dev/null; then fail "an agent id must not resolve when only local passports are wanted"; fi

echo "PASS: passport reuse"
