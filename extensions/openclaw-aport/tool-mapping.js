const MESSAGE_SEND_ACTIONS = new Set([
  "send",
  "broadcast",
  "reply",
  "thread-reply",
  "sendwitheffect",
  "sendattachment",
  "upload-file",
  "react",
]);

const RELEASE_PUBLISH_ACTIONS = new Set([
  "create",
  "publish",
  "release",
  "upload",
]);
const SESSION_TYPES = new Set(["interactive", "batch", "webhook", "scheduled", "ephemeral"]);
const DURATION_SECOND_KEYS = [
  "requested_duration",
  "requestedDuration",
  "requested_duration_seconds",
  "requestedDurationSeconds",
  "session_duration_seconds",
  "sessionDurationSeconds",
  "duration_seconds",
  "durationSeconds",
  "ttl_seconds",
  "ttlSeconds",
];
const DURATION_MILLISECOND_KEYS = [
  "requested_duration_ms",
  "requestedDurationMs",
  "session_duration_ms",
  "sessionDurationMs",
  "duration_ms",
  "durationMs",
];

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function cleanString(value, limit = 200) {
  return String(value ?? "")
    .replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit);
}

function readAction(params) {
  const src = params && typeof params === "object" ? params : {};
  return firstNonEmpty(
    src.action,
    src.action_name,
    src.actionName,
    src.arguments && typeof src.arguments === "object" ? src.arguments.action : "",
    src.input && typeof src.input === "object" ? src.input.action : "",
  ).toLowerCase();
}

function sessionOperation(toolName) {
  const name = String(toolName ?? "").toLowerCase().replace(/^functions\./, "");
  if (name.includes("interrupt")) return "update";
  if (name.includes("close") || name.includes("stop") || name.includes("delete")) return "close";
  if (name.includes("list") || name.includes("status") || name.includes("history") || name.includes("wait")) return "list";
  if (name.includes("resume")) return "resume";
  if (name.includes("send") || name.includes("update") || name.includes("followup")) return "update";
  if (
    name === "agent" ||
    name === "task" ||
    name === "subagent" ||
    name === "subagentstart" ||
    name === "sessions_spawn" ||
    name === "croncreate" ||
    name.includes("spawn") ||
    name.includes("create") ||
    name.includes("start")
  ) {
    return "create";
  }
  return "other";
}

function sessionTypeEvidence(toolName, src) {
  const rawExplicit = src.session_type ?? src.sessionType;
  if (rawExplicit != null && typeof rawExplicit !== "string") {
    return { sessionType: "", invalid: true };
  }
  if (rawExplicit != null && rawExplicit.trim() !== "") {
    const explicit = cleanString(rawExplicit, 32).toLowerCase();
    if (SESSION_TYPES.has(explicit)) return { sessionType: explicit, invalid: false };
    return { sessionType: "", invalid: true };
  }
  const name = String(toolName ?? "").toLowerCase();
  if (name.includes("cron") || name.includes("schedulewakeup") || name.includes("schedule_wakeup")) {
    return { sessionType: "scheduled", invalid: false };
  }
  if (name.includes("remote") || name.includes("webhook")) return { sessionType: "webhook", invalid: false };
  if (name.includes("batch")) return { sessionType: "batch", invalid: false };
  if (name.includes("ephemeral")) return { sessionType: "ephemeral", invalid: false };
  return { sessionType: "interactive", invalid: false };
}

function providedValues(src, keys) {
  return keys
    .filter((key) => Object.prototype.hasOwnProperty.call(src, key) && src[key] != null)
    .map((key) => src[key]);
}

function parseDecimalScalar(value) {
  if (typeof value === "number") {
    return Number.isFinite(value) && value > 0 ? value : null;
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!/^(?:0|[1-9]\d*)(?:\.\d+)?$/.test(trimmed)) return null;
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }
  return null;
}

function requestedDuration(src) {
  const candidates = [
    ...providedValues(src, DURATION_SECOND_KEYS).map((value) => ({ unit: "s", value })),
    ...providedValues(src, DURATION_MILLISECOND_KEYS).map((value) => ({ unit: "ms", value })),
  ];
  if (candidates.length === 0) return null;

  const normalized = [];
  for (const candidate of candidates) {
    const parsed = parseDecimalScalar(candidate.value);
    if (parsed == null) return "invalid";
    normalized.push(candidate.unit === "ms" ? Math.ceil(parsed / 1000) : Math.ceil(parsed));
  }

  const unique = new Set(normalized);
  if (unique.size !== 1) return "invalid";
  const seconds = normalized[0];
  if (seconds < 60 || seconds > 86400) return "invalid";
  return seconds;
}

function parseNonNegativeInteger(value) {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^(?:0|[1-9]\d*)$/.test(value.trim())) {
    return Number(value.trim());
  }
  return null;
}

function activeSessionCountEvidence(src) {
  const rawValues = [];
  if (Object.prototype.hasOwnProperty.call(src, "active_session_count") && src.active_session_count != null) {
    rawValues.push(src.active_session_count);
  }
  if (Object.prototype.hasOwnProperty.call(src, "current_active_sessions") && src.current_active_sessions != null) {
    rawValues.push(src.current_active_sessions);
  }
  if (rawValues.length === 0) return { present: false, invalid: false, value: null };

  const normalized = rawValues.map(parseNonNegativeInteger);
  if (normalized.some((value) => value == null)) return { present: true, invalid: true, value: null };
  if (new Set(normalized).size !== 1) return { present: true, invalid: true, value: null };
  return { present: true, invalid: false, value: normalized[0] };
}

export function parseMcpToolName(toolName) {
  const raw = String(toolName ?? "").trim();
  if (!raw) return null;

  if (raw.startsWith("mcp__")) {
    const parts = raw.split("__");
    if (parts.length >= 3 && parts[1] && parts.slice(2).join("__")) {
      return {
        serverName: parts[1],
        toolName: parts.slice(2).join("__"),
      };
    }
  }

  const separatorIndex = raw.indexOf("__");
  if (separatorIndex <= 0 || separatorIndex >= raw.length - 2) {
    return null;
  }

  return {
    serverName: raw.slice(0, separatorIndex),
    toolName: raw.slice(separatorIndex + 2),
  };
}

export function mapToolToPolicy(toolName, params) {
  const rawTool = String(toolName ?? "").trim();
  const tool = rawTool.toLowerCase();

  if (
    tool === "release.publish" ||
    tool === "release.create" ||
    tool === "repo.release.publish" ||
    tool === "repo.release.create" ||
    tool === "git.release" ||
    tool.includes("release.publish") ||
    tool.includes("release.create") ||
    ((tool === "release" || tool === "repo.release") && RELEASE_PUBLISH_ACTIONS.has(readAction(params)))
  ) {
    return "code.release.publish.v1";
  }
  if (tool.match(/git\.(create_pr|merge|push|commit)/)) return "code.repository.merge.v1";
  if (tool.startsWith("git.")) return "code.repository.merge.v1";

  if (tool === "exec") return "system.command.execute.v1";
  if (tool.match(/exec\.(run|shell)/)) return "system.command.execute.v1";
  if (tool.startsWith("exec.")) return "system.command.execute.v1";
  if (tool.startsWith("system.command.")) return "system.command.execute.v1";
  if (tool === "bash" || tool === "shell" || tool === "command" || tool === "powershell" || tool === "monitor") {
    return "system.command.execute.v1";
  }

  if (tool === "message") {
    return MESSAGE_SEND_ACTIONS.has(readAction(params)) ? "messaging.message.send.v1" : null;
  }
  if (
    tool === "message.send" ||
    tool === "message.reply" ||
    tool === "message.broadcast" ||
    tool === "message.react" ||
    tool === "messaging.message.send"
  ) {
    return "messaging.message.send.v1";
  }
  if (tool.match(/(^|[._-])(whatsapp|telegram|slack|email)([._-](send|reply|broadcast|message|react))?$/)) {
    return "messaging.message.send.v1";
  }

  if (tool === "read" || tool === "view") return "data.file.read.v1";
  if (tool.startsWith("file.read")) return "data.file.read.v1";
  if (tool.startsWith("data.file.read")) return "data.file.read.v1";
  if (tool === "sessions_list" || tool === "sessions_history") return "data.file.read.v1";
  if (tool === "write" || tool === "edit") return "data.file.write.v1";
  if (tool === "multiedit" || tool === "notebookedit") return "data.file.write.v1";
  if (tool === "glob" || tool === "ls" || tool === "grep" || tool === "toolsearch") {
    return "data.file.read.v1";
  }
  if (tool === "todoread") return "data.file.read.v1";
  if (tool === "todowrite") return "data.file.write.v1";
  if (tool === "taskget" || tool === "tasklist" || tool === "taskoutput" || tool === "cronlist") {
    return "data.file.read.v1";
  }
  if (
    tool === "agent" ||
    tool === "task" ||
    tool === "taskcreate" ||
    tool === "taskupdate" ||
    tool === "taskstop" ||
    tool === "skill" ||
    tool === "enterworktree" ||
    tool === "exitworktree" ||
    tool === "subagent" ||
    tool === "subagentstart" ||
    tool === "sendmessage" ||
    tool === "teamcreate" ||
    tool === "teamdelete" ||
    tool === "remotetrigger" ||
    tool === "sessions_spawn" ||
    tool === "sessions_send" ||
    tool === "sessions_yield" ||
    tool === "subagents" ||
    tool === "session_status" ||
    tool === "croncreate" ||
    tool === "crondelete"
  ) {
    return "agent.session.create.v1";
  }
  if (tool === "askuserquestion" || tool === "enterplanmode" || tool === "exitplanmode") return null;
  if (tool.startsWith("file.write")) return "data.file.write.v1";
  if (tool.startsWith("file.edit")) return "data.file.write.v1";
  if (tool.startsWith("data.file.write")) return "data.file.write.v1";

  if (tool === "web_fetch" || tool === "webfetch") return "web.fetch.v1";
  if (tool === "web_search" || tool === "websearch") return "web.fetch.v1";
  if (tool.startsWith("web.fetch")) return "web.fetch.v1";
  if (tool.startsWith("web.search")) return "web.fetch.v1";
  if (tool === "browser") return "web.browser.v1";
  if (tool.startsWith("web.browser")) return "web.browser.v1";
  if (tool.startsWith("browser.")) return "web.browser.v1";

  if (tool.startsWith("mcp.")) return "mcp.tool.execute.v1";
  if (parseMcpToolName(rawTool)) return "mcp.tool.execute.v1";

  if (tool === "gateway" || tool.startsWith("gateway.")) return "system.command.execute.v1";
  if (tool === "process" || tool.startsWith("process.")) return "system.command.execute.v1";

  return null;
}

export function normalizeExecContext(params, event) {
  const src = event && typeof event === "object" ? { ...event, ...params } : params || {};
  if (!src || typeof src !== "object") return { command: "" };

  const raw =
    src.command ??
    src.cmd ??
    (src.arguments && typeof src.arguments === "object" ? src.arguments.command : null) ??
    (src.input && typeof src.input === "object" ? src.input.command : null) ??
    (typeof src.input === "string" && src.input.trim().length > 0 ? src.input : null) ??
    (src.args && typeof src.args === "object" ? src.args.command : null) ??
    (src.invocation && typeof src.invocation === "object" ? src.invocation.command : null) ??
    (src.payload && typeof src.payload === "object" ? src.payload.command : null) ??
    (Array.isArray(src.args) && src.args.length > 0 ? src.args.join(" ") : src.args?.[0]);

  const full = typeof raw === "string" ? raw : raw != null ? String(raw) : "";
  const out = { ...(params || {}), command: full, full_command: full };
  if (params && params.workdir !== undefined && out.cwd === undefined) out.cwd = params.workdir;
  return out;
}

export function normalizeFileContext(params) {
  const src = params && typeof params === "object" ? params : {};
  const filePath =
    src.file_path ??
    src.path ??
    src.filePath ??
    (src.arguments && typeof src.arguments === "object" ? src.arguments.file_path ?? src.arguments.path : null) ??
    (src.input && typeof src.input === "object" ? src.input.file_path ?? src.input.path : null) ??
    (src.args && typeof src.args === "object" ? src.args.file_path ?? src.args.path : null);

  if (filePath == null || String(filePath).trim() === "") {
    return { ...src };
  }

  return {
    ...src,
    file_path: String(filePath),
  };
}

export function normalizeMessageContext(params) {
  const src = params && typeof params === "object" ? params : {};
  const action = readAction(src);
  const firstTarget = Array.isArray(src.targets)
    ? src.targets.find((value) => typeof value === "string" && value.trim())
    : "";
  const channelId = firstNonEmpty(
    src.channel_id,
    src.channelId,
    src.target,
    firstTarget,
    src.channel,
    src.to,
    src.accountId,
  );
  const isAttachmentAction =
    action === "sendattachment" ||
    action === "upload-file" ||
    Boolean(src.media || src.buffer || src.path || src.filePath || src.filename);
  const messageType = action === "react" ? "reaction" : isAttachmentAction ? "file" : "text";
  const message = firstNonEmpty(
    src.message,
    src.text,
    src.content,
    src.caption,
    src.quoteText,
    src.emoji,
    isAttachmentAction ? src.filename : "",
  );
  const threadId = firstNonEmpty(src.thread_id, src.threadId);
  const replyTo = firstNonEmpty(src.reply_to, src.replyTo, src.messageId, src.message_id);
  const out = {
    ...src,
    message_type: src.message_type ?? messageType,
  };

  if (channelId) out.channel_id = channelId;
  if (message) out.message = message;
  else if (messageType === "reaction") out.message = "reaction";
  else if (messageType === "file") out.message = "[attachment]";

  if (threadId) out.thread_id = threadId;
  if (replyTo) out.reply_to = replyTo;

  if (!Array.isArray(out.attachments) && isAttachmentAction) {
    out.attachments = [
      {
        ...(typeof src.media === "string" && src.media ? { url: src.media } : {}),
        ...(typeof src.filename === "string" && src.filename ? { filename: src.filename } : {}),
      },
    ];
  }

  return out;
}

function buildMcpParameters(src) {
  if (src.parameters && typeof src.parameters === "object") return src.parameters;
  if (src.arguments && typeof src.arguments === "object") return src.arguments;
  if (src.input && typeof src.input === "object") return src.input;
  if (src.payload && typeof src.payload === "object") return src.payload;

  const {
    server,
    server_url,
    serverUrl,
    server_name,
    serverName,
    tool,
    tool_name,
    toolName,
    parameters,
    ...rest
  } = src;
  return rest;
}

export function normalizeMcpContext(toolName, params) {
  const src = params && typeof params === "object" ? params : {};
  const parsed = parseMcpToolName(toolName);
  const serverName = firstNonEmpty(
    src.server,
    src.server_url,
    src.serverUrl,
    src.server_name,
    src.serverName,
    src.mcp_server,
    parsed?.serverName,
  );
  const normalizedServer =
    serverName && serverName.includes("://") ? serverName : serverName ? `mcp://${serverName}` : "";
  const tool = firstNonEmpty(src.tool, src.tool_name, src.toolName, src.mcp_tool, parsed?.toolName);
  const out = {
    ...src,
    parameters: buildMcpParameters(src),
  };

  if (normalizedServer) out.server = normalizedServer;
  if (tool) out.tool = tool;

  return out;
}

export function normalizeSessionContext(toolName, params, event = {}) {
  const paramsObj = params && typeof params === "object" ? params : {};
  const eventObj = event && typeof event === "object" ? event : {};
  const args = paramsObj.args && typeof paramsObj.args === "object" && !Array.isArray(paramsObj.args) ? paramsObj.args : {};
  const input = paramsObj.input && typeof paramsObj.input === "object" ? paramsObj.input : {};
  const nested = { ...args, ...input, ...paramsObj };
  const operation = sessionOperation(toolName);
  const typeEvidence = sessionTypeEvidence(toolName, nested);
  const description = firstNonEmpty(
    nested.description,
    nested.task,
    nested.message,
    nested.prompt,
  );
  const userId = cleanString(eventObj.user_id ?? eventObj.userId);
  const duration = requestedDuration(nested);
  const activeSessionCount = activeSessionCountEvidence(eventObj);
  const sessionId =
    operation === "create"
      ? ""
      : firstNonEmpty(
          nested.child_session_id,
          nested.childSessionId,
          eventObj.subagent_id,
          nested.subagent_id,
          nested.agent_id,
          nested.agentId,
          nested.id,
          nested.session_id,
          nested.sessionId,
          eventObj.target_session_id,
          eventObj.targetSessionId,
        );
  const out = {
    description_length: description.length,
    session_operation: operation,
    session_type: typeEvidence.sessionType || "interactive",
    session_tracking: "host_active_count",
    hook_event: cleanString(eventObj.hook_event_name ?? eventObj.event, 80),
    active_session_count: activeSessionCount.value,
    current_active_sessions: activeSessionCount.value,
    parent_session_id: cleanString(eventObj.session_id ?? eventObj.sessionId, 200),
    session_call_id: cleanString(eventObj.toolCallId ?? eventObj.tool_call_id ?? eventObj.id ?? eventObj.callId ?? eventObj.call_id, 200),
    session_id: cleanString(sessionId, 200),
    subagent_type: cleanString(eventObj.subagent_type ?? nested.subagent_type ?? nested.agent_type, 80),
  };
  if (userId) out.user_id = userId;
  if (duration === "invalid") out.invalid_session_duration = true;
  else if (duration != null) out.requested_duration = duration;
  if (typeEvidence.invalid) out.invalid_session_type = true;
  if (activeSessionCount.invalid) out.invalid_session_count = true;
  return out;
}

export function normalizePolicyContext(policyName, toolName, params, event) {
  if (policyName === "system.command.execute.v1") {
    return normalizeExecContext(params, event);
  }
  if (policyName === "data.file.read.v1" || policyName === "data.file.write.v1") {
    return normalizeFileContext(params);
  }
  if (policyName === "messaging.message.send.v1") {
    return normalizeMessageContext(params);
  }
  if (policyName === "mcp.tool.execute.v1") {
    return normalizeMcpContext(toolName, params);
  }
  if (policyName === "agent.session.create.v1") {
    return normalizeSessionContext(toolName, params, event);
  }
  return params || {};
}
