# GitHub Protection

APort protects GitHub work by verifying repository activity against an OAP passport and recording an OAP decision. The same hosted verifier used by Claude Code, Cursor, OpenClaw, and other agent runtimes evaluates GitHub policy packs and records decisions.

Use this when you want report-only evidence first, then blocking controls for higher-risk repository workflows such as protected-branch updates and automation run by coding agents. Release and package-publish policy checks are supported by the guardrail/verifier mapping, but the current Repository Guard Action is the `code.repository.merge.v1` slice.

## Recommended Path

Use hosted verification for GitHub Actions.

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
| Repository push | `git.push` -> `code.repository.merge.v1` | `repo.pr.create`, allowed repos, target branch, changed paths |

Explicit release publishing uses the same guardrail mapping, but is not part of the first Repository Guard Action workflow:

| Agent/runtime or direct guardrail surface | Tool/policy name | What APort checks |
| --- | --- | --- |
| Release publish | `release.publish` -> `code.release.publish.v1` | `repo.release`, allowed repos, semantic version, release files |

Shell commands such as `npm publish`, `pnpm publish`, and `gh release create` are evaluated as `system.command.execute.v1` when they arrive through Claude Code, Cursor, or another shell hook. Use an explicit `release.publish`/`git.release` tool name or hosted API verification when you want `code.release.publish.v1`.

## Minimal Workflow Shape

The canonical GitHub Repository Guard Action lives in the `agent-passport` repository under `integrations/github/actions/policy-verify/` and is published to `aporthq/policy-verify-action`.

Use the published action after the downstream action PR is released. Until then, APort dogfoods the local action path from `agent-passport`.

```yaml
permissions:
  contents: read
  id-token: write
  pull-requests: read

steps:
  - uses: actions/checkout@v4

  - name: APort repository guard
    uses: aporthq/policy-verify-action@v1
    with:
      mode: auto
```

Default `auto` mode requests GitHub OIDC, creates or reuses a hosted repository/workflow-scoped OAP passport, records a report-only decision through APort Verify, and falls back to labelled evidence-only reporting if hosted verification is unavailable. No APort API key is required for that free report-only path.

For blocking enforcement, switch to explicit hosted mode after the org has reviewed the first decisions and tuned passport limits:

```yaml
- name: APort repository guard
  uses: aporthq/policy-verify-action@v1
  with:
    mode: hosted
```

Explicit `hosted` mode fails the workflow when hosted verification cannot return a valid signed decision, returns `allow: false`, or reports a high/error structural finding.

## Passport Requirements

For repository workflows, the passport should include only the capabilities that match the workflow being protected.

Common capabilities:

- `repo.pr.create` for PR creation/update and push-style checks.
- `repo.merge` for merge checks.
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
