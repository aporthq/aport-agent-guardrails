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
# GNU stat has no -f '%Lp'; it reads '%Lp' as a filename, prints a usage error and exits nonzero, so the
# first command's stdout has to be discarded or both outputs end up concatenated in $mode. Same order and
# same redirection as tests/frameworks/*/setup.sh: GNU first, BSD as the fallback.
mode="$(stat -c '%a' "$HOME/.claude/aport/passport.json" 2> /dev/null || stat -f '%Lp' "$HOME/.claude/aport/passport.json" 2> /dev/null)"
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

# Local reuse must clear inherited hosted state. Otherwise callers see the stale APORT_AGENT_ID and install API
# mode for a different passport than the local one that was just copied.
export APORT_REUSE_PASSPORT_FROM_CLI=cursor APORT_AGENT_ID=ap_stalehosted1234567890abcdef123456 APORT_API_KEY=apk_stale_key APORT_API_URL=https://stale.example
if aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null; then fail "local reuse with stale hosted env must return 1 (local path)"; fi
[[ -z "${APORT_AGENT_ID:-}" ]] || fail "local reuse must clear stale APORT_AGENT_ID"
[[ -z "${APORT_API_KEY:-}" ]] || fail "local reuse must clear stale APORT_API_KEY"
[[ -z "${APORT_API_URL:-}" ]] || fail "local reuse must clear stale APORT_API_URL"
grep -q local-cursor "$HOME/.claude/aport/passport.json" || fail "local reuse with stale hosted env did not copy the local passport"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI

# 6. Non-interactive with --reuse-from=<framework> (hosted): configured as hosted.
export APORT_REUSE_PASSPORT_FROM_CLI=codex
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "hosted reuse must return 0"
[[ "${APORT_AGENT_ID:-}" = "ap_1234567890abcdef1234567890abcdef" ]] || fail "hosted reuse did not export the agent id"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSED_FROM

# Hosted reuse from a source mode file that omits optional credentials must clear inherited stale values rather
# than carrying them into the target framework.
mkdir -p "$HOME/.aport/gemini-cli/aport"
cat > "$HOME/.aport/gemini-cli/aport/guardrail-mode.env" << 'EOF'
APORT_GUARDRAIL_MODE=api
APORT_ENFORCEMENT_MODE=warn
APORT_API_URL=https://api.aport.io
APORT_AGENT_ID=ap_abcdefabcdefabcdefabcdefabcdefab
EOF
export APORT_REUSE_PASSPORT_FROM_CLI=gemini-cli APORT_API_KEY=apk_stale_key APORT_API_URL=https://stale.example APORT_SELECTED_API_URL=https://stale.example
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "keyless hosted reuse must return 0"
[[ "${APORT_AGENT_ID:-}" = "ap_abcdefabcdefabcdefabcdefabcdefab" ]] || fail "keyless hosted reuse did not export the source agent id"
[[ -z "${APORT_API_KEY:-}" ]] || fail "keyless hosted reuse must clear stale APORT_API_KEY"
[[ "${APORT_API_URL:-}" = "https://api.aport.io" ]] || fail "keyless hosted reuse should keep the source API URL, got ${APORT_API_URL:-unset}"
[[ "${APORT_SELECTED_API_URL:-}" = "https://api.aport.io" ]] || fail "keyless hosted reuse should replace stale APORT_SELECTED_API_URL, got ${APORT_SELECTED_API_URL:-unset}"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSED_FROM

# 7. --reuse-from with a bare agent id or a path works without any framework state.
line="$(aport_resolve_reuse_ref ap_abcdefabcdefabcdefabcdefabcdefab claude-code)"
[[ "$line" = "cli|hosted|ap_abcdefabcdefabcdefabcdefabcdefab" ]] || fail "agent id ref not resolved: $line"
export APORT_REUSE_PASSPORT_FROM_CLI=ap_abcdefabcdefabcdefabcdefabcdefab APORT_API_KEY=apk_intended_key APORT_API_URL=https://custom.example
unset APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED
aport_maybe_configure_hosted_passport claude-code "$HOME/.claude" < /dev/null || fail "bare hosted id reuse must return 0"
[[ "${APORT_AGENT_ID:-}" = "ap_abcdefabcdefabcdefabcdefabcdefab" ]] || fail "bare hosted id reuse did not export the agent id"
[[ "${APORT_API_KEY:-}" = "apk_intended_key" ]] || fail "bare hosted id reuse must preserve explicit APORT_API_KEY"
[[ "${APORT_API_URL:-}" = "https://custom.example" ]] || fail "bare hosted id reuse must preserve explicit APORT_API_URL"
[[ "${APORT_SELECTED_API_URL:-}" = "https://custom.example" ]] || fail "bare hosted id reuse should carry the custom API URL into selection"
unset APORT_AGENT_ID APORT_API_KEY APORT_API_URL APORT_SELECTED_API_URL APORT_PASSPORT_REUSE_DECIDED APORT_REUSE_PASSPORT_FROM_CLI APORT_PASSPORT_REUSED_FROM
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

# 15. A failed copy must not report success. Callers invoke aport_apply_reused_passport inside an `if` or
#     after a `||`, which turns errexit off for everything the function runs, so an unchecked cp that failed
#     would fall through to the success log and return 0: the wizard would be skipped with no passport, or an
#     existing passport would be overwritten after a backup that is not there.
#     The function chmods its own destination directory to 700, so an unwritable directory cannot force the
#     failure; a read-only passport.json can, and it is a state a user reaches by hardening the file by hand.
#     The backup succeeds here and the destination copy fails, which is exactly the case where returning 0
#     would have skipped the wizard with the OLD passport still in place.
BLOCKED_DIR="$HOME/.blocked-dest"
mkdir -p "$BLOCKED_DIR/aport"
printf '{"passport_id":"read-only-dest","spec_version":"oap/1.0","capabilities":[]}\n' > "$BLOCKED_DIR/aport/passport.json"
chmod 400 "$BLOCKED_DIR/aport/passport.json"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM
if aport_apply_reused_passport "cursor|local|$HOME/.cursor/aport/passport.json" "$BLOCKED_DIR" 2> "$TEST_DIR/blocked-dest.err"; then
    chmod 600 "$BLOCKED_DIR/aport/passport.json"
    fail "a failed destination copy must return non-zero"
fi
[[ -z "${APORT_PASSPORT_REUSED:-}" ]] || fail "a failed destination copy must not set the wizard-skip flag"
[[ -z "${APORT_PASSPORT_REUSED_FROM:-}" ]] || fail "a failed destination copy must not record a source"
grep -q read-only-dest "$BLOCKED_DIR/aport/passport.json" || fail "the unwritable passport should be unchanged"
grep -qi "could not copy" "$TEST_DIR/blocked-dest.err" || fail "the failure must say what went wrong: $(cat "$TEST_DIR/blocked-dest.err")"
chmod 600 "$BLOCKED_DIR/aport/passport.json"
echo "PASS: a failed destination copy fails loudly"

#     Unwritable backup: the existing passport must survive and the reuse must fail, because the backup the
#     function promises in its log line could not be written. A read-only .bak makes `cp dest dest.bak` fail.
BAK_DIR="$HOME/.unwritable-backup"
mkdir -p "$BAK_DIR/aport"
printf '{"passport_id":"must-survive","spec_version":"oap/1.0","capabilities":[]}\n' > "$BAK_DIR/aport/passport.json"
printf 'reserved\n' > "$BAK_DIR/aport/passport.json.bak"
chmod 400 "$BAK_DIR/aport/passport.json.bak"
unset APORT_PASSPORT_REUSED APORT_PASSPORT_REUSED_FROM
if aport_apply_reused_passport "cursor|local|$HOME/.cursor/aport/passport.json" "$BAK_DIR" 2> "$TEST_DIR/bak.err"; then
    chmod 600 "$BAK_DIR/aport/passport.json.bak"
    fail "a failed backup must return non-zero"
fi
grep -q must-survive "$BAK_DIR/aport/passport.json" || fail "a failed backup must leave the existing passport in place"
[[ -z "${APORT_PASSPORT_REUSED:-}" ]] || fail "a failed backup must not set the wizard-skip flag"
grep -qi "could not back up" "$TEST_DIR/bak.err" || fail "the failure must name the backup: $(cat "$TEST_DIR/bak.err")"
chmod 600 "$BAK_DIR/aport/passport.json.bak"
echo "PASS: a failed backup leaves the existing passport alone"

# 16. OpenClaw stores its passport under $OPENCLAW_HOME when that is set (bin/openclaw), so the scanner has
#     to resolve the same aliases or it misses a passport already on the device and offers to mint a duplicate.
OC_HOME="$HOME/.openclaw-custom-home"
mkdir -p "$OC_HOME/aport"
printf '{"passport_id":"local-openclaw-home","spec_version":"oap/1.0","capabilities":[]}\n' > "$OC_HOME/aport/passport.json"
OC_STATE="$HOME/.openclaw-state-dir"
mkdir -p "$OC_STATE/aport"
printf '{"passport_id":"local-openclaw-state","spec_version":"oap/1.0","capabilities":[]}\n' > "$OC_STATE/aport/passport.json"
oc_listing="$(OPENCLAW_HOME="$OC_HOME" aport_list_device_passports claude-code)"
[[ "$oc_listing" == *"openclaw|local|$OC_HOME/aport/passport.json"* ]] \
    || fail "OPENCLAW_HOME passport not discovered: $oc_listing"
oc_listing="$(OPENCLAW_STATE_DIR="$OC_STATE" OPENCLAW_HOME="$OC_HOME" aport_list_device_passports claude-code)"
[[ "$oc_listing" == *"openclaw|local|$OC_STATE/aport/passport.json"* ]] \
    || fail "OPENCLAW_STATE_DIR passport not discovered or did not beat OPENCLAW_HOME: $oc_listing"
oc_listing="$(OPENCLAW_CONFIG_DIR="$OC_HOME" aport_list_device_passports claude-code)"
[[ "$oc_listing" == *"openclaw|local|$OC_HOME/aport/passport.json"* ]] \
    || fail "OPENCLAW_CONFIG_DIR passport not discovered: $oc_listing"
# APort's own override still wins over OpenClaw aliases, which is the precedence set-mode and reset use.
OTHER_OC="$HOME/.openclaw-aport-override"
mkdir -p "$OTHER_OC/aport"
printf '{"passport_id":"aport-override","spec_version":"oap/1.0","capabilities":[]}\n' > "$OTHER_OC/aport/passport.json"
oc_listing="$(APORT_OPENCLAW_CONFIG_DIR="$OTHER_OC" OPENCLAW_STATE_DIR="$OC_STATE" OPENCLAW_HOME="$OC_HOME" aport_list_device_passports claude-code)"
[[ "$oc_listing" == *"openclaw|local|$OTHER_OC/aport/passport.json"* ]] \
    || fail "APORT_OPENCLAW_CONFIG_DIR must win over OpenClaw aliases: $oc_listing"
# And --reuse-from=openclaw resolves the alias too, not just the listing.
oc_line="$(OPENCLAW_STATE_DIR="$OC_STATE" OPENCLAW_HOME="$OC_HOME" aport_resolve_reuse_ref openclaw claude-code)"
[[ "$oc_line" = "openclaw|local|$OC_STATE/aport/passport.json" ]] || fail "--reuse-from=openclaw did not resolve OPENCLAW_STATE_DIR: $oc_line"
echo "PASS: OpenClaw home aliases are resolved during discovery"

# 17. --reuse-from= with an empty value is refused like the separated form with no argument. Storing "" read
#     as "not provided" everywhere later, so a non-interactive setup would mint a new passport anyway.
# shellcheck source=../../bin/lib/guardrail-mode.sh
source "$REPO_ROOT/bin/lib/guardrail-mode.sh"
unset APORT_REUSE_PASSPORT_FROM_CLI
if parse_guardrail_mode_args --reuse-from= 2> "$TEST_DIR/empty-reuse.err"; then
    fail "--reuse-from= with an empty value must be refused"
fi
grep -q "reuse-from requires" "$TEST_DIR/empty-reuse.err" || fail "the refusal must name the option: $(cat "$TEST_DIR/empty-reuse.err")"
[[ -z "${APORT_REUSE_PASSPORT_FROM_CLI:-}" ]] || fail "a refused --reuse-from= must not store a value"
# The separated form with no argument is still refused, and a real value is still accepted.
unset APORT_REUSE_PASSPORT_FROM_CLI
if parse_guardrail_mode_args --reuse-from 2> /dev/null; then fail "--reuse-from with no argument must be refused"; fi
unset APORT_REUSE_PASSPORT_FROM_CLI
parse_guardrail_mode_args --reuse-from=cursor || fail "--reuse-from=cursor must still be accepted"
[[ "${APORT_REUSE_PASSPORT_FROM_CLI:-}" = "cursor" ]] || fail "--reuse-from=cursor did not store the value"
unset APORT_REUSE_PASSPORT_FROM_CLI
if parse_guardrail_mode_args --reuse-from=codex ap_abcdefabcdefabcdefabcdefabcdefab 2> "$TEST_DIR/reuse-conflict.err"; then
    fail "--reuse-from plus a positional hosted agent id must be refused during argument parsing"
fi
grep -q "hosted agent id" "$TEST_DIR/reuse-conflict.err" || fail "the conflict refusal must name the hosted id: $(cat "$TEST_DIR/reuse-conflict.err")"
if (
    export HOME="$TEST_DIR/conflict-home" APORT_NONINTERACTIVE=1 APORT_CURSOR_CONFIG_DIR="$TEST_DIR/conflict-cursor"
    mkdir -p "$HOME"
    "$REPO_ROOT/bin/frameworks/cursor.sh" --reuse-from=codex ap_abcdefabcdefabcdefabcdefabcdefab > "$TEST_DIR/reuse-conflict-installer.out" 2> "$TEST_DIR/reuse-conflict-installer.err"
); then
    fail "the Cursor installer path must reject conflicting passport selectors before hosted-id setup"
fi
grep -q "hosted agent id" "$TEST_DIR/reuse-conflict-installer.err" || fail "installer conflict must name the hosted id: $(cat "$TEST_DIR/reuse-conflict-installer.err")"
echo "PASS: --reuse-from= with an empty value is refused"

echo "PASS: passport reuse"
