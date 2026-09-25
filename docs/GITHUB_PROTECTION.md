# GitHub Protection

APort protects GitHub work by verifying repository activity against an OAP passport and recording an OAP decision. The same hosted verifier used by Claude Code, Cursor, OpenClaw, and other agent runtimes evaluates GitHub policy packs and records decisions.

Use this when you want report-only evidence first, then blocking controls for higher-risk repository workflows such as protected-branch updates and automation run by coding agents. Release and package-publish policy checks are supported by the guardrail/verifier mapping, but the current Repository Guard Action is the `code.repository.merge.v1` slice.

## Recommended Path

Use hosted verification for GitHub Actions. To generate the starter workflow from a repository root:

```bash
npx @aporthq/aport-agent-guardrails github
```

Add `--policy` if you also want a starter `.aport/policy.yaml`. Existing workflow or policy files are left untouched unless you pass `--force`. Use `--branches main,staging` to include additional protected push branches.

For blocking enforcement on protected branches:

```bash
npx @aporthq/aport-agent-guardrails github --mode hosted --branches main,staging
```

For repositories with sensitive release, workflow, package, or guardrail code, pass the same protected-path globs you want the Action to check:

```bash
npx @aporthq/aport-agent-guardrails github \
  --mode hosted \
  --branches main,staging \
  --block-protected-paths \
  --protected-paths ".github/workflows/**,.aport/**,bin/**,packages/**,scripts/**,package.json,package-lock.json"
```

Hosted mode gives APort the context it needs for production-grade repository controls:

- GitHub OIDC identity for the workflow run.
- Signed OAP decision receipts.
- Central audit across repositories and organizations.
- Passport suspend/update controls from the APort dashboard.
- Future policy updates without changing local shell logic.

Local mode is still useful for developer/offline smoke tests, but it cannot independently validate GitHub-issued OIDC claims or server-side repository facts.

## What Gets Protected

| Current Repository Guard Action surface | Tool/policy name | What APort checks |
| --- | --- | --- |
| PR create/update | `git.create_pr` -> `code.repository.merge.v1` | `repo.pr.create`, allowed repos, base branch, changed paths, PR size |
| PR merge | `git.merge` -> `code.repository.merge.v1` | `repo.merge`, allowed repos, base branch, changed paths |
| Repository push | `git.push` -> `code.repository.merge.v1` | `repo.push`, allowed repos, target branch, changed paths. Free GitHub OIDC passports do not include `repo.push` by default, so direct pushes are detected and denied unless the repo explicitly authorizes them. |

Explicit release publishing uses the same guardrail mapping, but is not part of the first Repository Guard Action workflow:

| Agent/runtime or direct guardrail surface | Tool/policy name | What APort checks |
| --- | --- | --- |
| Release publish | `release.publish` -> `code.release.publish.v1` | `repo.release`, allowed repos, semantic version, release files |

Shell commands such as `npm publish`, `pnpm publish`, and `gh release create` are evaluated as `system.command.execute.v1` when they arrive through Claude Code, Cursor, or another shell hook. Use an explicit `release.publish`/`git.release` tool name or hosted API verification when you want `code.release.publish.v1`.

## Minimal Workflow Shape

The canonical GitHub Repository Guard Action lives in the `agent-passport` repository under `integrations/github/actions/policy-verify/` and is published to `aporthq/policy-verify-action`.

```yaml
permissions:
  contents: read
  id-token: write
  pull-requests: read

steps:
  - name: APort repository guard
    uses: aporthq/policy-verify-action@v1
    with:
      mode: auto
```

Default `auto` mode requests GitHub OIDC, creates or reuses a hosted repository-scoped OAP passport, records a report-only decision through APort Verify, and falls back to labelled evidence-only reporting if hosted verification is unavailable. No APort API key is required for that free report-only path.

For blocking enforcement, switch to explicit hosted mode after the org has reviewed the first decisions and tuned passport limits:

```yaml
- name: APort repository guard
  uses: aporthq/policy-verify-action@v1
  with:
    mode: hosted
    block-protected-paths: true
    protected-paths: ".github/workflows/**,.aport/**,src/**,packages/**,package.json"
```

### Pinning the Action

GitHub's workflow syntax reference calls a full commit SHA the safest way to reference an action; a major tag such as `@v1` moves with every patch release. The installer writes `@v1` so new repositories pick up fixes without edits. To pin, set the ref before running the installer:

```bash
APORT_GITHUB_ACTION_REF=aporthq/policy-verify-action@433d32239fa46c483bc5936d9bae8c5163d85c03 \
  npx @aporthq/aport-agent-guardrails github --force
```

That SHA is the `v1.0.11` release commit (2026-09-21). APort's own repository workflow pins it with a `# v1.0.11` comment so the bump is visible in review. Dependabot and Renovate both update SHA-pinned `uses:` lines and keep the version comment current. When the base-branch `.aport/policy.yaml` sets `github.require_pinned_actions: true`, the Action itself flags unpinned actions in pull requests.

Explicit `hosted` mode fails the workflow when hosted verification cannot return a valid signed decision, returns `allow: false`, or reports a high/error structural finding. `block-protected-paths: true` escalates protected-path changes from warning to high severity; leave it off during first rollout if you only want visibility.

Avoid marking the entire repository as blocking protected paths on day one. Start
with the actual control plane, such as `.github/workflows/**`, `.aport/**`, and
release/package metadata, then expand only after the team has a review path for
those changes. For APort-owned repositories, the `aport-control-plane-approved`
label prefix is the maintainer break-glass path for reviewed guard workflow or
policy changes. The actual label must include the reviewed head SHA prefix, for
example `aport-control-plane-approved-4dfbf5cdc1a2`; the action still runs and
records its denial/audit output, and a later push invalidates the override.

## Default Branch Protection

The Repository Guard Action evaluates `code.repository.merge.v1`. On a `push` event it classifies the push as `merged_pull_request` (the tip commit is the merge commit of a pull request into that branch) or `direct`, and sends `repo.push` to the verifier. Two gaps remain, and an external audit called them out:

- In default `auto` mode the run is report-only, so a direct push to `main` produces evidence but never a red check.
- The Action does not read the push payload's `forced` flag, so a force push looks like any other push.

The `--protect-default-branch` flag closes both gaps through the Action (policy-verify-action 1.1.0 or newer):

```bash
npx @aporthq/aport-agent-guardrails github --protect-default-branch --force
```

It renders `protect-default-branch: true` under the Action's `with:` block. On a `push` to `github.event.repository.default_branch` the Action then fails the run when:

1. the payload's `forced` flag is true (finding `OAP.REPO.FORCE_PUSH`), or
2. `GET /repos/{owner}/{repo}/commits/{sha}/pulls` returns no merged pull request whose `merge_commit_sha` is the pushed tip (finding `OAP.REPO.DIRECT_PUSH_DEFAULT_BRANCH`). Merge, squash and rebase merges all pass. The lookup is retried three times ten seconds apart because the commit index can lag a merge; a lookup that fails every time classifies the push as `unknown` and fails closed.

Every run sets the `push-classification` output (`direct`, `merged_pull_request`, `forced`, `unknown`, `not_push`), so later steps can branch on it. With the input off, a force push to the default branch is still reported as a warning-level finding but never fails the run. No permissions beyond the `contents: read` and `pull-requests: read` the workflow already has are needed. The same environment variable works for CI: `APORT_GITHUB_PROTECT_DEFAULT_BRANCH=true`.

On APort's own repository the input is bound to the repository variable `APORT_PROTECT_DEFAULT_BRANCH`, so enabling it is a settings change rather than a workflow edit; it takes effect once the pinned Action is 1.1.0 or newer.

What it does not do: a `push` workflow runs after the commit is on the branch, so the Action records a failed check on the commit; it cannot reject the push. Downstream automation that keys on the commit's check status (deploy workflows, `gh run watch`, status-gated release jobs) can rely on the red check. Pair it with a GitHub ruleset on the default branch that blocks force pushes and requires a pull request before merging; the ruleset prevents, the Action proves. Merge-queue merges land as pushes by the queue and should classify as `merged_pull_request`; confirm that on the first queued merge before relying on the check in a merge-queue repository.

### Still open on the verifier side

The Action now carries the force-push finding and the classification output (items 1 and 2 of the earlier proposal; the `fail-on` input was folded into the single `protect-default-branch` boolean). What remains is verifier-side: `code.repository.merge.v1` gaining a `repo.push.allow_force_push` limit defaulting to `false`, so hosted policy can deny force pushes for passports that hold `repo.push` even when the input is off. No new policy pack is needed; the Action already sends `push_forced`, `push_to_default_branch` and `default_branch` in the verify context.

## Passport Requirements

For repository workflows, the passport should include only the capabilities that match the workflow being protected.

Common capabilities:

- `repo.pr.create` for PR creation/update checks.
- `repo.merge` for merge checks.
- `repo.push` for direct push checks on protected branches. Free GitHub OIDC passports omit this by default, so ordinary direct pushes are denied unless the repository intentionally authorizes them.
- `repo.release` only when directly invoking `code.release.publish.v1` for release publishing checks. Legacy local passports with `release` are still accepted as an alias.

Common limits:

```json
{
  "allowed_repos": ["aporthq/*"],
  "allowed_base_branches": ["main"],
  "allowed_paths": ["src/**", "packages/**", ".github/workflows/**"],
  "max_pr_size_kb": 500,
  "repo": {
    "allowed_paths": ["src/**", "packages/**", ".github/workflows/**"]
  },
  "code.release.publish": {
    "allowed_repos": ["aporthq/*"],
    "allowed_extensions": [".tgz", ".zip"]
  }
}
```

`code.release.publish` is shown here because the guardrail/verifier supports it. The current published Repository Guard Action uses `code.repository.merge.v1`.

Hosted verification can also use `integrations.github` allowlists on the passport. The local evaluator supports lightweight checks when these values are provided in the request context:

```json
{
  "integrations": {
    "github": {
      "allowed_repositories": ["aporthq/agent-passport"],
      "allowed_actors": ["uchibeke", "aport-deploy-bot"],
      "allowed_apps": ["github-actions"],
      "allowed_workflow_refs": ["aporthq/agent-passport/.github/workflows/*@refs/heads/main"],
      "allowed_job_workflow_refs": ["*"]
    }
  }
}
```

## Local Smoke Tests

Local checks are intentionally narrow and should be treated as smoke tests, not a replacement for hosted GitHub OIDC verification.

To test the published GitHub Action behavior locally, run the action source in `evidence-only` mode with a synthetic GitHub event. Use a real PR number from the repository if you want the action to fetch changed files and commits from GitHub. This exercises attribution, summary rendering, repository evidence fetches, protected-path checks, and outputs. It does not exercise hosted OIDC because GitHub only issues OIDC tokens inside Actions.

```bash
cat > /tmp/aport-pr-event.json <<'JSON'
{
  "pull_request": {
    "number": 123,
    "user": { "login": "octocat", "type": "User" },
    "head": { "ref": "feature-branch" },
    "base": { "ref": "staging" }
  },
  "repository": { "full_name": "aporthq/aport-agent-guardrails" },
  "sender": { "login": "octocat", "type": "User" }
}
JSON

APORT_MODE=evidence-only \
GITHUB_EVENT_NAME=pull_request \
GITHUB_EVENT_PATH=/tmp/aport-pr-event.json \
GITHUB_REPOSITORY=aporthq/aport-agent-guardrails \
GITHUB_STEP_SUMMARY=/tmp/aport-summary.md \
GITHUB_OUTPUT=/tmp/aport-output.txt \
node /path/to/policy-verify-action/src/index.js

cat /tmp/aport-summary.md
cat /tmp/aport-output.txt
```

To verify hosted behavior, push the workflow and open or update a PR. `mode: auto` should request GitHub OIDC, create or reuse a hosted repository-scoped OAP passport, write a signed APort decision, and fall back to labelled evidence-only only if hosted verification is unavailable.

```bash
aport-guardrail git.create_pr '{
  "repository": "aporthq/agent-passport",
  "action": "pr.update",
  "base_branch": "main",
  "files_changed": ["src/app.ts"]
}'

aport-guardrail release.publish '{
  "repository": "aporthq/agent-passport",
  "version": "1.2.3",
  "files": ["dist/app.tgz"]
}'
```

Exit `0` means allow. Exit `1` means deny.

## Rollout Guidance

1. Start with default `mode: auto` on one repository.
2. Confirm decisions appear in APort audit.
3. Tune `allowed_repos`, `allowed_base_branches`, and `allowed_paths`.
4. Switch high-risk workflows to explicit `mode: hosted` after hosted decisions are reliable.
5. Expand to more repositories after the audit signal is clean.

Do not use local JSON passports for organization-wide GitHub enforcement unless the goal is offline reporting only. Hosted passports are the default because APort can record central evidence and rotate/update policy without touching every repository.

## GitHub Reference Review (2026-09-24)

The framework drift watch flagged the three GitHub references (issue #107). What changed upstream and what it meant for the guard:

| Reference | Finding | Guard status |
| --- | --- | --- |
| Workflow syntax | `permissions` gained `artifact-metadata` and `code-quality`; specifying any permission sets the rest to `none`; `jobs.<id>.timeout-minutes` defaults to 360; new `cache-mode` key with a warning about write mode on low-trust triggers; full commit SHA named the safest `uses:` ref. | `contents`, `id-token`, `pull-requests` unchanged. Guard sets `timeout-minutes: 5`, uses no cache, and now pins by SHA in the repository workflow. Added a `concurrency` group that cancels superseded `pull_request` runs only. |
| Workflow events | `pull_request` types unchanged (all eight the guard subscribes to are listed); `pull_request_review` types are `submitted`, `edited`, `dismissed`; `merge_group` still has the single type `checks_requested`; `pull_request_target` warning retained. | No trigger changes needed. The guard deliberately omits `edited` reviews and never uses `pull_request_target`. |
| OIDC hardening | `id-token: write` grants only token fetch, not resource writes; Dependabot OIDC tokens carry `event_name: dynamic`, and trust policies should restrict `event_name`; examples moved to `actions/github-script@v8`. | The Action requests the token with audience `aport.io` inside its own code, so nothing changes in the workflow. Verifier-side restriction on `event_name` is a hosted policy concern; see the proposal above. |

No `set-output`, `save-state`, or Node runtime deprecation notices appear on these pages. The Action is a composite action that runs `node` from the runner image, so the Node 20 action-runtime retirement does not apply to it.
