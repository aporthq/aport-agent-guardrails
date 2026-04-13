import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { canonicalize } from "./decision.js";

const REQUIRED_CAPABILITIES = {
  "system.command.execute.v1": ["system.command.execute"],
  "code.repository.merge.v1": ["repo.pr.create", "repo.merge"],
  "messaging.message.send.v1": ["messaging.send"],
  "data.file.read.v1": ["data.file.read"],
  "data.file.write.v1": ["data.file.write"],
  "web.fetch.v1": ["web.fetch"],
  "web.browser.v1": ["web.browser"],
  "mcp.tool.execute.v1": ["mcp.tool.execute"],
  "agent.session.create.v1": ["agent.session.create"],
  "agent.tool.register.v1": ["agent.tool.register"],
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

function hasRequiredCapabilities(passport, policyId) {
  const required = REQUIRED_CAPABILITIES[policyId] || [];
  if (required.length === 0) return true;
  const granted = new Set(getCapabilityIds(passport));
  return required.every((capability) => {
    if (granted.has(capability)) return true;
    if (capability === "messaging.send" && granted.has("messaging.message.send")) return true;
    return false;
  });
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

export function evaluateLocalDecision({ policyName, context, passportFile }) {
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
    const filesChanged = Array.isArray(context.files_changed)
      ? context.files_changed.length
      : Number(context.files_changed ?? context.files ?? 0);
    const maxFiles = Number(limits.max_pr_size_kb ?? 500);
    if (Number.isFinite(filesChanged) && filesChanged > maxFiles) {
      return makeDeny(params, "oap.limit_exceeded", `PR size ${filesChanged} exceeds limit of ${maxFiles} files`);
    }

    const repo = String(context.repo ?? context.repository ?? "");
    if (!allowByList(repo, limits.allowed_repos, (value, pattern) => value === pattern || value.endsWith(`/${pattern}`) || pattern === "*")) {
      return makeDeny(params, "oap.repo_not_allowed", `Repository '${repo}' is not in allowed list`);
    }

    const branch = String(context.branch ?? "");
    if (!allowByList(branch, limits.allowed_base_branches, (value, pattern) => value === pattern || pattern === "*")) {
      return makeDeny(params, "oap.branch_not_allowed", `Branch '${branch}' is not in allowed list`);
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

    if (/rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]*[[:space:]]+\/[[:space:]]*$/i.test(command) ||
        /rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f[^[:space:]]+\/\*/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Destructive file operation: rm -rf / or rm -rf /*");
    }
    if (/dd[[:space:]]+if=\/dev\//i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Dangerous disk operation: dd if=/dev/");
    }
    if (/mkfs\./i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Filesystem creation: mkfs");
    }
    if (/(curl|wget)[[:space:]][^|]*\|[[:space:]]*(bash|sh|zsh|python|node)/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Download-and-execute pattern detected");
    }
    if (/:\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:[[:space:]]*&[[:space:]]*\}/.test(command) || /fork\(\)/i.test(command)) {
      return makeDeny(params, "oap.dangerous_operation", "Fork bomb detected");
    }

    const blockedPatterns = Array.isArray(limits.blocked_patterns) ? limits.blocked_patterns : [];
    const blockedPattern = blockedPatterns.find((pattern) => safePatternMatch(command, pattern));
    if (blockedPattern) {
      return makeDeny(params, "oap.blocked_pattern", `Command contains blocked pattern: ${blockedPattern}`);
    }
  }

  if (policyName === "messaging.message.send.v1") {
    const recipient = String(context.recipient ?? context.to ?? "");
    if (!allowByList(recipient, limits.allowed_recipients, (value, pattern) => value === pattern || pattern === "*")) {
      return makeDeny(params, "oap.recipient_not_allowed", `Recipient '${recipient}' is not in allowed list`);
    }
  }

  if (policyName === "data.file.read.v1") {
    const filePath = String(context.file_path ?? context.path ?? "");
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
