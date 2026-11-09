# Release process and version policy

**Current release:** 1.0.37 (see [CHANGELOG.md](../CHANGELOG.md)).

We keep **one version number** across all published packages (Node core, Python core, and every framework adapter). That avoids “core is 1.2 but CLI is 0.9” and keeps the story simple for users and support.

---

## 1. Version policy summary

| What | Policy |
|------|--------|
| **Core packages** | `@aporthq/aport-agent-guardrails` (root/CLI), `@aporthq/aport-agent-guardrails-core`, `aport-agent-guardrails` (Python) always share the same version (e.g. `1.3.0`). |
| **Framework adapters** | Node: `@aporthq/aport-agent-guardrails-langchain`, `-crewai`, `-cursor`, `-claude-code`, and `@aporthq/openclaw-aport` (published). `-n8n` is **not published yet** (coming soon). Python: `aport-agent-guardrails-langchain`, `aport-agent-guardrails-crewai`. They depend on core with `>=` and publish with the same version as core. |
| **Repo tag** | Git tag `v1.3.0` matches the released version so docs and installs stay aligned. |

So: **one version for the whole suite.** If only the LangChain adapter changed, we still bump core (and all other packages) to the same new version so everything stays in lockstep.

---

## 1.1. Why two npm packages: @aporthq/aport-agent-guardrails vs @aporthq/aport-agent-guardrails-core?

| Package | What it is | Who installs it |
|---------|------------|------------------|
| **@aporthq/aport-agent-guardrails** (root) | The **CLI and setup tool**: `bin/agent-guardrails`, framework installers (bash scripts), docs, OpenClaw extension. No TypeScript evaluator — it runs the passport wizard and writes config. | Users who want the one-line setup: `npx @aporthq/aport-agent-guardrails langchain` (or cursor, crewai, openclaw). |
| **@aporthq/aport-agent-guardrails-core** | The **Node library**: Evaluator, config, passport loading, `verify` / `verifySync`. Used inside your app to enforce policy. | Anyone using the **framework adapters** (e.g. `@aporthq/aport-agent-guardrails-langchain`) — they depend on core. Also apps that want only the evaluator without the CLI. |

So: **root = CLI/setup**; **core = library**. We publish core so that (1) the adapters can declare it as a dependency and npm can resolve it, and (2) users can install just the evaluator if they don’t need the full CLI.

---

## 2. Tooling

- **Changesets** (Node): fixed mode so all workspace packages are in one “fixed” group and get the same version on release.
- **sync-version script**: after `changeset version`, reads the canonical version from the fixed workspace group and propagates it to the root CLI package, Python packages, manifests, lockfiles, and release docs.

---

## 3. Release flow

1. **Merge PRs** → run automated tests (e.g. CI).
2. **Bump version and changelogs**  
   ```bash
   npm run version
   ```  
   This runs `changeset version` for the fixed workspace group, then `node scripts/sync-version.mjs` to align the root CLI package, Python packages, lockfiles, manifests, and release docs to that same version.
3. **Commit** the version bump and changelog updates (e.g. “chore(release): 1.3.0”).
4. **Merge the release PR to `main`**. The `Dispatch Release On Version Bump` workflow detects the package version change and dispatches `.github/workflows/release.yml` with that version.
5. **CI (`.github/workflows/release.yml`)**:
   - On `workflow_dispatch`, verifies the requested version matches `package.json`, runs the release regression gate, creates the annotated `vX.Y.Z` tag when it is missing, and then publishes.
   - On manual tag push `v*`, verifies the tag version matches `package.json`, runs the release regression gate, and then publishes.
   - **publish-npm**: publishes the **root** package `@aporthq/aport-agent-guardrails` (CLI), workspace packages `@aporthq/aport-agent-guardrails-core`, `-langchain`, `-crewai`, `-cursor`, `-claude-code`, `@aporthq/openclaw-aport`, and the deprecated compatibility alias `@aporthq/agent-guardrails` to npm. The **n8n** package is not published yet (coming soon). Uses `NPM_TOKEN` secret.
   - **publish-python**: builds and publishes `aport-agent-guardrails`, `aport-agent-guardrails-langchain`, and `aport-agent-guardrails-crewai` to PyPI (uses `PYPI_TOKEN` secret). Uploads use `--skip-existing`, so reruns or recovery releases can still publish any missing Python artifacts for the same version.
   - **workflow_dispatch**: supports release recovery for an existing version after workflow fixes land on `main`.
   - **create-release**: creates the GitHub Release with install notes for both ecosystems.

   **PyPI**: In [PyPI project settings](https://pypi.org/help/#project-urls), set Repository and (if using trusted publishing) add this repo and workflow name **Release**. Otherwise configure the `PYPI_TOKEN` secret in the GitHub repo.

If npm or PyPI registry consistency delays leave a release tag without a GitHub Release, a later push to `main` that touches the release workflow can dispatch the same version again. The release workflow checks out the existing tag, skips already-published artifacts, verifies registry availability, and creates the missing GitHub Release.

### Manual fallback

If the automatic dispatcher is unavailable, run the existing release workflow manually from GitHub Actions with the desired `version`. The workflow will create the missing tag if the requested version matches `package.json`.

You can still push a tag manually if needed:

```bash
git tag v1.3.0
git push origin v1.3.0
```

---

## 4. Adding a changeset (before release)

After making any change that should go into the next release:

```bash
npx changeset
# or
npm run changeset
```

- Choose **patch** / **minor** / **major**.
- Write a short summary for the changelog.
- Commit the new file under `.changeset/`.

When you run `npm run version`, that changeset will drive a single version bump for the whole fixed group; then `sync-version` keeps Python in sync.

---

## 5. Release verification records

Each prepared candidate gets a sanitized JSON record under `docs/reviews/`,
generated from the actual built artifacts rather than written by hand:

```bash
npm run build
# pack the npm archives and build the three Python distributions first
node scripts/validate-release-artifacts.mjs --npm-dir <dir> --out <artifacts.json>
node scripts/validate-release-fixture-matrix.mjs --out <fixtures.json>
node scripts/build-release-verification-record.mjs \
  --artifacts <artifacts.json> --fixtures <fixtures.json> \
  --out docs/reviews/installation-reporting-release-<version>.json
```

`scripts/check-release-verification-record.mjs` is the schema and sanitization
gate, and `tests/unit/test-release-verification-record.sh` runs it against the
current version's committed record plus deliberately poisoned copies. The test
derives the filename from `packages/core/package.json`; a version bump needs
its own record and never rewrites or substitutes an older release's evidence.
The builder requires explicit empty artifact-problem and fixture-violation
lists before writing a record. Inspection commands retain failed diagnostics,
but those files are not successful release evidence.

`tests/unit/test-release-validation-regressions.sh` exercises that boundary,
including a temporary runtime with installation-scope checks removed. The
rotation fixture requires the foreign enqueue to reject and send zero requests;
the rotated token for the same installation must actually deliver successfully.

The record keeps only
bounded allowlisted metadata: identifiers, digests, counts, booleans, and
authored constants. Credentials, private paths, prompts, commands, and raw tool
inputs and outputs are rejected, as is fixture evidence labelled as a live run.

The current record is
[installation-reporting-release-1.0.37.json](reviews/installation-reporting-release-1.0.37.json).

**1.0.37 scope.** Validation used isolated local contract fixtures and synthetic
credentials. Live deployment compatibility is recorded as `not_run` with no
deployment identifier, because the operator waived live sandbox qualification
for that preparation task. Fixture success is not evidence of compatibility with
a deployed Agent Passport backend. Unsigned `adapter_failure`/`unavailable`
receipts stay deferred, Windows reporting stays unresolved, and hosts without a
trustworthy post-action signal stay `not_reported`. See
[docs/installation-reporting.md](installation-reporting.md) for the full list.
Earlier qualification records keep their original unmet claims; the per-release
record states the scope of its own run rather than retiring theirs.

---

## 6. Long-term flexibility

If we later need finer control (e.g. enterprise adapters that shouldn’t force a full suite release), we can:

- Move to independent versioning for some adapters, and/or
- Introduce a “meta” package that pins compatible versions.

For now, a single version across all packages keeps the ecosystem coherent and avoids support confusion.
