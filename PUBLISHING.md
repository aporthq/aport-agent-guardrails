# Publishing Guide

How we publish **APort Agent Guardrails** to npm and what gets shipped.

## What gets published

Each version bump merged to `main` dispatches the [Release workflow](.github/workflows/release.yml),
which tags the matching source, publishes npm/PyPI packages, bundles enterprise scripts, and
creates or repairs the GitHub Release.

**Primary npm package:** [`@aporthq/aport-agent-guardrails`](https://www.npmjs.com/package/@aporthq/aport-agent-guardrails)

The release also publishes the workspace npm packages documented in
[docs/RELEASE.md](docs/RELEASE.md), including the Node core package, framework adapters,
`@aporthq/openclaw-aport`, and the deprecated compatibility alias. Python packages are published
to PyPI from the same version tag.

**Contents of the npm tarball:**

| Path | Description |
|------|-------------|
| `bin/` | All scripts: `openclaw` (setup wizard), `aport-guardrail.sh`, `aport-create-passport.sh`, etc. |
| `src/` | Node evaluator and server |
| `extensions/openclaw-aport/` | OpenClaw plugin (deterministic enforcement) |
| `external/` | Policy packs and spec (aport-policies, aport-spec) — bundled at publish time from submodules |
| `docs/` | QUICKSTART, TOOL_POLICY_MAPPING, etc. |
| `templates/`, `local-overrides/`, `skills/`, `LICENSE`, `README.md` | Supporting files |

So after `npm install @aporthq/aport-agent-guardrails` or `npx @aporthq/aport-agent-guardrails`, the package is **self-contained**: no git clone or submodule init required.

**Does the guardrail get installed without `make install`?** Yes. The **setup wizard** (`bin/openclaw`, run when you execute `npx @aporthq/aport-agent-guardrails`) does the installation: it creates wrappers in your config dir (e.g. `~/.openclaw/.skills/`) that point back at the package’s `bin/` and `external/`. So the interactive setup does not use Make at all. The package’s `install` script runs `make install` only when a Makefile is present (i.e. when installed from a clone, to copy scripts into `~/.openclaw/.skills`); when installed from the npm tarball there is no Makefile, so the script no-ops and install succeeds.

## User-facing entrypoints

- **`npx @aporthq/aport-agent-guardrails`** — runs the setup wizard (`bin/openclaw`): passport, plugin install, gateway restart, smoke test. This is the recommended one-command flow.
- **`aport-guardrail`** (from installed package) — run a single guardrail check (e.g. from CI or after setup).

## Release workflow

**Merges to main are releases only when the package version changes.** The
`release-on-version.yml` dispatcher compares the previous and current `package.json` version.
When the version changes, it dispatches `release.yml` on `main` with that version.

The canonical process (single version for all packages, Changesets, Python sync) is in **[docs/RELEASE.md](docs/RELEASE.md)**. Summary:

1. **Bump version** using `npm run version` (runs Changesets for the fixed workspace group, then syncs the root CLI package, Python packages, lockfiles, manifests, and release docs). Commit the version bump and changelog updates.
2. **Merge the release PR to `main`.**
3. **CI runs automatically:** the release dispatcher triggers the [Release workflow](.github/workflows/release.yml). It:
   - Verifies the requested version matches the tagged source
   - Creates the missing annotated `vX.Y.Z` tag when needed
   - Publishes npm packages and PyPI packages, skipping already-published artifacts during recovery
   - Bundles enterprise scripts for macOS, Linux, and Windows
   - Creates or repairs the GitHub Release for that tag

Manual tag pushes still work as a fallback when the tag matches `package.json`, but the normal
path is version bump PR -> merge to `main` -> automatic release dispatch. See
[docs/RELEASE.md](docs/RELEASE.md) for the exact checklist.

## Comparison to agent-passport

| Aspect | agent-passport | aport-agent-guardrails |
|--------|----------------|------------------------|
| Structure | Monorepo (SDK node/python, middleware) | Single npm package + bundled submodules |
| Publish trigger | Tags / manual “Publish Packages” | Version bump on `main` dispatches release; tag push remains a fallback |
| Version bump | `npm run version:patch` etc. | `npm run version` (Changesets + sync-version) |
| What’s published | Multiple packages (npm + PyPI) | Root CLI package, workspace npm packages, OpenClaw plugin package, deprecated alias, and Python packages |

## Prerequisites

- **GitHub:** Merge the version bump to `main`; the dispatcher creates the tag and release workflow run.
- **npm:** `NPM_TOKEN` (Automation token) in repo secrets so the workflow can publish.
- **PyPI:** `PYPI_TOKEN` in repo secrets or trusted publishing configured for the `Release` workflow.

## Troubleshooting

- **Publish fails:** Ensure `NPM_TOKEN` is set and the version in `package.json` is **newer** than the last published version.
- **Package missing policy/spec submodules:** Ensure the Release workflow uses `actions/checkout` with `submodules: recursive` so `external/` is included in the tarball.
