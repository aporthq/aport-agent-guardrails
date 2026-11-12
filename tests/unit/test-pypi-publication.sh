#!/bin/bash
# Execute the workflow's actual verification function against inert registry responses.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import yaml

root = Path(sys.argv[1])
workflow = yaml.load((root / ".github/workflows/release.yml").read_text(), Loader=yaml.BaseLoader)
steps = workflow["jobs"]["publish-python"]["steps"]
source = next(step["run"] for step in steps if step.get("name") == "Verify PyPI publication")
match = re.search(r"(?ms)^verify_py\(\) \{.*?^\}", source)
assert match is not None, "PYPI_VERIFIER_REACHED: actual workflow function is missing"
function = match.group()
packages = ["aport-agent-guardrails", "aport-agent-guardrails-langchain", "aport-agent-guardrails-crewai"]
stub = """
set -uo pipefail
VERSION=1.0.38
python() {
  printf '%s\\n' "$PKG" >> "$TRACE"
  [[ "$PKG" != "$MISSING" ]]
}
"""
with tempfile.TemporaryDirectory(prefix="aport-pypi-verification-") as directory:
    for index, missing in enumerate(["", *packages]):
        trace = Path(directory) / str(index)
        result = subprocess.run(["bash", "-c", stub + function + "\nverify_py\n"], env={**os.environ, "TRACE":str(trace), "MISSING":missing}, capture_output=True, text=True, timeout=10)
        visited = trace.read_text().splitlines()
        assert visited, "PYPI_VERIFIER_REACHED: no package was queried"
        if missing:
            assert missing in visited, "PYPI_VERIFIER_REACHED: missing-package fixture was not reached"
            assert result.returncode != 0, f"PYPI_EACH_PACKAGE_REQUIRED: missing {missing} was reported as success"
        else:
            assert result.returncode == 0, result.stderr
            assert visited == packages, "PYPI_ALL_PACKAGES_QUERIED: success must check every package"
print("PASS: all three Python packages are required; each missing-package position fails")
PY

