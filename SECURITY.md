# Security Policy

APort Agent Guardrails provides pre-action authorization for AI agents and
agent-operated automation. It checks an action against an Open Agent Passport
(OAP) passport and policy before the action runs.

The current priority surfaces are:

- GitHub Repository Guard through `aporthq/policy-verify-action@v1`
- Claude Code and Cursor local/hosted tool hooks
- Codex CLI, Gemini CLI, and Goose beta command-hook harnesses
- OpenClaw plugin support
- LangChain, CrewAI, DeerFlow, and other framework adapters

## What APort Protects

APort is designed to reduce damage from prompt injection, compromised agent
instructions, risky MCP tools, and automation that tries to perform actions
outside its authorized passport.

In scope:

- Shell command execution, including blocked command patterns and allowlists
- File reads and writes, including path restrictions
- MCP tool calls and server/tool allowlists
- Web fetch and network-like tool calls exposed by supported harnesses
- Agent/session spawning where the framework exposes a pre-action hook
- GitHub pull request, merge, release, and push evidence evaluated by APort
- Hosted signed decisions and local/offline decisions depending on mode

Out of scope:

- Operating system compromise, root compromise, or direct process injection
- A user or attacker with write access to disable framework hook config
- Framework bugs that skip documented hook execution
- Secret storage, TLS, DNS, package registry, or kernel sandbox security
- Post-action cleanup after a tool already executed

APort operates at the application/harness layer. It is most effective when the
host framework reliably invokes its pre-action hook and branch protection or
deployment controls require the guard check before sensitive operations.

## Enforcement Modes

Default mode is fail-closed.

- `enforce`: Denied decisions block the action.
- `warn`: Completed policy denials are reported but the action may continue.
- `local`: Uses a local passport and local evaluator.
- `api`/hosted: Uses the APort API, hosted passports, and signed decisions.

Warn mode is intentionally narrow. It may downgrade a completed policy denial
for rollout/audit, but these conditions still fail closed:

- malformed or missing hook input
- missing required tool name, command, or file path
- unsupported multi-target patch writes or glob-expanded reads
- unmapped effectful tools
- missing dependencies such as `jq`
- invalid, missing, suspended, or revoked passports
- evaluator crashes, API integrity failures, or corrupted mode files

This keeps "report-only" useful for adoption without turning schema drift or
runtime failures into bypasses.

## GitHub Repository Guard

GitHub protection is the fastest path to secure AI-assisted repository changes:

```yaml
- uses: aporthq/policy-verify-action@v1
  with:
    mode: auto
```

`mode: auto` uses GitHub OIDC to create or reuse a repository-scoped hosted OAP
passport without long-lived secrets. For enterprise or internal repositories,
configure `agent-id` and `api-key` with GitHub Actions variables/secrets so
decisions persist under a managed passport.

Repository guard findings include:

- workflow permission escalation
- `pull_request_target` introduction
- protected path changes
- suspicious obfuscated or remote-execution content
- incomplete or truncated GitHub evidence

Workflow and `.aport` policy changes are control-plane changes. Treat them as
high risk and require maintainer review or branch protection. Do not allow a PR
to weaken the guard in the same change that modifies sensitive files.

Repositories that dogfood APort may need to merge reviewed guard workflow or
policy changes. Use an explicit maintainer-applied break-glass label bound to
the reviewed head commit, such as `aport-control-plane-approved-4dfbf5cdc1a2`.
The action should still run and write its denial/audit output; the label only
prevents that exact reviewed control-plane change from blocking its own rollout.
A later push changes the head SHA and invalidates the override.

## Harness Security Rules

For Claude Code, Cursor, Codex CLI, Gemini CLI, Goose, and OpenClaw, the hook
must evaluate the action the host is about to execute. The implementation
therefore follows these rules:

- Do not trust prompts or model output as safety controls.
- Do not forward raw prompt text, file content, or MCP payload bodies unless a
  policy explicitly requires it.
- Fail closed when the hook cannot map a tool to a policy.
- Fail closed when one hook payload may affect multiple file targets and the
  local evaluator cannot authorize each target independently.
- Deny loopback, link-local, private, and cloud-metadata IP literals before
  applying local web allowlists.
- Prefer hosted mode for production because decisions are signed and passports
  can be suspended centrally.
- Keep local mode simple for development, offline use, and free report-only
  experimentation.

## Local vs Hosted Verification

Hosted mode:

- Full APort/OAP policy evaluation
- Hosted passport lookup and global suspend
- Ed25519-signed decision receipts
- Decision history in the APort dashboard when authenticated
- Requires network access to `api.aport.io`

Local mode:

- Offline and private
- Fast local checks
- No hosted decision persistence
- Limited policy surface compared with the hosted verifier
- Trusts local filesystem integrity for passport/config files

## Supply Chain

Install from the published npm/PyPI packages or the GitHub Marketplace action.
For production use, pin versions where appropriate and monitor release notes.
This repository includes tests for command hooks, framework setup, Python
adapters, npm packages, and release packaging.

## Reporting a Vulnerability

Do not open public GitHub issues for security vulnerabilities.

Report vulnerabilities to: **security@aport.io**

Include:

- affected package, framework, or action
- exact version or commit
- reproduction steps
- expected versus actual behavior
- impact and any suggested mitigation

We aim to acknowledge reports within 48 hours and prioritize critical issues
for a fix within 7 days.
