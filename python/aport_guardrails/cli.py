"""
Main CLI entry point: aport setup [--framework=langchain|crewai|...]

Full setup (passport wizard + config + framework integration) is done by the
Node CLI. This entry point prints the exact command to run for the chosen framework.
"""

import argparse
import asyncio


def main() -> None:
    parser = argparse.ArgumentParser(
        description="APort Agent Guardrails setup (prints next-step command; full wizard runs via Node CLI)"
    )
    parser.add_argument(
        "--framework",
        default="openclaw",
        choices=["openclaw", "cursor", "langchain", "crewai"],
        help="Target framework (n8n coming soon)",
    )
    parser.add_argument("command", nargs="?", default="setup", help="Command (setup, status)")
    args = parser.parse_args()
    asyncio.run(run(args))


async def run(args: argparse.Namespace) -> None:
    if args.command == "setup":
        _print_setup_next_steps(args.framework)
    elif args.command == "status":
        print("Status: run `npx @aporthq/agent-guardrails` or see docs for guardrail status commands.")
    else:
        print(f"Unknown command: {args.command}")


def _print_setup_next_steps(framework: str) -> None:
    """Print the concrete command(s) to run for full setup."""
    print(f"APort setup for framework: {framework}")
    print()
    if framework == "openclaw":
        print("Run the full wizard and plugin install:")
        print("  npx @aporthq/agent-guardrails openclaw")
        print("  (Optional: pass an agent_id for hosted passport: npx @aporthq/agent-guardrails openclaw <agent_id>)")
    elif framework == "cursor":
        print("Run the installer (writes ~/.cursor/hooks.json), then restart Cursor:")
        print("  npx @aporthq/agent-guardrails cursor")
    elif framework == "langchain":
        print("1. Run wizard and config:  npx @aporthq/agent-guardrails langchain")
        print("2. Install Python adapter: pip install aport-agent-guardrails-langchain")
        print("3. Framework setup:        aport-langchain setup")
    elif framework == "crewai":
        print("1. Run wizard and config:  npx @aporthq/agent-guardrails crewai")
        print("2. Install Python adapter: pip install aport-agent-guardrails-crewai")
        print("3. Framework setup:        aport-crewai setup")
    print()
    print("Docs: https://github.com/aporthq/aport-agent-guardrails/tree/main/docs")


if __name__ == "__main__":
    main()
