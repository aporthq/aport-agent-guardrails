#!/usr/bin/env node
/**
 * Weekly framework drift check.
 *
 * This is intentionally deterministic and dependency-free. It does not try to
 * infer support with an LLM. It checks our declared integration surfaces against
 * upstream primary sources and committed baselines, then writes Markdown/JSON
 * reports for scheduled GitHub Actions.
 */

import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const REPO_ROOT = resolve(new URL("..", import.meta.url).pathname, "..");
const DEFAULT_BASELINE_PATH = resolve(
  REPO_ROOT,
  "docs/framework-drift-baseline.json",
);
const DEFAULT_JSON_PATH = resolve(REPO_ROOT, "framework-drift-report.json");
const DEFAULT_MARKDOWN_PATH = resolve(REPO_ROOT, "framework-drift-report.md");

const WATCHLIST = Object.freeze([
  {
    id: "openclaw",
    name: "OpenClaw",
    support: "runtime plugin",
    ownerFiles: [
      "extensions/openclaw-aport/",
      "bin/frameworks/openclaw.sh",
      "docs/frameworks/openclaw.md",
    ],
    sources: [
      {
        id: "openclaw-hooks-doc",
        type: "http",
        label: "Plugin hooks doc",
        url: "https://raw.githubusercontent.com/openclaw/openclaw/main/docs/plugins/hooks.md",
        requiredMarkers: [
          'api.on("before_tool_call"',
          "before_tool_call",
          "matcher",
          "timeoutMs",
          "block: true",
        ],
      },
      {
        id: "openclaw-tags",
        type: "github-tags",
        label: "Latest repository tag",
        repo: "openclaw/openclaw",
      },
    ],
  },
  {
    id: "cursor",
    name: "Cursor",
    support: "command hooks",
    ownerFiles: [
      "bin/frameworks/cursor.sh",
      "bin/aport-cursor-hook.sh",
      "docs/frameworks/cursor.md",
    ],
    sources: [
      {
        id: "cursor-hooks-doc",
        type: "http",
        label: "Hooks reference",
        url: "https://prod.cursor.com/docs/hooks",
        requiredMarkers: [
          "preToolUse",
          "beforeShellExecution",
          "beforeMCPExecution",
          "beforeReadFile",
          "subagentStart",
          "failClosed",
        ],
      },
    ],
  },
  {
    id: "claude-code",
    name: "Claude Code",
    support: "PreToolUse hook",
    ownerFiles: [
      "bin/frameworks/claude-code.sh",
      "bin/aport-claude-code-hook.sh",
      "docs/frameworks/claude-code.md",
    ],
    sources: [
      {
        id: "claude-code-hooks-doc",
        type: "http",
        label: "Hooks reference",
        url: "https://code.claude.com/docs/en/hooks",
        requiredMarkers: [
          "PreToolUse",
          "hookSpecificOutput",
          "permissionDecision",
          "matcher",
          "Bash",
          "mcp__",
        ],
      },
    ],
  },
  {
    id: "langchain",
    name: "LangChain / LangGraph",
    support: "callback today; middleware watch",
    ownerFiles: [
      "python/langchain_adapter/",
      "packages/langchain/",
      "docs/frameworks/langchain.md",
    ],
    sources: [
      {
        id: "langchain-middleware-doc",
        type: "http",
        label: "Agent middleware overview",
        url: "https://docs.langchain.com/oss/python/langchain/middleware/overview",
        requiredMarkers: ["middleware", "create_agent", "tool"],
      },
      {
        id: "langchain-middleware-ref",
        type: "http",
        label: "Middleware API reference",
        url: "https://reference.langchain.com/python/langchain/agents/middleware",
        requiredMarkers: [
          "wrap_tool_call",
          "before_agent",
          "after_agent",
          "AgentMiddleware",
        ],
      },
      {
        id: "langchain-tags",
        type: "github-tags",
        label: "Latest repository tag",
        repo: "langchain-ai/langchain",
      },
    ],
  },
  {
    id: "crewai",
    name: "CrewAI",
    support: "released adapter; hook/event watch",
    ownerFiles: [
      "python/crewai_adapter/",
      "packages/crewai/",
      "docs/frameworks/crewai.md",
    ],
    sources: [
      {
        id: "crewai-events-doc",
        type: "http",
        label: "Event listener reference",
        url: "https://raw.githubusercontent.com/crewAIInc/crewAI/main/docs/v1.14.7/en/concepts/event-listener.mdx",
        requiredMarkers: [
          "ToolUsageStartedEvent",
          "ToolUsageFinishedEvent",
          "MCPToolExecutionStartedEvent",
          "MCPToolExecutionCompletedEvent",
        ],
      },
      {
        id: "crewai-tags",
        type: "github-tags",
        label: "Latest repository tag",
        repo: "crewAIInc/crewAI",
      },
    ],
  },
  {
    id: "deerflow",
    name: "DeerFlow",
    support: "provider wiring",
    ownerFiles: [
      "integrations/deerflow/",
      "docs/frameworks/deerflow.md",
      "python/aport_guardrails/providers/generic.py",
    ],
    sources: [
      {
        id: "deerflow-readme",
        type: "http",
        label: "Repository README",
        url: "https://raw.githubusercontent.com/bytedance/deer-flow/main/README.md",
        requiredMarkers: ["DeerFlow", "2.0", "Skills", "Sub-Agents"],
      },
      {
        id: "deerflow-tools-guide",
        type: "http",
        label: "Harness tools guide",
        url: "https://deerflow.tech/en/docs/harness/tools",
        requiredMarkers: ["Built-in tools", "MCP tools", "Skill tools"],
      },
      {
        id: "deerflow-tags",
        type: "github-tags",
        label: "Latest repository tag",
        repo: "bytedance/deer-flow",
      },
    ],
  },
  {
    id: "n8n",
    name: "n8n",
    support: "setup only; runtime node not shipped",
    ownerFiles: [
      "integrations/n8n/",
      "packages/n8n/",
      "docs/frameworks/n8n.md",
    ],
    sources: [
      {
        id: "n8n-tools-agent-doc",
        type: "http",
        label: "Tools AI Agent node",
        url: "https://raw.githubusercontent.com/n8n-io/n8n-docs/main/docs/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/tools-agent.md",
        requiredMarkers: [
          "Tools AI Agent node",
          "$fromAI()",
          "Human review for tool calls",
        ],
      },
      {
        id: "n8n-agents-doc",
        type: "http",
        label: "Build and manage agents",
        url: "https://raw.githubusercontent.com/n8n-io/n8n-docs/main/docs/build/build-and-manage-agents.md",
        requiredMarkers: [
          "Agents are in Preview",
          "Tools",
          "Sub-agents",
          "Schedules",
          "self-hosted",
        ],
      },
      {
        id: "n8n-tags",
        type: "github-tags",
        label: "Latest repository tag",
        repo: "n8n-io/n8n",
      },
    ],
  },
  {
    id: "github",
    name: "GitHub Repository Guard",
    support: "GitHub Action",
    ownerFiles: [
      "bin/github.sh",
      ".github/workflows/aport-repository-guard.yml",
      "docs/GITHUB_PROTECTION.md",
    ],
    sources: [
      {
        id: "github-workflow-syntax-doc",
        type: "http",
        label: "Workflow syntax reference",
        url: "https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax",
        requiredMarkers: ["on.schedule", "pull_request", "merge_group", "permissions"],
      },
      {
        id: "github-oidc-doc",
        type: "http",
        label: "OIDC hardening reference",
        url: "https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect",
        requiredMarkers: ["id-token: write", "OpenID Connect", "JWT"],
      },
    ],
  },
]);

function parseArgs(argv) {
  const args = {
    offline: false,
    failOnDrift: false,
    updateBaseline: false,
    baselinePath: DEFAULT_BASELINE_PATH,
    jsonPath: DEFAULT_JSON_PATH,
    markdownPath: DEFAULT_MARKDOWN_PATH,
    timeoutMs: 20_000,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--offline") args.offline = true;
    else if (arg === "--fail-on-drift") args.failOnDrift = true;
    else if (arg === "--update-baseline") args.updateBaseline = true;
    else if (arg === "--baseline") args.baselinePath = resolveRequiredValue(argv, ++i, arg);
    else if (arg === "--json") args.jsonPath = resolveRequiredValue(argv, ++i, arg);
    else if (arg === "--markdown") args.markdownPath = resolveRequiredValue(argv, ++i, arg);
    else if (arg === "--timeout-ms") args.timeoutMs = Number(resolveRequiredValue(argv, ++i, arg));
    else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (!Number.isFinite(args.timeoutMs) || args.timeoutMs < 1000) {
    throw new Error("--timeout-ms must be a number >= 1000");
  }

  return args;
}

function resolveRequiredValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return resolve(REPO_ROOT, value);
}

function printHelp() {
  console.log(`Usage: node scripts/framework-drift-check.mjs [options]

Options:
  --offline              Validate watchlist and write a no-network report.
  --update-baseline      Fetch upstream and write docs/framework-drift-baseline.json.
  --fail-on-drift        Exit 2 if drift is detected.
  --baseline <path>      Baseline JSON path.
  --json <path>          Report JSON output path.
  --markdown <path>      Report Markdown output path.
  --timeout-ms <ms>      Fetch timeout per source.
`);
}

async function readBaseline(path) {
  try {
    const raw = await readFile(path, "utf8");
    const parsed = JSON.parse(raw);
    return parsed.sources || {};
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 20_000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        "User-Agent": "APort-Framework-Drift-Watch/1.0",
        ...(options.headers || {}),
      },
    });
    const text = await response.text();
    return { response, text };
  } finally {
    clearTimeout(timeout);
  }
}

async function inspectHttpSource(source, baseline, args) {
  if (args.offline) {
    return {
      ...baseResult(source),
      status: "skipped",
      summary: "offline mode",
      drift: false,
    };
  }

  const { response, text } = await fetchWithTimeout(source.url, {}, args.timeoutMs);
  const sha256 = hash(text);
  const missingMarkers = (source.requiredMarkers || []).filter(
    (marker) => !text.includes(marker),
  );
  const baselineSha = baseline?.sha256;
  const drift = Boolean(baselineSha && baselineSha !== sha256) || missingMarkers.length > 0;
  return {
    ...baseResult(source),
    status: response.ok ? "ok" : "error",
    httpStatus: response.status,
    sha256,
    baselineSha256: baselineSha || null,
    drift,
    missingMarkers,
    summary: response.ok
      ? `${text.length.toLocaleString()} bytes, sha256 ${sha256.slice(0, 12)}`
      : `HTTP ${response.status}`,
  };
}

async function inspectGithubTagsSource(source, baseline, args) {
  if (args.offline) {
    return {
      ...baseResult(source),
      status: "skipped",
      summary: "offline mode",
      drift: false,
    };
  }

  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "";
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  const url = `https://api.github.com/repos/${source.repo}/tags?per_page=1`;
  const { response, text } = await fetchWithTimeout(url, { headers }, args.timeoutMs);
  let latestTag = null;
  if (response.ok) {
    const tags = JSON.parse(text);
    latestTag = Array.isArray(tags) && tags[0]?.name ? tags[0].name : null;
  }
  const baselineTag = baseline?.latestTag || null;
  const drift = Boolean(baselineTag && latestTag && latestTag !== baselineTag);
  return {
    ...baseResult(source),
    status: response.ok && latestTag ? "ok" : "error",
    httpStatus: response.status,
    latestTag,
    baselineLatestTag: baselineTag,
    drift,
    summary: latestTag ? `latest tag ${latestTag}` : `HTTP ${response.status}`,
  };
}

function baseResult(source) {
  return {
    id: source.id,
    label: source.label,
    type: source.type,
    url: source.url || (source.repo ? `https://github.com/${source.repo}` : null),
  };
}

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function inspectSource(source, baseline, args) {
  try {
    if (source.type === "http") return await inspectHttpSource(source, baseline, args);
    if (source.type === "github-tags") return await inspectGithubTagsSource(source, baseline, args);
    throw new Error(`Unsupported source type: ${source.type}`);
  } catch (error) {
    return {
      ...baseResult(source),
      status: "error",
      drift: true,
      summary: error.message,
      error: error.message,
    };
  }
}

async function buildReport(args) {
  const baseline = await readBaseline(args.baselinePath);
  const frameworks = [];

  for (const framework of WATCHLIST) {
    const sources = [];
    for (const source of framework.sources) {
      sources.push(await inspectSource(source, baseline[source.id], args));
    }
    frameworks.push({
      id: framework.id,
      name: framework.name,
      support: framework.support,
      ownerFiles: framework.ownerFiles,
      sources,
      drift: sources.some((source) => source.drift),
    });
  }

  const driftCount = frameworks.filter((framework) => framework.drift).length;
  const errorCount = frameworks.flatMap((framework) => framework.sources).filter(
    (source) => source.status === "error",
  ).length;

  return {
    generatedAt: new Date().toISOString(),
    offline: args.offline,
    summary: {
      frameworks: frameworks.length,
      driftCount,
      errorCount,
    },
    frameworks,
  };
}

function buildBaseline(report) {
  const sources = {};
  for (const framework of report.frameworks) {
    for (const source of framework.sources) {
      sources[source.id] = {
        framework: framework.id,
        type: source.type,
        label: source.label,
        url: source.url,
        sha256: source.sha256 || undefined,
        latestTag: source.latestTag || undefined,
        capturedAt: report.generatedAt,
      };
    }
  }
  return {
    generatedAt: report.generatedAt,
    note:
      "Generated by scripts/framework-drift-check.mjs --update-baseline. Update intentionally after reviewing upstream framework changes.",
    sources,
  };
}

function toMarkdown(report) {
  const rows = report.frameworks.map((framework) => {
    const status = framework.drift ? "Review" : "OK";
    const signals = framework.sources
      .map((source) => `${source.label}: ${source.summary}`)
      .join("<br>");
    return `| ${framework.name} | ${framework.support} | ${status} | ${signals} |`;
  });

  const details = report.frameworks
    .map((framework) => {
      const sourceLines = framework.sources
        .map((source) => {
          const markerNote = source.missingMarkers?.length
            ? ` Missing markers: ${source.missingMarkers.map((marker) => `\`${marker}\``).join(", ")}.`
            : "";
          return `- ${source.status.toUpperCase()} ${source.label}: ${source.url || ""} ${source.summary}.${markerNote}`;
        })
        .join("\n");
      const files = framework.ownerFiles.map((file) => `\`${file}\``).join(", ");
      return `### ${framework.name}\n\nOwned files: ${files}\n\n${sourceLines}`;
    })
    .join("\n\n");

  return `# APort Framework Drift Report

Generated: ${report.generatedAt}

This report checks APort's framework integrations against upstream primary sources. A "Review" status does not prove breakage; it means upstream changed, a required marker disappeared, or the source could not be reached.

| Framework | APort support | Status | Signals |
|---|---|---|---|
${rows.join("\n")}

## Details

${details}
`;
}

async function writeJson(path, value) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const report = await buildReport(args);
  await writeJson(args.jsonPath, report);
  await mkdir(dirname(args.markdownPath), { recursive: true });
  await writeFile(args.markdownPath, toMarkdown(report), "utf8");

  if (args.updateBaseline) {
    await writeJson(args.baselinePath, buildBaseline(report));
  }

  console.log(
    `Framework drift check complete: ${report.summary.driftCount} framework(s) need review, ${report.summary.errorCount} source error(s).`,
  );

  if (args.failOnDrift && report.summary.driftCount > 0) {
    process.exit(2);
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
