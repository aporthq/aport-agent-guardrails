"""CLI: aport-crewai setup — shared wizard flow, write config, next steps."""

import argparse
import sys

from aport_guardrails.core.cli_common import run_setup


def main() -> None:
    parser = argparse.ArgumentParser(
        description="APort Agent Guardrail for CrewAI — passport wizard and config"
    )
    parser.add_argument("--ci", action="store_true", help="Non-interactive (CI); skip wizard, write config only")
    parser.add_argument("--no-wizard", action="store_true", help="Do not run passport wizard; write config only")
    args = parser.parse_args()

    run_setup(
        "crewai",
        ci=args.ci,
        no_wizard=args.no_wizard,
        next_steps_lines=[
            "  Next steps (CrewAI):",
            "  ───────────────────",
            "  1. Register the agent guardrail before running your crew:",
            "",
            "     from aport_guardrails_crewai import register_aport_guardrail",
            "     register_aport_guardrail()",
            "     crew.kickoff()",
            "",
            "  2. Or use the decorator on your entry point:",
            "",
            "     from aport_guardrails_crewai import with_aport_guardrail",
            "     @with_aport_guardrail",
            "     def main():",
            "         crew.kickoff()",
            "     main()",
            "",
            "  3. See: https://github.com/aporthq/agent-guardrails/blob/main/docs/frameworks/crewai.md",
        ],
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
