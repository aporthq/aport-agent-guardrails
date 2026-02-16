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

**Tools Covered:**
- `tool.name.1`
- `tool.name.2`
- `tool.name.3`

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
