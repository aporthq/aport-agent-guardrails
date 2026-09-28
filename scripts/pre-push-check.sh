#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="${HOME:-}"
REAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
if [[ -n "${APORT_PRE_PUSH_TMP_ROOT:-}" ]]; then
    TMP_ROOT="$APORT_PRE_PUSH_TMP_ROOT"
    CLEANUP_TMP_ROOT=0
else
    TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aport-prepush.XXXXXX")"
    CLEANUP_TMP_ROOT=1
fi
TEST_HOME="${APORT_PRE_PUSH_HOME:-$TMP_ROOT/home/default}"
CREWAI_VENV="$TMP_ROOT/venvs/crewai"
LANGCHAIN_VENV="$TMP_ROOT/venvs/langchain"
CREWAI_HOME="$TMP_ROOT/homes/crewai"
LANGCHAIN_HOME="$TMP_ROOT/homes/langchain"
OPENCLAW_HOME="$TMP_ROOT/openclaw"
DEFAULT_AGENT_ID="ap_8955f5450cd542fe8f67bbbf07c3e103"
PRE_PUSH_LEVEL="${APORT_PRE_PUSH_LEVEL:-fast}"
if [[ "${APORT_PRE_PUSH_FULL:-0}" = "1" ]]; then
    PRE_PUSH_LEVEL="full"
fi

cleanup() {
    if [[ "${CLEANUP_TMP_ROOT:-0}" = "1" ]]; then
        rm -rf "$TMP_ROOT"
    fi
}
trap cleanup EXIT

log_step() {
    printf '\n[%s] %s\n' "pre-push" "$1"
}

run_cmd() {
    log_step "$1"
    shift
    "$@"
}

run_shellcheck() {
    if command -v shellcheck > /dev/null 2>&1; then
        bash -lc "shellcheck -S error --color=always --shell=bash \$(find bin enterprise-scripts scripts tests -name '*.sh' -type f | tr '\n' ' ')"
    else
        echo "shellcheck not installed; CI still enforces it"
    fi
}

run_fast_checks() {
    local include_shellcheck="${1:-${APORT_PRE_PUSH_INCLUDE_SHELLCHECK:-0}}"
    run_cmd "Validate passport schema JSON" jq . external/aport-spec/oap/examples/passport.template.v1.json
    run_cmd "Shell syntax" bash -n bin/*.sh bin/lib/*.sh bin/frameworks/*.sh enterprise-scripts/*.sh scripts/*.sh tests/*.sh tests/unit/*.sh tests/frameworks/*/*.sh
    if [[ "$include_shellcheck" = "1" ]]; then
        run_cmd "ShellCheck" run_shellcheck
    else
        log_step "Skipping ShellCheck in fast mode (set APORT_PRE_PUSH_INCLUDE_SHELLCHECK=1 or APORT_PRE_PUSH_LEVEL=full)"
    fi
    run_cmd "shfmt" bash -lc "find bin enterprise-scripts scripts tests -name '*.sh' -type f -print0 | xargs -0 shfmt -d"
    run_cmd "Codex provider tool surface drift" bash scripts/check-codex-provider-tool-surface.sh
    run_cmd "Evaluator API timeout parsing" node tests/unit/test-evaluator-api-timeout.cjs
}

ensure_crewai_venv() {
    if [[ ! -x "$CREWAI_VENV/bin/python" ]]; then
        log_step "Creating CrewAI E2E venv"
        mkdir -p "$(dirname "$CREWAI_VENV")"
        python3 -m venv "$CREWAI_VENV"
        "$CREWAI_VENV/bin/pip" install -q -e "$REPO_ROOT/python/aport_guardrails" -e "$REPO_ROOT/python/crewai_adapter[dev]" "crewai>=0.80"
    fi
}

ensure_langchain_venv() {
    if [[ ! -x "$LANGCHAIN_VENV/bin/python" ]]; then
        log_step "Creating LangChain E2E venv"
        mkdir -p "$(dirname "$LANGCHAIN_VENV")"
        python3 -m venv "$LANGCHAIN_VENV"
        "$LANGCHAIN_VENV/bin/pip" install -q -e "$REPO_ROOT/python/aport_guardrails" -e "$REPO_ROOT/python/langchain_adapter[dev]"
    fi
    "$LANGCHAIN_VENV/bin/pip" install -q pytest pytest-asyncio
}

run_crewai_e2e() {
    ensure_crewai_venv
    rm -rf "$CREWAI_HOME"
    mkdir -p "$CREWAI_HOME"

    run_cmd "E2E CrewAI setup" env HOME="$CREWAI_HOME" PYTHONPATH=python:python/crewai_adapter \
        "$CREWAI_VENV/bin/aport-crewai" --ci

    run_cmd "E2E CrewAI example" env HOME="$CREWAI_HOME" PYTHONPATH=python:python/crewai_adapter \
        "$CREWAI_VENV/bin/python" examples/crewai/run_with_guardrail.py

    run_cmd "E2E CrewAI sample crew" env HOME="$CREWAI_HOME" PYTHONPATH=python:python/crewai_adapter \
        "$CREWAI_VENV/bin/python" -m pytest examples/crewai/sample_crew.py -v --tb=short

    run_cmd "E2E CrewAI adapter tests" env HOME="$CREWAI_HOME" PYTHONPATH="$REPO_ROOT/python" \
        "$CREWAI_VENV/bin/pytest" "$REPO_ROOT/python/crewai_adapter/tests/" -v --tb=short
}

run_langchain_e2e() {
    ensure_langchain_venv
    rm -rf "$LANGCHAIN_HOME"
    mkdir -p "$LANGCHAIN_HOME"

    run_cmd "E2E LangChain setup" env HOME="$LANGCHAIN_HOME" PYTHONPATH=python:python/langchain_adapter \
        "$LANGCHAIN_VENV/bin/aport-langchain" --ci

    run_cmd "E2E LangChain example" env HOME="$LANGCHAIN_HOME" PYTHONPATH=python:python/langchain_adapter \
        "$LANGCHAIN_VENV/bin/python" examples/langchain/run_with_guardrail.py

    run_cmd "E2E LangChain adapter tests" env HOME="$LANGCHAIN_HOME" PYTHONPATH="$REPO_ROOT/python" \
        "$LANGCHAIN_VENV/bin/pytest" "$REPO_ROOT/python/langchain_adapter/tests/" -v --tb=short

    run_cmd "E2E core Python tests" env HOME="$LANGCHAIN_HOME" \
        "$LANGCHAIN_VENV/bin/pytest" "$REPO_ROOT/python/aport_guardrails/tests/" -v --tb=short
}

run_openclaw_e2e() {
    if [[ "${APORT_PRE_PUSH_INCLUDE_OPENCLAW_LIVE:-0}" != "1" ]]; then
        log_step "Skipping live OpenClaw CLI E2E (set APORT_PRE_PUSH_INCLUDE_OPENCLAW_LIVE=1 to enable)"
        return 0
    fi

    rm -rf "$OPENCLAW_HOME"
    mkdir -p "$OPENCLAW_HOME"

    run_cmd "E2E OpenClaw CLI setup" bash -lc "
    cd '$REPO_ROOT'
    OPENCLAW_HOME='$OPENCLAW_HOME' AGENT_ID='${APORT_TEST_REMOTE_AGENT_ID:-$DEFAULT_AGENT_ID}' \
      printf '\n\n\n\n' | ./bin/agent-guardrails --framework=openclaw \"\${AGENT_ID}\" >'$TMP_ROOT/openclaw-cli.log' 2>&1 || true
    test -f '$OPENCLAW_HOME/config.yaml'
    grep -q 'agentId:' '$OPENCLAW_HOME/config.yaml'
  "
}

run_optional_scans() {
    if [[ "${APORT_PRE_PUSH_INCLUDE_OPTIONAL:-0}" != "1" ]]; then
        log_step "Skipping optional secret scans (set APORT_PRE_PUSH_INCLUDE_OPTIONAL=1 to enable)"
        return 0
    fi

    if command -v gitleaks > /dev/null 2>&1; then
        run_cmd "Gitleaks" gitleaks detect --source "$REPO_ROOT" --report-path "$TMP_ROOT/gitleaks-report.json" --report-format json --verbose
    else
        log_step "Skipping Gitleaks (not installed)"
    fi

    if command -v trufflehog > /dev/null 2>&1; then
        run_cmd "TruffleHog" trufflehog filesystem "$REPO_ROOT" --json --only-verified
    else
        log_step "Skipping TruffleHog (not installed)"
    fi
}

cd "$REPO_ROOT"
mkdir -p "$TEST_HOME"
if [[ -z "${APORT_CODEX_PROVIDER_SOURCE_DIR:-}" && -z "${APORT_CODEX_PROVIDER_CACHE_DIR:-}" && -z "${CI:-}" && -n "$REAL_HOME" ]]; then
    cache_root="${REAL_XDG_CACHE_HOME:-$REAL_HOME/.cache}/aport/codex-provider"
    cache_key="$(printf '%s' "${APORT_CODEX_PROVIDER_REF:-main}" | tr -c 'A-Za-z0-9._-' '_')"
    export APORT_CODEX_PROVIDER_CACHE_DIR="$cache_root/$cache_key"
fi
export HOME="$TEST_HOME"

case "$PRE_PUSH_LEVEL" in
    fast)
        run_fast_checks
        log_step "Fast pre-push checks passed (set APORT_PRE_PUSH_LEVEL=full for CI-equivalent local checks)"
        exit 0
        ;;
    full | ci)
        run_fast_checks 1
        ;;
    *)
        echo "FAIL: unsupported APORT_PRE_PUSH_LEVEL=$PRE_PUSH_LEVEL (expected fast or full)" >&2
        exit 1
        ;;
esac

run_cmd "Repo test suite" make test
run_cmd "Node build" npm run build
run_cmd "Node workspace tests" npm run test -w @aporthq/aport-agent-guardrails-core -w @aporthq/aport-agent-guardrails-langchain
run_cmd "OpenClaw Node setup test" node tests/frameworks/openclaw/setup.test.mjs
run_cmd "OpenClaw plugin tests" bash -lc "cd '$REPO_ROOT/extensions/openclaw-aport' && npm test"
run_cmd "Python package builds + twine" bash -lc "cd '$REPO_ROOT' && python3 -m build python/aport_guardrails && python3 -m build python/langchain_adapter && python3 -m build python/crewai_adapter && python3 -m twine check python/aport_guardrails/dist/* python/langchain_adapter/dist/* python/crewai_adapter/dist/*"

run_crewai_e2e
run_langchain_e2e
run_openclaw_e2e
run_optional_scans

log_step "All pre-push checks passed"
