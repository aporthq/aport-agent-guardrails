# Publishing Guide

How we publish **APort Agent Guardrails** to npm and what gets shipped.

## What gets published

Each **GitHub Release** (e.g. `v1.0.0`) triggers the [Release workflow](.github/workflows/release.yml), which runs `npm publish` from the repo root.

**Published package:** [`@aporthq/aport-agent-guardrails`](https://www.npmjs.com/package/@aporthq/aport-agent-guardrails)

**Contents of the npm tarball:**

| Path | Description |
|------|-------------|
| `bin/` | All scripts: `openclaw` (setup wizard), `aport-guardrail.sh`, `aport-create-passport.sh`, etc. |
| `src/` | Node evaluator and server |
| `extensions/openclaw-aport/` | OpenClaw plugin (deterministic enforcement) |
| `external/` | Policy packs and spec (aport-policies, aport-spec) — bundled at publish time from submodules |
| `docs/` | QUICKSTART, TOOL_POLICY_MAPPING, etc. |
| `templates/`, `policies/`, `LICENSE`, `README.md` | Supporting files |

So after `npm install @aporthq/aport-agent-guardrails` or `npx @aporthq/aport-agent-guardrails`, the package is **self-contained**: no git clone or submodule init required.

**Does the guardrail get installed without `make install`?** Yes. The **setup wizard** (`bin/openclaw`, run when you execute `npx @aporthq/aport-agent-guardrails`) does the installation: it creates wrappers in your config dir (e.g. `~/.openclaw/.skills/`) that point back at the package’s `bin/` and `external/`. So the interactive setup does not use Make at all. The package’s `install` script runs `make install` only when a Makefile is present (i.e. when installed from a clone, to copy scripts into `~/.openclaw/.skills`); when installed from the npm tarball there is no Makefile, so the script no-ops and install succeeds.

## User-facing entrypoints

- **`npx @aporthq/aport-agent-guardrails`** — runs the setup wizard (`bin/openclaw`): passport, plugin install, gateway restart, smoke test. This is the recommended one-command flow.
- **`aport-guardrail`** (from installed package) — run a single guardrail check (e.g. from CI or after setup).

## Release workflow (tag-driven)

**Merges to main are not releases.** A release happens only when you push a **tag** `v*`.

The canonical process (single version for all packages, Changesets, Python sync) is in **[docs/RELEASE.md](docs/RELEASE.md)**. Summary:

1. **Bump version** using `npm run version` (runs Changesets then syncs version to Python packages). Commit the version bump and changelog updates.
2. **Publish** Node packages (e.g. `npx changeset publish`) and Python packages to PyPI as needed.
4. **Tag and push** (from your local `main`, or from the merge commit):
   ```bash
   git checkout main && git pull
   git tag v1.0.1   # must match package.json "version"
   git push origin v1.0.1
   ```
5. **CI runs automatically:** the [Release workflow](.github/workflows/release.yml) triggers on tag push. It:
   - Checks out that tag with submodules
   - Runs `npm publish`
   - Creates the GitHub Release for that tag (with generated notes)

So: **same process every time** — bump version, merge to main, then `git tag vX.Y.Z && git push origin vX.Y.Z`. No need to create the release in the GitHub UI. See [docs/RELEASE.md](docs/RELEASE.md) for the exact checklist.

## Comparison to agent-passport

| Aspect | agent-passport | aport-agent-guardrails |
|--------|----------------|------------------------|
| Structure | Monorepo (SDK node/python, middleware) | Single npm package + bundled submodules |
| Publish trigger | Tags / manual “Publish Packages” | Tag push `v*` (then npm publish + release created) |
| Version bump | `npm run version:patch` etc. | `npm run version` (Changesets + sync-version) |
| What’s published | Multiple packages (npm + PyPI) | One package: `@aporthq/aport-agent-guardrails` |

## Prerequisites

- **GitHub:** Push a tag `vX.Y.Z`; workflow runs and creates the release.
- **npm:** `NPM_TOKEN` (Automation token) in repo secrets so the workflow can publish.

## Troubleshooting

- **Publish fails:** Ensure `NPM_TOKEN` is set and the version in `package.json` is **newer** than the last published version.
- **Package missing policies/spec:** Ensure the Release workflow uses `actions/checkout` with `submodules: recursive` so `external/` is included in the tarball.
