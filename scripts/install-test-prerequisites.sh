#!/usr/bin/env bash
# Shared bootstrap for Ubuntu CI and release validation; package manifests own dependencies.
set -euo pipefail

# Recovery keeps this verified helper outside the old tag and supplies its checkout root.
REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"

sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=20 update
sudo apt-get install -y --no-install-recommends curl jq uuid-runtime
python -m pip install --upgrade pip
python -m pip install --disable-pip-version-check --no-input build -e "python/aport_guardrails[dev]" -e "python/langchain_adapter[dev]"
python -m pip check
