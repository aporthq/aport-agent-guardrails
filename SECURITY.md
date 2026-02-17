# Security Policy

## OpenClaw and agent frameworks: why pre-action authorization matters

OpenClaw and similar agent frameworks (IronClaw, PicoClaw, etc.) let AI agents run tools—shell commands, MCP servers, messaging, file access—often with third-party “skills” from the community. That creates a clear risk: **a malicious or compromised skill can exfiltrate data, run arbitrary commands, or escalate access without the user’s awareness.**

Public research and disclosures have made this concrete:

- **Cisco’s AI security team** documented [silent data exfiltration and prompt-injection attacks via third-party OpenClaw skills](https://blogs.cisco.com/ai/personal-ai-agents-like-openclaw-are-a-security-nightmare) (Jan 2026). Skills run with the same trust as the agent; the model may invoke them based on user or attacker-controlled prompts.
- **AuthMind** and others describe the [agentic AI supply-chain risk from malicious skills](https://www.authmind.com/post/openclaw-malicious-skills-agentic-ai-supply-chain) (Feb 2026).
- **FourWeekMBA** and **Bitsight** have amplified the [“OpenClaw security nightmare”](https://fourweekmba.com/openclaws-security-nightmare-the-risk-openai-just-inherited/) narrative (Feb 2026).
- **SecurityWeek** reported [CVE-2026-25253](https://www.securityweek.com/vulnerability-allows-hackers-to-hijack-openclaw-ai-assistant/): token exfiltration leading to full gateway compromise (Feb 2026).

APort Agent Guardrails does **not** fix every OpenClaw or gateway vulnerability (e.g. token exfiltration is a runtime/auth issue). It does provide a **pre-action authorization layer**: every tool call is evaluated against a passport and policy **before** it runs. Malicious or injected tool invocations are blocked at the hook; the tool never executes.

---

## Prompt injection and how APort mitigates it

### What is prompt injection in this context?

The agent decides which tools to call and with what arguments based on user input, system prompts, and context. An attacker can try to **inject instructions** (e.g. in a user message or in data the agent reads) so the agent calls a dangerous tool—for example `exec.run` with `rm -rf /` or a skill that sends data to an attacker-controlled server. If the only control is “the agent is instructed to call a guardrail,” the agent can be prompted to skip or bypass that step.

### How APort blocks it

- **Enforcement is in the platform, not the prompt.** The APort OpenClaw plugin runs in the `before_tool_call` hook. OpenClaw invokes the hook for **every** tool call before execution. The model cannot “choose” to skip it; there is no prompt or agent response that bypasses the hook.
- **Deterministic allow/deny.** Each tool call is evaluated against the passport (identity, capabilities, limits) and policy (e.g. `system.command.execute.v1`). If the request is not allowed—e.g. command not in allowlist, or matches a blocked pattern like `rm -rf`—the guardrail returns deny and the tool **never runs**.
- **No “trust the model” for safety.** Safety is not delegated to the model following instructions; it is enforced by the runtime. So prompt injection that tries to get the model to run a bad command or skip checks does not help—the hook still runs and can deny.

| Attack goal | Without APort | With APort (plugin) |
|-------------|----------------|----------------------|
| Run `rm -rf /` via injected prompt | Model may comply; no hard block | Hook evaluates command; blocked by policy (blocked pattern / allowlist) |
| Get agent to “skip guardrail” | Model can be prompted to ignore instructions | Hook is not skippable by the model |
| Use malicious skill to exfiltrate via `exec` | Skill runs; command executes | `exec` / `system.command.execute` checked; only allowlisted commands allowed |

---

## Cisco findings and how APort addresses them

Cisco’s blog ([“Personal AI agents like OpenClaw are a security nightmare”](https://blogs.cisco.com/ai/personal-ai-agents-like-openclaw-are-a-security-nightmare)) highlights risks from third-party OpenClaw skills and agent behavior. Below is how APort Agent Guardrails maps to those concerns.

| Cisco / reported risk | What APort does |
|------------------------|-----------------|
| **Silent data exfiltration** (skill or agent sends data out without user awareness) | Tool calls that would send data (e.g. `messaging.message.send`, or custom tools if mapped) are subject to the same pre-action check. Passport and policy can restrict which channels/servers/commands are allowed; unauthorized sends are denied before execution. |
| **Malicious or compromised third-party skills** (skill runs dangerous commands or calls) | Every tool invocation—whether from a “skill” or the core agent—goes through the same `before_tool_call` hook. A malicious skill cannot bypass the guardrail; its tool calls are evaluated against the passport and policy (allowlists, blocked patterns, rate limits). |
| **Prompt-injection to trigger dangerous tool use** | As above: the model cannot skip the hook. Injected prompts that try to force a dangerous tool call still hit the guardrail; the call is allowed or denied by policy, not by the model. |
| **Lack of identity/authorization for agents** | Passports (OAP v1.0) provide identity and scoped capabilities/limits. Enforcement is per tool call, so only authorized actions run. |

APort does **not** replace secure development of OpenClaw itself, safe skill curation, or mitigation of issues like CVE-2026-25253 (token/gateway compromise). It adds a **pre-action authorization layer** so that even when the agent or a skill tries to run a tool, the platform can block it before it executes.

---

## Other attack vectors and APort’s scope

| Vector | Description | APort’s role |
|--------|-------------|--------------|
| **Token exfiltration / gateway takeover** (e.g. [CVE-2026-25253](https://www.securityweek.com/vulnerability-allows-hackers-to-hijack-openclaw-ai-assistant/)) | Attacker steals tokens or hijacks the gateway. | Out of scope: this is runtime/auth security of the OpenClaw stack. APort does not store or handle gateway tokens. Use upstream patches and secure deployment. |
| **Malicious skill installed by user** | User adds a skill that is designed to abuse tools. | In scope: every tool call from that skill is still subject to the guardrail. Passport allowlists and blocked patterns limit what can run (e.g. which commands, which MCP tools). |
| **Supply-chain compromise (skill or dependency)** | A trusted skill or dependency is compromised and tries to run bad commands. | In scope: same as above; tool calls are checked before execution. |
| **PII or secrets in context** | Agent or skill has access to sensitive data in prompts or context. | Partially in scope: APort can restrict which tools run (e.g. no `data.export` or messaging to arbitrary endpoints). It does not redact or encrypt context; that requires other controls. |

---

## Security features of this project

- **Fail-closed by default**: If the guardrail errors or the passport is invalid, the tool is blocked.
- **Deterministic enforcement**: Policy runs in the platform hook; the AI cannot bypass it.
- **Tamper-evident audit trail**: Decisions can be logged locally or via APort API (signed receipts in API mode).
- **Local-first option**: You can run the guardrail entirely offline (bash evaluator) with no network dependency.
- **Explicit allowlists and blocked patterns**: e.g. `system.command.execute` uses allowlists and 40+ blocked patterns (`rm -rf`, `sudo`, injection patterns) so only intended commands can run.

---

## Supported versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| 0.1.x   | :white_check_mark: |

---

## Reporting a vulnerability

**DO NOT** open public GitHub issues for security vulnerabilities.

Please report security vulnerabilities to: **uchi@aport.io**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We aim to respond within 48 hours and provide a fix within 7 days for critical issues.
