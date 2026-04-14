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

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
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

  if (tool.match(/git\.(create_pr|merge|push|commit)/)) return "code.repository.merge.v1";
  if (tool.startsWith("git.")) return "code.repository.merge.v1";

  if (tool === "exec") return "system.command.execute.v1";
  if (tool.match(/exec\.(run|shell)/)) return "system.command.execute.v1";
  if (tool.startsWith("exec.")) return "system.command.execute.v1";
  if (tool.startsWith("system.command.")) return "system.command.execute.v1";
  if (tool === "bash" || tool === "shell" || tool === "command") return "system.command.execute.v1";

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

  if (tool === "read") return "data.file.read.v1";
  if (tool.startsWith("file.read")) return "data.file.read.v1";
  if (tool.startsWith("data.file.read")) return "data.file.read.v1";
  if (tool === "write" || tool === "edit") return "data.file.write.v1";
  if (tool === "multiedit" || tool === "notebookedit") return "data.file.write.v1";
  if (tool === "glob" || tool === "ls" || tool === "grep" || tool === "toolsearch") {
    return "data.file.read.v1";
  }
  if (tool === "todoread") return "data.file.read.v1";
  if (tool === "todowrite") return "data.file.write.v1";
  if (tool === "taskget" || tool === "tasklist" || tool === "taskoutput") return "data.file.read.v1";
  if (tool === "askuserquestion" || tool === "enterplanmode" || tool === "exitplanmode") return null;
  if (tool === "cronlist") return "data.file.read.v1";
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
  return params || {};
}
