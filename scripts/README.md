# Scripts

## Submodules: ensure up to date before push

### `ensure-submodules-updated.sh`

Used by the pre-push hook. Ensures submodules are initialized and, with `--update-remote`, updated to the latest remote commit. Exits 1 if refs changed and are uncommitted (so you must commit submodule updates before pushing).

```bash
./scripts/ensure-submodules-updated.sh           # init only
./scripts/ensure-submodules-updated.sh --update-remote   # init + fetch latest, fail if uncommitted
```

### Pre-push hook (runs on every push)

Hooks live in **`scripts/git-hooks/`** and are used by Git so that **every `git push`** runs the submodule check.

**One-time per clone:**

```bash
make install-git-hooks
```

This sets `git config core.hooksPath scripts/git-hooks`. Git then runs hooks from this directory (e.g. `pre-push`) on every push. No copy into `.git/hooks`—the committed hooks in the repo are used.

After that, every push will:

1. Run `git submodule update --init --recursive`
2. Run `git submodule update --remote`
3. If any submodule ref changed, block the push and tell you to commit the updated refs, then push again
4. Run `scripts/pre-push-check.sh` for the local workflow-equivalent checks

### `pre-push-check.sh`

Runs the blocking GitHub workflow-equivalent checks locally:

- `jq` passport schema validation
- `shellcheck` and `shfmt -d`
- `make test`
- `npm run build`
- `npm run test -w @aporthq/aport-agent-guardrails-core -w @aporthq/aport-agent-guardrails-langchain`
- `node tests/frameworks/openclaw/setup.test.mjs`
- `npm test` in `extensions/openclaw-aport`
- isolated Python package builds + `twine check`
- CrewAI, LangChain, and OpenClaw E2E flows using cached `/tmp` virtualenvs / temp homes

Run it manually with:

```bash
npm run prepush:check
```

Useful environment flags:

```bash
APORT_SKIP_PRE_PUSH_CHECKS=1 git push          # skip hook checks once
APORT_PRE_PUSH_INCLUDE_OPTIONAL=1 npm run prepush:check  # also run gitleaks / trufflehog if installed
APORT_PRE_PUSH_INCLUDE_OPENCLAW_LIVE=1 npm run prepush:check  # include the live OpenClaw CLI E2E step
```
