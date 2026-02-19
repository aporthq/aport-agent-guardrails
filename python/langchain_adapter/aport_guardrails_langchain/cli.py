"""CLI: aport-langchain setup - shared wizard flow, write config, next steps."""

import argparse

from aport_guardrails.core.cli_common import run_setup


def main() -> None:
    parser = argparse.ArgumentParser(
        description="APort Agent Guardrail for LangChain - passport wizard and config"
    )
    parser.add_argument("--ci", action="store_true", help="Non-interactive (CI); skip wizard, write config only")
    parser.add_argument("--no-wizard", action="store_true", help="Do not run passport wizard; write config only")
    args = parser.parse_args()

    run_setup(
        "langchain",
        ci=args.ci,
        no_wizard=args.no_wizard,
        next_steps_lines=[
            "  Next steps (LangChain):",
            "  -----------------------",
            "  1. Add to your agent:",
            "",
            "     from aport_guardrails_langchain import APortCallback",
            "     agent = initialize_agent(..., callbacks=[APortCallback()])",
            "",
            "  2. See: https://github.com/aporthq/agent-guardrails/tree/main/docs/frameworks/langchain.md",
        ],
    )


if __name__ == "__main__":
    main()
