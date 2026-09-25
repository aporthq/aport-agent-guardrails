#!/bin/bash
# Unit test: every library a manifest file sources is itself in the runtime manifest, so the installed runtime
# tree is self-contained. Regression for passport-reuse.sh, sourced by quick-hosted.sh but not copied.
set -e
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$REPO_ROOT/bin/lib/runtime-manifest.txt"
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -q '^file bin/lib/passport-reuse.sh$' "$MANIFEST" || fail "bin/lib/passport-reuse.sh must be in the runtime manifest"

listed="$(grep '^file bin/' "$MANIFEST" | sed 's/^file //')"
while IFS= read -r file; do
    case "$file" in bin/lib/*.sh | bin/*.sh) ;; *) continue ;; esac
    # Sibling sources spelled as source "$<dir>/name.sh" or source "$(...)/name.sh" inside the lib dir.
    for dep in $(grep -oE 'source "[^"]*/(lib/)?[a-z-]+\.sh"' "$REPO_ROOT/$file" | grep -oE '[a-z-]+\.sh"$' | tr -d '"' | sort -u); do
        [[ -f "$REPO_ROOT/bin/lib/$dep" ]] || continue
        grep -qx "bin/lib/$dep" <<< "$listed" || fail "$file sources bin/lib/$dep, which is not in the runtime manifest"
    done
done <<< "$listed"
echo "PASS: runtime manifest lists every sourced library"
