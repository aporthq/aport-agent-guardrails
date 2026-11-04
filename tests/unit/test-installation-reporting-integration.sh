#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
npm run build:core --prefix "$REPO_ROOT" > /dev/null
npm run build --prefix "$REPO_ROOT" -w @aporthq/aport-agent-guardrails-langchain > /dev/null
node --test "$REPO_ROOT/tests/unit/installation-reporting-integration.test.js"
