"""
Main CLI entry point: aport setup --framework=deerflow [--agent-id=ap_xxx]

Python-native setup — creates config dir, runs passport wizard, prints next steps.
No Node/npx dependency when run from source (uses bin/aport-create-passport.sh directly).
"""

import argparse
import sys

SUPPORTED_FRAMEWORKS = ["openclaw", "cursor", "langchain", "crewai", "deerflow", "n8n", "claude-code"]

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
        "     from aport_guardrails_langchain import APortCallback",
        "     agent = initialize_agent(..., callbacks=[APortCallback()])",
        "",
        "  See: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs",
    ],
    "crewai": [
        "  Next steps (CrewAI):",
        "  ───────────────────",
        "  1. Install the Python adapter:",
        "     pip install aport-agent-guardrails-crewai",
        "  2. Register the guardrail before running your crew:",
        "",
        "     from aport_guardrails_crewai import register_aport_guardrail",
        "     register_aport_guardrail()",
        "     crew.kickoff()",
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
    parser.add_argument("--ci", action="store_true", help="Non-interactive mode")
    parser.add_argument("--no-wizard", action="store_true", help="Skip passport wizard")
    args = parser.parse_args()

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
        run_setup(
            args.framework,
            ci=args.ci,
            no_wizard=args.no_wizard,
            agent_id=args.agent_id,
            next_steps_lines=_NEXT_STEPS.get(args.framework),
        )

    elif args.command == "status":
        print("Status: check your passport at ~/.aport/<framework>/aport/passport.json")
        print("  Or see docs: https://github.com/aporthq/aport-agent-guardrails")


if __name__ == "__main__":
    main()
