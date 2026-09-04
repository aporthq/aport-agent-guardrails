#!/usr/bin/env bash
# GitHub repository guard setup.
# Writes a project-local GitHub Actions workflow and, optionally, a starter
# repository policy. Does not install shell hooks or require APort API keys.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/lib" && pwd)"
# shellcheck source=./lib/common.sh
source "$LIB/common.sh"

PROJECT_DIR="${APORT_PROJECT_DIR:-$PWD}"
FORCE=""
WRITE_POLICY=""
MODE="${APORT_GITHUB_GUARD_MODE:-auto}"
PUSH_BRANCHES="${APORT_GITHUB_GUARD_BRANCHES:-main}"
ACTION_REF="${APORT_GITHUB_ACTION_REF:-aporthq/policy-verify-action@v1}"
PASSPORT_PATH="${APORT_GITHUB_PASSPORT_PATH:-.aport/passport.json}"
PROTECTED_PATHS="${APORT_GITHUB_PROTECTED_PATHS:-}"
BLOCK_PROTECTED_PATHS="${APORT_GITHUB_BLOCK_PROTECTED_PATHS:-}"

usage() {
    cat << 'EOF'
Usage:
  npx @aporthq/aport-agent-guardrails github [options]

Options:
  --policy              Also create .aport/policy.yaml when it does not exist.
  --force               Overwrite existing generated files.
  --mode <mode>         Action mode: auto, hosted, local-json, evidence-only.
                        Default: auto.
  --branches <list>     Comma-separated push branches to watch. Default: main.
  --protected-paths <list>
                        Comma-separated repository path globs passed to the
                        Action's protected-path checks.
  --block-protected-paths
                        Fail hosted verification when protected paths change.
                        Useful for security-critical repositories.
  --passport-path <path>
                        Trusted base-ref passport path for --mode local-json.
                        Default: .aport/passport.json.
  --project-dir <path>  Write files into this repository path (default: cwd).
  -h, --help            Show this help.

This setup writes .github/workflows/aport-guard.yml using
aporthq/policy-verify-action@v1. Default mode uses GitHub OIDC, does not
require APort API keys, and avoids shell-piped installers.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --policy)
            WRITE_POLICY="1"
            shift
            ;;
        --force)
            FORCE="1"
            shift
            ;;
        --mode)
            if [[ $# -lt 2 ]]; then
                log_error "--mode requires a value"
                exit 1
            fi
            MODE="$2"
            shift 2
            ;;
        --mode=*)
            MODE="${1#--mode=}"
            shift
            ;;
        --branches)
            if [[ $# -lt 2 ]]; then
                log_error "--branches requires a comma-separated list"
                exit 1
            fi
            PUSH_BRANCHES="$2"
            shift 2
            ;;
        --branches=*)
            PUSH_BRANCHES="${1#--branches=}"
            shift
            ;;
        --protected-paths)
            if [[ $# -lt 2 ]]; then
                log_error "--protected-paths requires a comma-separated list"
                exit 1
            fi
            PROTECTED_PATHS="$2"
            shift 2
            ;;
        --protected-paths=*)
            PROTECTED_PATHS="${1#--protected-paths=}"
            shift
            ;;
        --block-protected-paths)
            BLOCK_PROTECTED_PATHS="true"
            shift
            ;;
        --project-dir)
            if [[ $# -lt 2 ]]; then
                log_error "--project-dir requires a path"
                exit 1
            fi
            PROJECT_DIR="$2"
            shift 2
            ;;
        --project-dir=*)
            PROJECT_DIR="${1#--project-dir=}"
            shift
            ;;
        --passport-path)
            if [[ $# -lt 2 ]]; then
                log_error "--passport-path requires a repository-relative path"
                exit 1
            fi
            PASSPORT_PATH="$2"
            shift 2
            ;;
        --passport-path=*)
            PASSPORT_PATH="${1#--passport-path=}"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown GitHub setup option: $1"
            echo "  Run: npx @aporthq/aport-agent-guardrails github --help" >&2
            exit 1
            ;;
    esac
done

case "$MODE" in
    auto | hosted | local-json | evidence-only) ;;
    *)
        log_error "Unsupported mode: $MODE (expected auto, hosted, local-json, or evidence-only)"
        exit 1
        ;;
esac

if [[ "$PUSH_BRANCHES" == *$'\n'* || "$PUSH_BRANCHES" == *$'\r'* ]]; then
    log_error "--branches must be a comma-separated single-line list"
    exit 1
fi

if [[ "$PROTECTED_PATHS" == *$'\n'* || "$PROTECTED_PATHS" == *$'\r'* ]]; then
    log_error "--protected-paths must be a comma-separated single-line list"
    exit 1
fi

case "$BLOCK_PROTECTED_PATHS" in
    "" | 0 | false | FALSE | False | no | NO | No) BLOCK_PROTECTED_PATHS="" ;;
    1 | true | TRUE | True | yes | YES | Yes) BLOCK_PROTECTED_PATHS="true" ;;
    *)
        log_error "APORT_GITHUB_BLOCK_PROTECTED_PATHS must be true or false"
        exit 1
        ;;
esac

if [[ ! "$ACTION_REF" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[A-Za-z0-9_.:/-]+$ ]]; then
    log_error "Invalid APORT_GITHUB_ACTION_REF. Expected owner/repo@ref."
    exit 1
fi

case "$PASSPORT_PATH" in
    /* | ../* | */../* | *"/.." | "." | "")
        log_error "--passport-path must be a repository-relative JSON path without traversal"
        exit 1
        ;;
esac
if [[ ! "$PASSPORT_PATH" =~ ^[A-Za-z0-9._/-]+\.json$ ]]; then
    log_error "--passport-path must end in .json and use portable path characters"
    exit 1
fi

require_cmd git
PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
if [[ ! -d "$PROJECT_DIR" ]]; then
    log_error "Project directory does not exist: $PROJECT_DIR"
    exit 1
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
GIT_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2> /dev/null || true)"
if [[ -z "$GIT_ROOT" ]]; then
    log_error "Run GitHub Repository Guard setup from inside a Git repository."
    exit 1
fi
PROJECT_DIR="$GIT_ROOT"

WORKFLOW_FILE="$PROJECT_DIR/.github/workflows/aport-guard.yml"
POLICY_FILE="$PROJECT_DIR/.aport/policy.yaml"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

render_branch_lines() {
    local raw="$1"
    local branch
    local rendered=""
    IFS=',' read -r -a branch_list <<< "$raw"
    for branch in "${branch_list[@]}"; do
        branch="$(trim "$branch")"
        [[ -n "$branch" ]] || continue
        if [[ ! "$branch" =~ ^[A-Za-z0-9._/*-]+$ ]]; then
            log_error "Invalid branch pattern '$branch'. Use letters, numbers, '.', '_', '-', '/', or '*'."
            exit 1
        fi
        rendered+="      - \"$branch\""$'\n'
    done
    if [[ -z "$rendered" ]]; then
        log_error "--branches must include at least one branch"
        exit 1
    fi
    printf '%s' "$rendered"
}

refuse_symlink_path() {
    local path="$1"
    local relative="${path#$PROJECT_DIR/}"
    local current=""
    local part

    IFS='/' read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || continue
        current="${current:+$current/}$part"
        if [[ -L "$PROJECT_DIR/$current" ]]; then
            log_error "Refusing to write through symlink: $current"
            exit 1
        fi
    done
}

render_action_inputs() {
    echo "          mode: $MODE"
    if [[ -n "$PROTECTED_PATHS" ]]; then
        echo "          protected-paths: >-"
        echo "            $PROTECTED_PATHS"
    fi
    if [[ -n "$BLOCK_PROTECTED_PATHS" ]]; then
        echo "          block-protected-paths: true"
    fi
    if [[ "$MODE" == "local-json" ]]; then
        echo "          passport-path: \"$PASSPORT_PATH\""
    fi
}

render_permissions() {
    if [[ "$MODE" == "auto" || "$MODE" == "hosted" ]]; then
        echo "  id-token: write"
    fi
    echo "  contents: read"
    echo "  pull-requests: read"
}

write_workflow() {
    local file="$1"
    local branch_lines
    branch_lines="$(render_branch_lines "$PUSH_BRANCHES")"
    refuse_symlink_path "$file"
    if [[ -f "$file" && -z "$FORCE" ]]; then
        log_warn "Workflow already exists; leaving unchanged: ${file#$PROJECT_DIR/}"
        echo "         Re-run with --force to overwrite it." >&2
        return 1
    fi

    mkdir -p "$(dirname "$file")"
    cat > "$file" << YAML
name: APort Repository Guard

on:
  pull_request:
    types:
      - opened
      - synchronize
      - reopened
      - ready_for_review
      - labeled
      - unlabeled
      - review_requested
      - review_request_removed
  pull_request_review:
    types:
      - submitted
      - dismissed
  push:
    branches:
$branch_lines
  merge_group:

permissions:
$(render_permissions)

jobs:
  aport:
    name: APort / OAP code.repository.merge.v1
    if: >-
      github.event_name != 'pull_request_review' ||
      github.event.action == 'dismissed' ||
      github.event.review.state != 'commented'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: APort repository guard
        uses: $ACTION_REF
        with:
$(render_action_inputs)
YAML
    log_info "Wrote ${file#$PROJECT_DIR/}"
    return 0
}

write_policy() {
    local file="$1"
    refuse_symlink_path "$file"
    if [[ -f "$file" && -z "$FORCE" ]]; then
        log_warn "Policy already exists; leaving unchanged: ${file#$PROJECT_DIR/}"
        echo "         Re-run with --force to overwrite it." >&2
        return 1
    fi

    mkdir -p "$(dirname "$file")"
    cat > "$file" << 'YAML'
version: oap-github-policy/1

repository:
  protected_paths:
    - .github/workflows/**
    - .aport/**
    - src/**
    - packages/**
    - package.json
    - package-lock.json
    - pnpm-lock.yaml
    - yarn.lock
YAML
    log_info "Wrote ${file#$PROJECT_DIR/}"
    return 0
}

echo ""
echo "  APort Agent Guardrails — GitHub setup"
echo "  ─────────────────────────────────────"
echo "  Repository: $PROJECT_DIR"
echo ""

if [[ "$MODE" == "local-json" ]]; then
    if [[ -L "$PROJECT_DIR/$PASSPORT_PATH" ]]; then
        log_error "Refusing local-json passport symlink: $PASSPORT_PATH"
        exit 1
    fi
    if [[ ! -f "$PROJECT_DIR/$PASSPORT_PATH" ]]; then
        log_error "mode local-json requires a trusted passport file at $PASSPORT_PATH. Create it first or use --mode auto."
        exit 1
    fi
fi

workflow_written=""
policy_written=""
if write_workflow "$WORKFLOW_FILE"; then
    workflow_written="1"
fi

if [[ -n "$WRITE_POLICY" ]]; then
    if write_policy "$POLICY_FILE"; then
        policy_written="1"
    fi
else
    if [[ -f "$POLICY_FILE" ]]; then
        log_info "Found existing .aport/policy.yaml; leaving unchanged."
    else
        log_info "Policy file not created. Add --policy for a starter .aport/policy.yaml."
    fi
fi

echo ""
echo "  Next steps (GitHub):"
echo "  ─────────────────────"
echo "  - Review .github/workflows/aport-guard.yml."
if [[ -n "$WRITE_POLICY" ]]; then
    echo "  - Tune .aport/policy.yaml for your repository paths."
else
    echo "  - Optional: run again with --policy to add a starter .aport/policy.yaml."
fi
echo "  - Commit the generated files and open or update a pull request."
echo "  - The workflow runs in mode: $MODE and uses GitHub OIDC in auto/hosted mode; no broad APort API key is required."
echo "  - Push detection watches: $PUSH_BRANCHES"
if [[ -n "$PROTECTED_PATHS" ]]; then
    echo "  - Protected path globs: $PROTECTED_PATHS"
fi
if [[ -n "$BLOCK_PROTECTED_PATHS" ]]; then
    echo "  - Protected path changes will fail hosted verification."
fi
if [[ "$MODE" == "local-json" ]]; then
    echo "  - Local JSON passport path: $PASSPORT_PATH"
fi
echo ""

if [[ -z "$workflow_written" && (-z "$WRITE_POLICY" || -z "$policy_written") ]]; then
    log_info "No files changed."
fi
