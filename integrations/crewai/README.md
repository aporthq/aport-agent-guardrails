# CrewAI integration

APort supports CrewAI through two integration modes.

## Released CrewAI compatibility mode

This path works with released CrewAI today.

```bash
uvx --from aport-agent-guardrails aport setup --framework=crewai
pip install aport-agent-guardrails-crewai
aport-crewai setup
```

```python
from aport_guardrails_crewai import register_aport_guardrail

register_aport_guardrail()
crew.kickoff()
```

## Native provider mode

This path requires a CrewAI build with native guardrail provider support.

```bash
uvx --from aport-agent-guardrails aport setup --framework=crewai --integration-mode=native
uv add aport-agent-guardrails
```

```python
from crewai.hooks import enable_guardrail
from aport_guardrails.providers import OAPGuardrailProvider

enable_guardrail(
    OAPGuardrailProvider(
        framework="crewai",
        config_path="~/.aport/crewai/config.yaml",
    ),
    fail_closed=True,
)

crew.kickoff()
```

See [docs/frameworks/crewai.md](../../docs/frameworks/crewai.md) for the full setup details.
