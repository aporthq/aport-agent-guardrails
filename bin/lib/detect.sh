#!/usr/bin/env bash
# Framework detection from project directory (cwd or first arg).
# Used by bin/agent-guardrails to skip prompt when project is detectable.
# detect_framework: echoes first detected framework or empty.
# detect_frameworks_list: echoes all detected frameworks (space-separated, unique)
#   so the dispatcher can show "Multiple frameworks detected: X, Y. Choose one: ...".

# shellcheck source=./common.sh
source "$(dirname "${BASH_SOURCE[0]:-.}")/common.sh"

# Collect all detected framework names (unique, order: pyproject -> package.json -> requirements)
detect_frameworks_list() {
  local dir="${1:-.}"
  local list=()

  [[ ! -d "$dir" ]] && echo "" && return 0

  # Python: pyproject.toml
  if [[ -f "$dir/pyproject.toml" ]]; then
    grep -qi 'langchain\|langgraph' "$dir/pyproject.toml" 2>/dev/null && list+=(langchain)
    grep -qi 'crewai' "$dir/pyproject.toml" 2>/dev/null && list+=(crewai)
  fi

  # Node: package.json
  if [[ -f "$dir/package.json" ]]; then
    grep -qi 'openclaw\|open-claw\|agent-guardrails' "$dir/package.json" 2>/dev/null && list+=(openclaw)
  fi

  # requirements.txt fallback
  if [[ -f "$dir/requirements.txt" ]]; then
    grep -qi 'langchain' "$dir/requirements.txt" 2>/dev/null && list+=(langchain)
    grep -qi 'crewai' "$dir/requirements.txt" 2>/dev/null && list+=(crewai)
  fi

  # Dedupe preserving order (first occurrence wins). Safe for set -u when list is empty.
  local seen=() out=()
  if [[ ${#list[@]} -gt 0 ]]; then
    for fw in "${list[@]}"; do
      if [[ " ${seen[*]:-} " != *" $fw "* ]]; then
        seen+=("$fw")
        out+=("$fw")
      fi
    done
  fi
  if [[ ${#out[@]} -gt 0 ]]; then
    echo "${out[*]}"
  else
    echo ""
  fi
  return 0
}

# Return first detected framework (for single-detection behavior); empty if none.
detect_framework() {
  local list
  list="$(detect_frameworks_list "${1:-.}")"
  if [[ -n "$list" ]]; then
    echo "${list%% *}"
  else
    echo ""
  fi
  return 0
}

export -f detect_framework detect_frameworks_list
