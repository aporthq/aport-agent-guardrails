# APort Agent Guardrails — CrewAI

APort supports CrewAI in two ways:

1. **Released CrewAI compatibility mode** via the existing `before_tool_call` adapter
2. **Native provider mode** for CrewAI builds that expose a native guardrail provider seam

The default bootstrap path targets released CrewAI so it works today without waiting
for upstream provider support.

## Option 1: Released CrewAI Compatibility Mode

This is the default mode.

Bootstrap config, passport, and local runtime with the Python-native CLI:

```bash
uvx --from aport-agent-guardrails aport setup --framework=crewai
```

Or use the Node bootstrap if you prefer:

```bash
npx -y @aporthq/aport-agent-guardrails crewai
# Optional mode flags:
#   --mode=api --api-url=https://api.aport.io
#   --mode=local
#   --enforcement=warn   # explicit report-only rollout; default is enforce/fail-closed
```

For CI or other non-interactive environments with the Python-native CLI:

```bash
APORT_CREWAI_CONFIG_DIR=.aport/crewai \
uvx --from aport-agent-guardrails aport setup \
  --framework=crewai \
  --ci
```

The equivalent Node bootstrap is:

```bash
APORT_CREWAI_CONFIG_DIR=.aport/crewai \
npx -y @aporthq/aport-agent-guardrails crewai \
  --output .aport/crewai/aport/passport.json \
  --non-interactive
```

Install the released CrewAI adapter:

```bash
pip install aport-agent-guardrails-crewai
aport-crewai setup
```

Register the hook before your crew runs:

```python
from aport_guardrails_crewai import register_aport_guardrail

register_aport_guardrail()
crew.kickoff()
```

This path works with released CrewAI because it plugs directly into CrewAI's existing
`before_tool_call` hook behavior.

## Option 2: Native Provider Mode

Use this only with a CrewAI build that exposes the native guardrail provider API.
Released CrewAI users should use compatibility mode above.

Bootstrap with native-mode instructions using the Python-native CLI:

```bash
uvx --from aport-agent-guardrails aport setup \
  --framework=crewai \
  --integration-mode=native
```

The equivalent Node bootstrap is:

```bash
npx -y @aporthq/aport-agent-guardrails crewai --integration-mode=native
```

Install the Python runtime package:

```bash
uv add aport-agent-guardrails
```

If your CrewAI build documents a native guardrail-provider hook, wire APort's
provider through that hook before your crew runs:

```python
from aport_guardrails.providers import OAPGuardrailProvider

provider = OAPGuardrailProvider(
    framework="crewai",
    config_path="~/.aport/crewai/config.yaml",
)
```

If you bootstrap into a project-local config directory, point `config_path` at that
file instead. Current released CrewAI users should use compatibility mode unless
their CrewAI version explicitly documents a native provider hook.

## What The Bootstrap Installs

Both modes write:

- `~/.aport/crewai/config.yaml`
- `~/.aport/crewai/aport/passport.json`
- `~/.aport/crewai/aport/runtime/...`

The compatibility and native modes share the same APort config and local runtime.
Only the CrewAI integration layer changes.

## How APort Fits

- **Compatibility mode:** APort adapts to CrewAI's existing hook surface.
- **Native mode:** CrewAI defines the seam, and APort plugs in as an external
  `OAPGuardrailProvider`.

That keeps CrewAI vendor-neutral while letting Open Agent Passport remain the
portable policy/passport format across frameworks.

## Configuration

The provider and adapter read the standard APort config:

- `mode: local` for the local shell evaluator
- `mode: api` for hosted evaluation
- `agent_id` for hosted passports
- `passport_path` for explicit local passport paths
- `guardrail_script` to override the local evaluator script path
- `enforcement_mode: enforce` to block by default, or `warn` for explicit report-only rollout
- `audit_log` to enable or disable audit logging

With the default bootstrap, you usually do not need to set `guardrail_script`
manually because the local runtime is installed under the framework config
directory.

## Validation

After bootstrap, you can smoke-test the local evaluator directly:

```bash
~/.aport/crewai/aport/runtime/bin/aport-guardrail.sh \
  system.command.execute \
  '{"command":"git status"}'
```

Exit code `0` means allow. Exit code `1` means deny.
