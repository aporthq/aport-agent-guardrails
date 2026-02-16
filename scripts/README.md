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
