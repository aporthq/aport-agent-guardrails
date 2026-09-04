---
name: Policy Pack Proposal
about: Propose a new policy pack for community contribution
title: '[Policy Pack] '
labels: policy-pack, enhancement
assignees: ''
---

## Policy Pack Proposal

**Policy ID:** `[e.g., kubernetes.deploy.v1]`

**Description:**
[What does this policy enforce?]

**Upstream Target:**
[For public policy packs, implementation starts in https://github.com/aporthq/aport-policies. This repository wires accepted packs into framework adapters, setup, local smoke tests, and docs.]

**Tools Covered:**
- `tool.name.1`
- `tool.name.2`
- `tool.name.3`

**Verification Mode:**
- [ ] Hosted/API verifier only
- [ ] Local/offline evaluator parity required
- [ ] Both, with documented local limitations

**Trusted Evidence Source:**
- [What system proves the facts in the request context? Examples: GitHub OIDC + Action metadata, CI run result, runner-observed command exit code, APort decision ID, signed attestation, file hash.]

**Limits:**
- Max deployments per day: [number]
- Allowed namespaces: [list]
- Blocked resources: [list]

**Use Case:**
[Why is this needed?]

**Example Context:**
```json
{
  "repo": "example",
  "namespace": "production",
  "resources": ["deployment", "service"]
}
```

**References:**
- [Link to related issue or discussion]

**Security / Performance Notes:**
- [Expected latency impact, stateful checks, external lookups, SSRF considerations, maximum context size, and any failure mode that must fail closed.]
