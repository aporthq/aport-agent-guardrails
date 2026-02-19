# Release process and version policy

**Current release:** 1.0.8 (see [CHANGELOG.md](../CHANGELOG.md)).

We keep **one version number** across all published packages (Node core, Python core, and every framework adapter). That avoids “core is 1.2 but CLI is 0.9” and keeps the story simple for users and support.

---

## 1. Version policy summary

| What | Policy |
|------|--------|
| **Core packages** | `@aporthq/aport-agent-guardrails` (root/CLI), `@aporthq/aport-agent-guardrails-core`, `aport-agent-guardrails` (Python) always share the same version (e.g. `1.3.0`). |
| **Framework adapters** | Node: `@aporthq/aport-agent-guardrails-langchain`, `-crewai`, `-cursor` (published). `-n8n` is **not published yet** (coming soon). Python: `aport-agent-guardrails-langchain`, `aport-agent-guardrails-crewai`. They depend on core with `>=` and publish with the same version as core. |
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
- **sync-version script**: after `changeset version`, copies the new version from root `package.json` into all Python `pyproject.toml` and `aport_guardrails/__init__.py`.

---

## 3. Release flow

1. **Merge PRs** → run automated tests (e.g. CI).
2. **Bump version and changelogs**  
   ```bash
   npm run version
   ```  
   This runs `changeset version` (updates all Node `package.json` and CHANGELOGs) then `node scripts/sync-version.mjs` (updates Python packages to the same version).
3. **Commit** the version bump and changelog updates (e.g. “chore(release): 1.3.0”).
4. **Tag and push** — this triggers the release workflow and publishes both npm and PyPI:
   ```bash
   git tag v1.3.0
   git push origin v1.3.0
   ```
5. **CI (`.github/workflows/release.yml`)**: on tag push `v*`:
   - **publish-npm**: publishes the **root** package `@aporthq/aport-agent-guardrails` (CLI) and workspace packages `@aporthq/aport-agent-guardrails-core`, `-langchain`, `-crewai`, `-cursor` to npm. The **n8n** package is not published yet (coming soon). Uses `NPM_TOKEN` secret.
   - **publish-python**: builds and publishes `aport-agent-guardrails`, `aport-agent-guardrails-langchain`, and `aport-agent-guardrails-crewai` to PyPI (uses `PYPI_TOKEN` secret). Skips upload if aport-agent-guardrails version already exists.
   - **create-release**: creates the GitHub Release with install notes for both ecosystems.

   **PyPI**: In [PyPI project settings](https://pypi.org/help/#project-urls), set Repository and (if using trusted publishing) add this repo and workflow name **Release**. Otherwise configure the `PYPI_TOKEN` secret in the GitHub repo.

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

## 5. Long-term flexibility

If we later need finer control (e.g. enterprise adapters that shouldn’t force a full suite release), we can:

- Move to independent versioning for some adapters, and/or
- Introduce a “meta” package that pins compatible versions.

For now, a single version across all packages keeps the ecosystem coherent and avoids support confusion.
