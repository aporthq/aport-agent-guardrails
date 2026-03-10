"""CLI: aport-autogen setup — shared wizard flow, write config, next steps."""

import argparse
import sys

from aport_guardrails.core.cli_common import run_setup


def main() -> None:
    parser = argparse.ArgumentParser(
        description="APort Agent Guardrail for AutoGen — passport wizard and config"
    )
    parser.add_argument(
        "--ci",
        action="store_true",
        help="Non-interactive (CI); skip wizard, write config only",
    )
    parser.add_argument(
        "--no-wizard",
        action="store_true",
        help="Do not run passport wizard; write config only",
    )
    args = parser.parse_args()

    run_setup(
        "autogen",
        ci=args.ci,
        no_wizard=args.no_wizard,
        next_steps_lines=[
            "  Next steps (AutoGen):",
            "  ─────────────────────",
            "  AutoGen 0.4.x (autogen-agentchat / autogen-core):",
            "",
            "  1. Wrap each tool with APortGuardedTool:",
            "",
            "     from aport_guardrails_autogen import APortGuardedTool",
            "     from autogen_core.tools import FunctionTool",
            "",
            "     tool = APortGuardedTool(FunctionTool(my_fn, description='...'))",
            "     agent = ToolAgent('MyAgent', tools=[tool])",
            "",
            "  2. Or decorate async tool functions directly:",
            "",
            "     from aport_guardrails_autogen import with_aport_guardrail",
            "",
            "     @with_aport_guardrail",
            "     async def send_email(recipient: str, body: str) -> str:",
            "         ...",
            "",
            "  AutoGen 0.2.x (pyautogen):",
            "",
            "  3. Patch agent.function_map before starting chat:",
            "",
            "     from aport_guardrails_autogen import wrap_agent_tools",
            "     wrap_agent_tools(assistant_agent)",
            "     user_proxy.initiate_chat(assistant_agent, ...)",
            "",
            "  See: https://github.com/aporthq/agent-guardrails/blob/main/docs/frameworks/autogen.md",
        ],
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
