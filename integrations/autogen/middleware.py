# Reference: implementation lives in python/autogen_adapter/hook.py
# APortGuardedTool (AsyncBaseTool wrapper) — run_json calls evaluator; raises GuardrailViolation on deny.
# wrap_agent_tools(agent) — patches agent.function_map for AutoGen 0.2.x; verify_sync per call.
