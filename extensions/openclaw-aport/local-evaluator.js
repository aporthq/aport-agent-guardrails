import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { canonicalize } from "./decision.js";

const REQUIRED_CAPABILITIES = {
  "system.command.execute.v1": ["system.command.execute"],
  "code.repository.merge.v1": [],
  "messaging.message.send.v1": ["messaging.send"],
  "data.file.read.v1": ["data.file.read"],
  "data.file.write.v1": ["data.file.write"],
  "web.fetch.v1": ["web.fetch"],
  "web.browser.v1": ["web.browser"],
  "mcp.tool.execute.v1": ["mcp.tool.execute"],
  "agent.session.create.v1": ["agent.session.create"],
  "agent.tool.register.v1": ["agent.tool.register"],
  "code.release.publish.v1": ["repo.release"],
  "finance.payment.refund.v1": ["finance.payment.refund"],
  "finance.payment.charge.v1": ["payments.charge"],
  "data.export.create.v1": ["data.export"],
};

function validateCommandString(command) {
  if (command.includes("`")) return false;
  if (/\$\([^)]*\b(rm|dd|mkfs|curl|wget|chmod|chown|sudo|kill|nc|netcat)\b/i.test(command)) {
    return false;
  }
  if (/[\u0000-\u0008\u000e-\u001f]/.test(command)) return false;
  return true;
}

function safePatternMatch(string, pattern) {
  if (!pattern) return false;
  if (pattern.includes(" ")) return String(string).toLowerCase().includes(String(pattern).toLowerCase());
  const escaped = String(pattern).replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  return new RegExp(`(^|[^\\w])${escaped}([^\\w]|$)`, "i").test(String(string));
}

function safePrefixMatch(string, prefix) {
  if (prefix === "*") return true;
  return String(string).startsWith(String(prefix));
}

function matchesSimpleGlob(value, pattern) {
  if (pattern === "*") return true;
  const escaped = String(pattern)
    .replace(/[\\^$.*+?()[\]{}|]/g, "\\$&")
    .replace(/\\\*/g, ".*")
    .replace(/\\\?/g, ".");
  return new RegExp(`^${escaped}$`).test(String(value));
}

function getCapabilityIds(passport) {
  const capabilities = Array.isArray(passport.capabilities) ? passport.capabilities : [];
  return capabilities
    .map((entry) => {
      if (typeof entry === "string") return entry;
      if (entry && typeof entry === "object" && typeof entry.id === "string") return entry.id;
      return null;
    })
    .filter(Boolean);
}

function hasCapability(passport, capability) {
  const granted = new Set(getCapabilityIds(passport));
  if (granted.has(capability)) return true;
  if (capability === "repo.release" && granted.has("release")) return true;
  if (capability === "messaging.send" && granted.has("messaging.message.send")) return true;
  return false;
}

function hasRequiredCapabilities(passport, policyId) {
  const required = REQUIRED_CAPABILITIES[policyId] || [];
  if (required.length === 0) return true;
  return required.every((capability) => hasCapability(passport, capability));
}

function getLimits(passport, policyId) {
  const limits = passport && typeof passport.limits === "object" ? passport.limits : {};
  const policyBase = policyId.replace(/\.v\d+$/, "");
  if (policyId === "messaging.message.send.v1") {
    return limits["messaging.message.send"] || {
      msgs_per_min: limits.msgs_per_min,
      msgs_per_day: limits.msgs_per_day,
      allowed_recipients: limits.allowed_recipients,
      approval_required: limits.approval_required,
    };
  }
  if (policyId === "code.release.publish.v1") {
    return limits["code.release.publish"] || {
      allowed_repos: limits.allowed_repos,
      allowed_extensions: limits.allowed_extensions,
    };
  }
  if (policyId === "mcp.tool.execute.v1") {
    return limits["mcp.tool.execute"] || {
      allowed_servers: limits.allowed_servers,
      allowed_tools: limits.allowed_tools,
      allowed_tool_prefixes: limits.allowed_tool_prefixes,
    };
  }
  return limits[policyBase] || {};
}

function computePassportDigest(passportRaw) {
  return `sha256:${createHash("sha256").update(canonicalize(JSON.parse(passportRaw)), "utf8").digest("hex")}`;
}

function buildDecision({ allow, policyId, passport, passportRaw, code, message, dataDir }) {
  const now = new Date();
  const issuedAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + 60 * 60 * 1000).toISOString();
  const decisionId = randomUUID();
  const passportId = passport.passport_id || passport.agent_id || "unknown";
  const agentId = passport.agent_id || passport.passport_id || "unknown";
  const ownerId = passport.owner_id || "unknown";
  const reasons = allow
    ? [{ code: "oap.allowed", message: "All policy checks passed" }]
    : [{ code, message }];

  const decisionsDir = join(dataDir, "decisions");
  const chainStatePath = join(decisionsDir, ".chain-state.json");
  let prevDecisionId = null;
  let prevContentHash = null;
  try {
    if (existsSync(chainStatePath)) {
      const chainState = JSON.parse(readFileSync(chainStatePath, "utf8"));
      prevDecisionId = chainState.last_decision_id || null;
      prevContentHash = chainState.last_content_hash || null;
    }
  } catch {
    prevDecisionId = null;
    prevContentHash = null;
  }

  const baseDecision = {
    decision_id: decisionId,
    policy_id: policyId,
    passport_id: passportId,
    agent_id: agentId,
    owner_id: ownerId,
    assurance_level: passport.assurance_level || "L0",
    allow,
    reasons,
    issued_at: issuedAt,
    created_at: issuedAt,
    expires_at: expiresAt,
    expires_in: 3600,
    passport_digest: computePassportDigest(passportRaw),
    signature: "local-unsigned",
    kid: "oap:local:dev-key",
    verification_mode: "local",
    prev_decision_id: prevDecisionId,
    prev_content_hash: prevContentHash,
  };
  const contentHash = `sha256:${createHash("sha256").update(canonicalize(baseDecision), "utf8").digest("hex")}`;
  const decision = { ...baseDecision, content_hash: contentHash };

  try {
    mkdirSync(decisionsDir, { recursive: true });
    writeFileSync(
      chainStatePath,
      JSON.stringify({
        last_decision_id: decisionId,
        last_content_hash: contentHash,
      }),
      "utf8",
    );
  } catch {
    // Best-effort only.
  }

  return decision;
}

function allowByList(value, list, matcher) {
  if (!Array.isArray(list) || list.length === 0) return true;
  return list.some((entry) => matcher(value, entry));
}

function toStringArray(value) {
  if (Array.isArray(value)) return value.map((entry) => String(entry)).filter(Boolean);
  if (typeof value === "string" && value) return [value];
  return [];
}

function changedFilePaths(context) {
  return [
    ...toStringArray(context.files_changed),
    ...toStringArray(context.files),
    ...toStringArray(context.file_paths),
    ...toStringArray(context.paths),
  ];
}

function pathAllowedByPatterns(filePath, patterns) {
  if (!Array.isArray(patterns) || patterns.length === 0) return true;
  return patterns.some((pattern) => pattern === "*" || matchesSimpleGlob(filePath, pattern));
}

function isDefaultSensitiveReadPath(filePath) {
  const value = String(filePath).toLowerCase();
  return /(^|\/)\.env/.test(value) ||
    /(^|\/)\.aws\//.test(value) ||
    /(^|\/)\.ssh\//.test(value) ||
    value.includes("credentials") ||
    /(^|\/)id_(rsa|dsa|ecdsa|ed25519)/.test(value) ||
    /\.(pem|key)$/.test(value) ||
    value.includes("password") ||
    /(^|\/)\.gnupg\//.test(value) ||
    /(^|\/)\.kube\//.test(value);
}

function assuranceRank(level) {
  const ranks = { L0: 0, L1: 1, L2: 2, L3: 3, L4: 4, L5: 5 };
  return ranks[level] ?? 0;
}

function meetsMinimumAssurance(actual, required) {
  return assuranceRank(actual || "L0") >= assuranceRank(required);
}

function repositoryAction(context, toolName) {
  const raw = String(
    toolName ??
      context.tool_name ??
      context.toolName ??
      context.tool ??
      context.action ??
      context.operation ??
      context.event_type ??
      "",
  ).toLowerCase();
  if (raw.includes("merge")) return "repo.merge";
  if (raw.includes("push")) return "repo.push";
  if (raw.includes("create") || raw.includes("open") || raw.includes("update")) return "repo.pr.create";
  return "repo.pr.create";
}

function requiredRepoCapability(context, toolName) {
  return repositoryAction(context, toolName) === "repo.merge" ? "repo.merge" : "repo.pr.create";
}

function isSensitiveReleaseFile(filePath) {
  const value = String(filePath).toLowerCase();
  return /(^|\/)\.env(\.|$)/.test(value) ||
    /(^|\/)\.aws\//.test(value) ||
    /(^|\/)\.ssh\//.test(value) ||
    value.includes("credentials") ||
    /(^|\/)id_(rsa|dsa|ecdsa|ed25519)/.test(value) ||
    /\.(pem|key)$/.test(value);
}

function releaseFileAllowed(filePath, allowedPatterns) {
  if (!Array.isArray(allowedPatterns) || allowedPatterns.length === 0) return true;
  const file = String(filePath);
  const lower = file.toLowerCase();
  return allowedPatterns.some((pattern) => {
    const normalized = String(pattern).toLowerCase();
    if (normalized === "*") return true;
    if (normalized.startsWith(".")) return lower.endsWith(normalized);
    return matchesSimpleGlob(file, pattern);
  });
}

function normalizeMcpServer(value) {
  const server = String(value || "").trim();
  return server.startsWith("mcp://") ? server.slice("mcp://".length) : server;
}

function mcpServerAllowed(server, allowedServers) {
  if (!Array.isArray(allowedServers) || allowedServers.length === 0) return true;
  const normalized = normalizeMcpServer(server);
  return allowedServers.some((entry) => {
    if (entry === "*") return true;
    const allowed = normalizeMcpServer(entry);
    return normalized === allowed || matchesSimpleGlob(normalized, allowed);
  });
}

function mcpToolAllowed(tool, limits) {
  const value = String(tool || "");
  const allowedTools = Array.isArray(limits.allowed_tools) ? limits.allowed_tools : [];
  const allowedPrefixes = Array.isArray(limits.allowed_tool_prefixes) ? limits.allowed_tool_prefixes : [];
  if (allowedTools.length === 0 && allowedPrefixes.length === 0) return true;
  if (allowedTools.some((entry) => entry === "*" || matchesSimpleGlob(value, entry))) return true;
  return allowedPrefixes.some((entry) => entry === "*" || value.startsWith(String(entry)));
}

function hasRestrictiveList(value) {
  return Array.isArray(value) && value.length > 0 && !value.includes("*");
}

function hasRestrictiveMcpToolLimits(limits) {
  return hasRestrictiveList(limits.allowed_tools) || hasRestrictiveList(limits.allowed_tool_prefixes);
}

function makeDeny(baseParams, code, message) {
  return buildDecision({ allow: false, code, message, ...baseParams });
}

function makeAllow(baseParams) {
  return buildDecision({
    allow: true,
    code: "oap.allowed",
    message: "All policy checks passed",
    ...baseParams,
  });
}

export function evaluateLocalDecision({ policyName, toolName, context, passportFile }) {
  const dataDir = dirname(passportFile || ".");
  const baseParams = {
    policyId: policyName || "unknown",
    passport: {},
    passportRaw: "{}",
    dataDir,
  };

  if (!passportFile || !existsSync(passportFile)) {
    return makeDeny(baseParams, "oap.passport_not_found", `Passport file not found at ${passportFile}`);
  }

  let passportRaw = "{}";
  let passport = {};
  try {
    passportRaw = readFileSync(passportFile, "utf8");
    passport = JSON.parse(passportRaw);
  } catch {
    return makeDeny(baseParams, "oap.passport_invalid", "Passport file contains invalid JSON");
  }

  const params = { ...baseParams, passport, passportRaw };

  if (passport.status !== "active") {
    return makeDeny(params, "oap.passport_suspended", `Passport status is '${passport.status}', not 'active'. Agent suspended.`);
  }

  if (passport.spec_version !== "oap/1.0") {
    return makeDeny(params, "oap.passport_version_mismatch", `Passport spec version is '${passport.spec_version}', expected 'oap/1.0'`);
  }

  if (!hasRequiredCapabilities(passport, policyName)) {
    return makeDeny(params, "oap.unknown_capability", `Passport does not have required capability for policy '${policyName}'`);
  }

  const limits = getLimits(passport, policyName);

  if (policyName === "code.repository.merge.v1") {
    const requiredCapability = requiredRepoCapability(context, toolName);
    if (!hasCapability(passport, requiredCapability)) {
      return makeDeny(params, "oap.unknown_capability", `Missing required capability: ${requiredCapability}`);
    }

    const maxSizeKb = Number(limits.max_pr_size_kb ?? 500);
    const linesAdded = Number(context.lines_added ?? context.additions ?? 0);
    const linesRemoved = Number(context.lines_removed ?? context.deletions ?? 0);
    const totalLines =
      (Number.isFinite(linesAdded) ? linesAdded : 0) +
      (Number.isFinite(linesRemoved) ? linesRemoved : 0);
    if (totalLines > 0) {
      const estimatedSizeKb = Math.ceil(totalLines / 10);
      if (estimatedSizeKb > maxSizeKb) {
        return makeDeny(params, "oap.limit_exceeded", `PR size exceeds limit: ${estimatedSizeKb}KB > ${maxSizeKb}KB (${totalLines} lines)`);
      }
    } else {
      const filesChanged = Array.isArray(context.files_changed)
        ? context.files_changed.length
        : Number(context.files_changed ?? context.files ?? 0);
      if (Number.isFinite(filesChanged) && filesChanged > maxSizeKb) {
        return makeDeny(params, "oap.limit_exceeded", `PR file count ${filesChanged} exceeds fallback limit of ${maxSizeKb}`);
      }
    }

    const repo = String(context.repo ?? context.repository ?? "");
    if (!allowByList(repo, limits.allowed_repos, matchesSimpleGlob)) {
      return makeDeny(params, "oap.repo_not_allowed", `Repository '${repo}' is not in allowed list`);
    }

    const branch = repositoryAction(context, toolName) === "repo.push"
      ? String(context.branch ?? "")
      : String(context.base_branch ?? context.branch ?? "");
    if (!allowByList(branch, limits.allowed_base_branches, matchesSimpleGlob)) {
      return makeDeny(params, "oap.branch_not_allowed", `Branch '${branch}' is not in allowed list`);
    }

    const allowedPaths = Array.isArray(limits.allowed_paths) ? limits.allowed_paths : [];
    if (allowedPaths.length > 0) {
      const blockedPath = changedFilePaths(context).find((filePath) => !pathAllowedByPatterns(filePath, allowedPaths));
      if (blockedPath) {
        return makeDeny(params, "oap.path_not_allowed", `File path '${blockedPath}' is not in allowed list`);
      }
    }
  }

  if (policyName === "code.release.publish.v1") {
    const assuranceLevel = passport.assurance_level || "L0";
    if (!meetsMinimumAssurance(assuranceLevel, "L3")) {
      return makeDeny(params, "oap.assurance_insufficient", `Required assurance level L3 not met (current: ${assuranceLevel})`);
    }

    const repository = String(context.repository ?? context.repo ?? "");
    if (!repository) {
      return makeDeny(params, "oap.missing_required_context", "Release context must include repository");
    }

    const version = String(context.version ?? "");
    if (!version) {
      return makeDeny(params, "oap.missing_required_context", "Release context must include version");
    }
    if (!/^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$/.test(version)) {
      return makeDeny(params, "oap.format_unsupported", `Version '${version}' does not follow semantic versioning`);
    }

    const files = Array.isArray(context.files) ? context.files : [];
    if (files.length === 0) {
      return makeDeny(params, "oap.missing_required_context", "Release context must include at least one file");
    }
    const sensitiveFile = files.find((file) => isSensitiveReleaseFile(file));
    if (sensitiveFile) {
      return makeDeny(params, "oap.file_forbidden", `Release file '${sensitiveFile}' is sensitive and cannot be published by default`);
    }

    if (!allowByList(repository, limits.allowed_repos, matchesSimpleGlob)) {
      return makeDeny(params, "oap.repo_not_allowed", `Repository '${repository}' is not in allowed release list`);
    }

    const allowedExtensions = Array.isArray(limits.allowed_extensions) ? limits.allowed_extensions : [];
    if (allowedExtensions.length > 0) {
      const blockedFile = files.find((file) => !releaseFileAllowed(file, allowedExtensions));
      if (blockedFile) {
        return makeDeny(params, "oap.file_forbidden", `Release file '${blockedFile}' has a forbidden extension`);
      }
    }
  }

  if (policyName === "system.command.execute.v1") {
    const command = String(context.command ?? context.cmd ?? "");
    if (command && !validateCommandString(command)) {
      return makeDeny(params, "oap.command_injection_detected", "Command contains potentially dangerous characters");
    }

    const allowedCommands = Array.isArray(limits.allowed_commands) ? limits.allowed_commands : [];
    if (!allowByList(command, allowedCommands, safePrefixMatch)) {
      return makeDeny(params, "oap.command_not_allowed", `Command '${command}' is not in allowed list`);
    }

    if (/rm\s+-[^\s]*r[^\s]*f[^\s]*\s+\/\s*$/i.test(command) ||
        /rm\s+-[^\s]*r[^\s]*f[^\s]*\s+\/\*/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Destructive file operation: rm -rf / or rm -rf /*");
    }
    if (/dd\s+if=\/dev\//i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Dangerous disk operation: dd if=/dev/");
    }
    if (/mkfs\./i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Filesystem creation: mkfs");
    }
    if (/(curl|wget)\s+[^|]*\|\s*(bash|sh|zsh|python|node)/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Download-and-execute pattern detected");
    }
    if (/:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}/.test(command) || /fork\(\)/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Fork bomb detected");
    }

    const blockedPatterns = Array.isArray(limits.blocked_patterns) ? limits.blocked_patterns : [];
    const blockedPattern = blockedPatterns.find((pattern) => safePatternMatch(command, pattern));
    if (blockedPattern) {
      return makeDeny(params, "oap.blocked_pattern", `Command contains blocked pattern: ${blockedPattern}`);
    }
  }

  if (policyName === "messaging.message.send.v1") {
    const recipient = String(context.recipient ?? context.to ?? context.channel_id ?? context.channel ?? context.target ?? "");
    if (!allowByList(recipient, limits.allowed_recipients, (value, pattern) => value === pattern || pattern === "*")) {
      return makeDeny(params, "oap.recipient_not_allowed", `Recipient '${recipient}' is not in allowed list`);
    }
  }

  if (policyName === "mcp.tool.execute.v1") {
    const server = String(context.server ?? context.mcp_server ?? "");
    if (!server && hasRestrictiveList(limits.allowed_servers)) {
      return makeDeny(params, "oap.missing_required_context", "MCP server is required when allowed_servers is restricted");
    }
    if (server && !mcpServerAllowed(server, limits.allowed_servers)) {
      return makeDeny(params, "oap.mcp_server_not_allowed", `MCP server '${server}' is not in allowed list`);
    }

    const tool = String(context.tool ?? context.mcp_tool ?? "");
    if (!tool && hasRestrictiveMcpToolLimits(limits)) {
      return makeDeny(params, "oap.missing_required_context", "MCP tool is required when allowed_tools or allowed_tool_prefixes is restricted");
    }
    if (tool && !mcpToolAllowed(tool, limits)) {
      return makeDeny(params, "oap.mcp_tool_not_allowed", `MCP tool '${tool}' is not in allowed list`);
    }
  }

  if (policyName === "data.file.read.v1") {
    const filePath = String(context.file_path ?? context.path ?? "");
    if (isDefaultSensitiveReadPath(filePath)) {
      return makeDeny(params, "oap.blocked_pattern", "File path matches default sensitive read pattern");
    }

    if (!allowByList(filePath, limits.allowed_paths, (value, pattern) => value.startsWith(pattern) || pattern === "*")) {
      return makeDeny(params, "oap.path_not_allowed", `File path '${filePath}' is not in allowed list`);
    }

    const blockedPattern = (Array.isArray(limits.blocked_patterns) ? limits.blocked_patterns : [])
      .find((pattern) => filePath.includes(pattern) || filePath === pattern);
    if (blockedPattern) {
      return makeDeny(params, "oap.blocked_pattern", `File path matches blocked pattern: ${blockedPattern}`);
    }
  }

  if (policyName === "data.file.write.v1") {
    const filePath = String(context.file_path ?? context.path ?? "");
    if (!allowByList(filePath, limits.allowed_paths, (value, pattern) => value.startsWith(pattern) || pattern === "*")) {
      return makeDeny(params, "oap.path_not_allowed", `File path '${filePath}' is not in allowed list`);
    }

    const blockedPath = (Array.isArray(limits.blocked_paths) ? limits.blocked_paths : [])
      .find((pattern) => filePath.startsWith(pattern));
    if (blockedPath) {
      return makeDeny(params, "oap.path_blocked", `Writing to system directory is not allowed: ${blockedPath}`);
    }

    const allowedExtensions = Array.isArray(limits.allowed_extensions) ? limits.allowed_extensions : [];
    if (allowedExtensions.length > 0) {
      const fileExt = extname(filePath).toLowerCase();
      if (fileExt && !allowedExtensions.includes(fileExt)) {
        return makeDeny(params, "oap.extension_not_allowed", `File extension ${fileExt} is not allowed`);
      }
    }
  }

  return makeAllow(params);
}
