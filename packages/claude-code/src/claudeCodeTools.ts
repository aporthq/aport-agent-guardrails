/**
 * Claude Code PreToolUse tool_name values (PascalCase) and their APort guardrail tool ids.
 * Runtime enforcement uses bin/aport-claude-code-hook.sh; this module documents the mapping
 * for programmatic consumers of @aporthq/aport-agent-guardrails-claude-code.
 *
 * @see https://code.claude.com/docs/en/tools-reference
 */

/** Guardrail evaluator tool id passed to aport-guardrail-bash.sh */
export type ClaudeCodeGuardrailToolId =
  | 'bash'
  | 'write'
  | 'websearch'
  | 'browser'
  | 'session.create'
  | 'mcp.tool';

/** Read-family tools: hook allows without calling the evaluator */
export const CLAUDE_CODE_READ_TOOLS = [
  'Read',
  'Glob',
  'Grep',
  'LSP',
  'ListMcpResourcesTool',
  'ReadMcpResourceTool',
  'ToolSearch',
  'WaitForMcpServers',
  'TaskGet',
  'TaskList',
  'TaskOutput',
  'CronList',
  'TodoRead',
  'AskUserQuestion',
] as const;

/**
 * Maps official Claude Code tool names to APort guardrail tool ids.
 * Tools omitted here are allow-by-default (read-family) or use MCP wildcard handling in the hook.
 */
export const CLAUDE_CODE_TO_GUARDRAIL_TOOL: Record<string, ClaudeCodeGuardrailToolId> = {
  Bash: 'bash',
  PowerShell: 'bash',
  Monitor: 'bash',
  Shell: 'bash',
  Write: 'write',
  Edit: 'write',
  MultiEdit: 'write',
  NotebookEdit: 'write',
  TodoWrite: 'write',
  ShareOnboardingGuide: 'write',
  WebSearch: 'websearch',
  WebFetch: 'websearch',
  Browser: 'browser',
  Agent: 'session.create',
  Task: 'session.create',
  TaskCreate: 'session.create',
  TaskUpdate: 'session.create',
  TaskStop: 'session.create',
  Skill: 'session.create',
  EnterWorktree: 'session.create',
  ExitWorktree: 'session.create',
  SendMessage: 'session.create',
  TeamCreate: 'session.create',
  TeamDelete: 'session.create',
  RemoteTrigger: 'session.create',
  CronCreate: 'session.create',
  CronDelete: 'session.create',
};
