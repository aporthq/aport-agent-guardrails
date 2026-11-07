#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The collected test builds the TypeScript workspaces and drives the Python
# evaluator, so name the missing prerequisite instead of failing deep inside.
if [[ ! -x "$REPO_ROOT/node_modules/.bin/tsc" ]]; then
    echo "FAIL: REPORTING_WRAPPER_NODE_PREREQUISITE: node_modules/.bin/tsc is missing; run 'npm ci' before 'make test'" >&2
    exit 1
fi
if ! python3 -c 'import yaml' > /dev/null 2>&1; then
    echo "FAIL: REPORTING_WRAPPER_PYTHON_PREREQUISITE: PyYAML is missing; install python/aport_guardrails[dev] before 'make test'" >&2
    exit 1
fi
npm run build:core --prefix "$REPO_ROOT" > /dev/null
npm run build --prefix "$REPO_ROOT" -w @aporthq/aport-agent-guardrails-langchain > /dev/null
node --test "$REPO_ROOT/tests/unit/installation-reporting-integration.test.js"
