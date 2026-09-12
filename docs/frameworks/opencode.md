# APort Agent Guardrail - opencode

opencode support is intentionally gated in this release.

The current opencode v2 plugin API exposes permission, shell, and tool hook surfaces that appear suitable for APort, but APort does not claim runtime enforcement until an installed-version smoke test verifies the exact hook payloads, deny semantics, and packaging path against a real opencode install.

Running the setup command exits with an explanation:

```bash
npx @aporthq/aport-agent-guardrails opencode
```

## Why this is gated

APort must fail closed for supported effectful actions. A paper integration based only on docs is not enough for that claim. Before enabling opencode, add:

| Gate | Required evidence |
|------|-------------------|
| Installed smoke test | Real opencode process loads the plugin and sends tool payloads. |
| Deny behavior | A blocked shell/tool action does not execute. |
| Warn behavior | Warn mode records the deny and permits execution with visible or documented warning output. |
| Data minimization | Hook payloads sent to APort exclude raw file contents and secrets. |
| Setup/reset | Installer and reset preserve unrelated opencode configuration. |

## Source reference

- opencode plugin docs: https://opencode.ai/v2/docs/build/plugins
