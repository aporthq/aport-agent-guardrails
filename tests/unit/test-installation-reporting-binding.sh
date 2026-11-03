#!/bin/bash
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node --test "$REPO_ROOT/tests/unit/installation-reporting-binding.test.js"
