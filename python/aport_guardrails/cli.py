"""
Main CLI entry point: aport setup --framework=deerflow [--agent-id=ap_xxx]

Python-native setup — creates config dir, runs the bundled passport wizard, and
prints next steps. Installed wheels carry the same bootstrap runtime.
"""

import argparse
import sys

SUPPORTED_FRAMEWORKS = ["openclaw", "cursor", "langchain", "crewai", "deerflow", "n8n", "claude-code"]


def _crewai_next_steps(integration_mode: str) -> list[str]:
    if integration_mode == "native":
        return [
            "  Next steps (CrewAI native provider mode):",
            "  ───────────────────────────────────────",
            "  Requires a CrewAI build with native guardrail provider support.",
            "",
            "  1. Install the Python runtime package:",
            "     uv add aport-agent-guardrails",
            "  2. If your CrewAI build documents a native guardrail-provider hook,",
            "     wire APort's provider through that hook before running your crew:",
            "",
            "     from aport_guardrails.providers import OAPGuardrailProvider",
            "",
            '     provider = OAPGuardrailProvider(framework="crewai", config_path="$config_dir/config.yaml")',
            "",
            "  Current released CrewAI users should use the compatibility hook adapter:",
            "     pip install aport-agent-guardrails-crewai",
            "     aport-crewai setup",
            "",
            "  Released CrewAI compatibility mode:",
            "     rerun without --integration-mode=native",
            "",
            "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
        ]

    return [
        "  Next steps (CrewAI):",
        "  ───────────────────",
        "  Default mode targets released CrewAI without native guardrail provider support.",
        "",
        "  1. Install the CrewAI adapter package:",
        "     pip install aport-agent-guardrails-crewai",
        "     aport-crewai setup",
        "  2. Register the guardrail before running your crew:",
        "",
        "     from aport_guardrails_crewai import register_aport_guardrail",
        "     register_aport_guardrail()",
        "     crew.kickoff()",
        "",
        "  Optional native mode:",
        "     rerun with --integration-mode=native",
        "",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ]

# Framework-specific next steps (data, not code)
_NEXT_STEPS = {
    "deerflow": [
        "  Next steps (DeerFlow):",
        "  ──────────────────────",
        "  1. Install the guardrails package:",
        "     uv add aport-agent-guardrails",
        "",
        "  2. Add to your DeerFlow config.yaml:",
        "",
        "     guardrails:",
        "       enabled: true",
        "       passport: $config_dir/aport/passport.json",
        "       provider:",
        "         use: aport_guardrails.providers.generic:OAPGuardrailProvider",
        "",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "langchain": [
        "  Next steps (LangChain):",
        "  ───────────────────────",
        "  1. Install the Python adapter:",
        "     pip install aport-agent-guardrails-langchain",
        "  2. Add to your agent:",
        "",
        "     from langchain.agents import create_agent",
        "     from aport_guardrails_langchain import APortCallback",
        "",
        "     agent = create_agent(model=model, tools=tools)",
        '     result = await agent.ainvoke({"messages": [{"role": "user", "content": "run the task"}]}, config={"callbacks": [APortCallback()]})',
        "",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "n8n": [
        "  Next steps (n8n):",
        "  ────────────────",
        "  n8n custom node coming soon. Config has been written.",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "openclaw": [
        "  Next steps (OpenClaw):",
        "  ──────────────────────",
        "  Run the full wizard: npx @aporthq/aport-agent-guardrails openclaw",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "cursor": [
        "  Next steps (Cursor):",
        "  ─────────────────────",
        "  Cursor hooks require the Node installer:",
        "  npx @aporthq/aport-agent-guardrails cursor",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "claude-code": [
        "  Next steps (Claude Code):",
        "  ──────────────────────────",
        "  Claude Code hooks require the Node installer:",
        "  npx @aporthq/aport-agent-guardrails claude-code",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
}


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="aport",
        description="APort Agent Guardrails — setup and manage OAP passports",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="setup",
        choices=["setup", "status"],
        help="Command to run (default: setup)",
    )
    parser.add_argument(
        "--framework", "-f",
        default=None,
        choices=SUPPORTED_FRAMEWORKS,
        help="Target framework",
    )
    parser.add_argument(
        "--agent-id",
        default=None,
        help="Hosted passport agent ID (e.g. ap_fa2f6d53...)",
    )
    parser.add_argument(
        "--integration-mode",
        choices=["compat", "native"],
        default="compat",
        help="CrewAI only: choose released compatibility mode or native provider mode",
    )
    parser.add_argument("--ci", action="store_true", help="Non-interactive mode")
    parser.add_argument("--no-wizard", action="store_true", help="Skip passport wizard")
    args = parser.parse_args()

    if args.framework != "crewai" and args.integration_mode != "compat":
        parser.error("--integration-mode is only supported with --framework=crewai")

    if args.command == "setup":
        if not args.framework:
            print("Usage: aport setup --framework <name>")
            print(f"  Supported: {', '.join(SUPPORTED_FRAMEWORKS)}")
            sys.exit(1)

        # Cursor and claude-code require Node hooks — delegate to npx
        if args.framework in ("cursor", "claude-code"):
            print(f"  {args.framework} requires the Node installer for hook setup:")
            print(f"  npx @aporthq/aport-agent-guardrails {args.framework}")
            sys.exit(0)

        from aport_guardrails.core.cli_common import run_setup
        next_steps = _crewai_next_steps(args.integration_mode) if args.framework == "crewai" else _NEXT_STEPS.get(args.framework)
        run_setup(
            args.framework,
            ci=args.ci,
            no_wizard=args.no_wizard,
            agent_id=args.agent_id,
            next_steps_lines=next_steps,
            wizard_args=[f"--integration-mode={args.integration_mode}"] if args.framework == "crewai" else None,
        )

    elif args.command == "status":
        print("Status: check your passport at ~/.aport/<framework>/aport/passport.json")
        print("  Or see docs: https://github.com/aporthq/aport-agent-guardrails")


if __name__ == "__main__":
    main()
