export function mapToolToPolicy(toolName) {
  const tool = String(toolName ?? "").toLowerCase();

  if (tool.match(/git\.(create_pr|merge|push|commit)/)) return "code.repository.merge.v1";
  if (tool.startsWith("git.")) return "code.repository.merge.v1";

  if (tool === "exec") return "system.command.execute.v1";
  if (tool.match(/exec\.(run|shell)/)) return "system.command.execute.v1";
  if (tool.startsWith("exec.")) return "system.command.execute.v1";
  if (tool.startsWith("system.command.")) return "system.command.execute.v1";
  if (tool === "bash" || tool === "shell" || tool === "command") return "system.command.execute.v1";

  if (tool.startsWith("message.")) return "messaging.message.send.v1";
  if (tool.startsWith("messaging.")) return "messaging.message.send.v1";
  if (tool.match(/sms|whatsapp|slack|email/)) return "messaging.message.send.v1";

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
  if (tool === "task" || tool === "taskcreate" || tool === "taskupdate" || tool === "taskstop") {
    return "agent.session.create.v1";
  }
  if (tool === "taskget" || tool === "tasklist" || tool === "taskoutput") return "data.file.read.v1";
  if (tool === "agent" || tool === "skill" || tool === "enterworktree") return "agent.session.create.v1";
  if (tool === "askuserquestion" || tool === "enterplanmode" || tool === "exitplanmode") return null;
  if (tool === "croncreate" || tool === "crondelete") return "agent.session.create.v1";
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
  if (tool.startsWith("mcp__")) return "mcp.tool.execute.v1";

  if (tool.match(/agent\.session|session\.create/)) return "agent.session.create.v1";
  if (tool === "sessions_spawn" || tool === "sessions_send") return "agent.session.create.v1";
  if (tool.startsWith("session.") || tool.startsWith("sessions.")) return "agent.session.create.v1";
  if (tool === "cron" || tool.startsWith("cron.")) return "agent.session.create.v1";

  if (tool === "gateway" || tool.startsWith("gateway.")) return "system.command.execute.v1";
  if (tool === "process" || tool.startsWith("process.")) return "system.command.execute.v1";

  if (tool.match(/agent\.tool|tool\.register/)) return "agent.tool.register.v1";

  if (tool.match(/payment\.refund|refund/)) return "finance.payment.refund.v1";
  if (tool.match(/payment\.charge|charge/)) return "finance.payment.charge.v1";
  if (tool.startsWith("finance.")) return "finance.payment.refund.v1";

  if (tool.match(/database\.(write|insert|update|delete)/)) return "data.export.create.v1";
  if (tool.match(/data\.export|export/)) return "data.export.create.v1";

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
