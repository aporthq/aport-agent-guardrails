#!/usr/bin/env node

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
import assert from "node:assert";
import { createHash } from "node:crypto";
import { access, mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import plugin, {
  canonicalize,
  mapToolToPolicy,
  verifyDecisionIntegrity,
} from "../../extensions/openclaw-aport/index.js";
import { evaluateLocalDecision } from "../../extensions/openclaw-aport/local-evaluator.js";
import {
  normalizeFileContext,
  normalizeMcpContext,
  normalizeMessageContext,
} from "../../extensions/openclaw-aport/tool-mapping.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginDir = path.resolve(__dirname, "../../extensions/openclaw-aport");

async function createTestPassport() {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "aport-openclaw-plugin-"));
  const aportDir = path.join(tempDir, "aport");
  await mkdir(aportDir, { recursive: true });
  const passportPath = path.join(aportDir, "passport.json");
  await writeFile(
    passportPath,
    JSON.stringify(
      {
        spec_version: "oap/1.0",
        status: "active",
        passport_id: "ap_test_passport",
        agent_id: "ap_test_passport",
        owner_id: "owner-1",
        assurance_level: "L0",
        capabilities: [
          { id: "system.command.execute" },
          { id: "code.repository.merge" },
          { id: "messaging.message.send" },
        ],
        limits: {
          "system.command.execute": {
            allowed_commands: ["ls", "git", "node"],
            blocked_patterns: ["sudo", "rm -rf"],
            max_execution_time: 300,
          },
        },
      },
      null,
      2,
    ),
    "utf8",
  );
  return { tempDir, passportPath };
}

async function registerPlugin(config) {
  let beforeToolCallHandler;
  plugin.register({
    pluginConfig: config,
    logger: {
      info() {},
      warn() {},
      error() {},
    },
    on(eventName, handler) {
      if (eventName === "before_tool_call") beforeToolCallHandler = handler;
    },
  });
  assert.ok(beforeToolCallHandler, "plugin should register before_tool_call");
  return beforeToolCallHandler;
}

describe("canonicalize", () => {
  it("sorts keys recursively", () => {
    assert.strictEqual(canonicalize({ b: 1, a: { z: 1, y: 2 } }), '{"a":{"y":2,"z":1},"b":1}');
  });
});

describe("verifyDecisionIntegrity", () => {
  it("returns true when content_hash matches", () => {
    const decision = {
      allow: false,
      decision_id: "dec-1",
      reasons: [{ code: "oap.denied", message: "test" }],
    };
    const content_hash = `sha256:${createHash("sha256").update(canonicalize(decision), "utf8").digest("hex")}`;
    assert.strictEqual(verifyDecisionIntegrity({ ...decision, content_hash }), true);
  });
});

describe("mapToolToPolicy", () => {
  it("maps current OpenClaw message and MCP tools while dropping speculative mappings", () => {
    assert.strictEqual(mapToolToPolicy("exec.run"), "system.command.execute.v1");
    assert.strictEqual(mapToolToPolicy("git.create_pr"), "code.repository.merge.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "send" }), "messaging.message.send.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "react" }), "messaging.message.send.v1");
    assert.strictEqual(mapToolToPolicy("message", { action: "read" }), null);
    assert.strictEqual(mapToolToPolicy("multiedit"), "data.file.write.v1");
    assert.strictEqual(mapToolToPolicy("agent"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("Agent"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("task"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("websearch"), "web.fetch.v1");
    assert.strictEqual(mapToolToPolicy("powershell"), "system.command.execute.v1");
    assert.strictEqual(mapToolToPolicy("mcp__github__list"), "mcp.tool.execute.v1");
    assert.strictEqual(mapToolToPolicy("vigil-harbor__memory_search"), "mcp.tool.execute.v1");
    assert.strictEqual(mapToolToPolicy("sessions_spawn"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("sessions_send"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("sessions_list"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("sessions_history"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("cronlist"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("croncreate"), "agent.session.create.v1");
    assert.strictEqual(mapToolToPolicy("view"), "data.file.read.v1");
    assert.strictEqual(mapToolToPolicy("tool.register"), null);
    assert.strictEqual(mapToolToPolicy("refund"), null);
    assert.strictEqual(mapToolToPolicy("export"), null);
    assert.strictEqual(mapToolToPolicy("unknown.tool"), null);
  });
});

describe("normalizeFileContext", () => {
  it("maps OpenClaw path-shaped file params to OAP file_path", () => {
    assert.deepStrictEqual(normalizeFileContext({ path: "README.md", content: "hi" }), {
      path: "README.md",
      file_path: "README.md",
      content: "hi",
    });
    assert.deepStrictEqual(normalizeFileContext({ file_path: "README.md", content: "hi" }), {
      file_path: "README.md",
      content: "hi",
    });
  });
});

describe("normalizeMessageContext", () => {
  it("maps current OpenClaw message params to APort messaging context", () => {
    assert.deepStrictEqual(
      normalizeMessageContext({
        action: "sendAttachment",
        target: "telegram:group:123",
        caption: "Invoice attached",
        filename: "invoice.pdf",
        threadId: "42",
        replyTo: "99",
      }),
      {
        action: "sendAttachment",
        target: "telegram:group:123",
        caption: "Invoice attached",
        filename: "invoice.pdf",
        threadId: "42",
        replyTo: "99",
        message_type: "file",
        channel_id: "telegram:group:123",
        message: "Invoice attached",
        thread_id: "42",
        reply_to: "99",
        attachments: [{ filename: "invoice.pdf" }],
      },
    );
    assert.deepStrictEqual(
      normalizeMessageContext({ action: "react", target: "whatsapp:chat:1", emoji: "👍" }),
      {
        action: "react",
        target: "whatsapp:chat:1",
        emoji: "👍",
        message_type: "reaction",
        channel_id: "whatsapp:chat:1",
        message: "👍",
      },
    );
  });
});

describe("normalizeMcpContext", () => {
  it("derives MCP policy context from provider-safe OpenClaw tool names", () => {
    assert.deepStrictEqual(
      normalizeMcpContext("vigil-harbor__memory_search", { query: "release notes" }),
      {
        query: "release notes",
        server: "mcp://vigil-harbor",
        tool: "memory_search",
        parameters: { query: "release notes" },
      },
    );
    assert.deepStrictEqual(
      normalizeMcpContext("mcp__github__pull_requests-create", {
        input: { owner: "aporthq", repo: "aport-agent-guardrails" },
      }),
      {
        input: { owner: "aporthq", repo: "aport-agent-guardrails" },
        server: "mcp://github",
        tool: "pull_requests-create",
        parameters: { owner: "aporthq", repo: "aport-agent-guardrails" },
      },
    );
  });
});

describe("local evaluator", () => {
  it("allows safe commands and denies blocked ones without child_process", async () => {
    const { tempDir, passportPath } = await createTestPassport();

    const allowDecision = evaluateLocalDecision({
      policyName: "system.command.execute.v1",
      context: { command: "ls -la" },
      passportFile: passportPath,
    });
    assert.strictEqual(allowDecision.allow, true);
    assert.strictEqual(verifyDecisionIntegrity(allowDecision), true);

    const denyDecision = evaluateLocalDecision({
      policyName: "system.command.execute.v1",
      context: { command: "sudo ls" },
      passportFile: passportPath,
    });
    assert.strictEqual(denyDecision.allow, false);
    assert.strictEqual(denyDecision.reasons[0].code, "oap.command_not_allowed");

    await rm(tempDir, { recursive: true, force: true });
  });
});

describe("plugin hook contract", () => {
  it("returns only documented before_tool_call fields on allow and deny", async () => {
    const { tempDir, passportPath } = await createTestPassport();
    const beforeToolCall = await registerPlugin({ mode: "local", passportFile: passportPath });

    const allowResult = await beforeToolCall({ toolName: "exec.run", params: { command: "ls -la" } });
    assert.deepStrictEqual(allowResult, {});

    const denyResult = await beforeToolCall({ toolName: "exec.run", params: { command: "sudo ls" } });
    assert.strictEqual(denyResult.block, true);
    assert.ok(typeof denyResult.blockReason === "string" && denyResult.blockReason.includes("APort Policy Denied"));
    assert.ok(!Object.prototype.hasOwnProperty.call(denyResult, "reasons"));

    await rm(tempDir, { recursive: true, force: true });
  });

  it("normalizes write tool params before API verification", async () => {
    const originalFetch = globalThis.fetch;
    let seenBody = null;
    globalThis.fetch = async (_url, opts) => {
      seenBody = JSON.parse(String(opts?.body ?? "{}"));
      return {
        ok: true,
        async json() {
          return {
            decision: {
              allow: true,
              decision_id: "dec-1",
              reasons: [{ code: "oap.allowed", message: "ok" }],
              content_hash: `sha256:${createHash("sha256").update(canonicalize({
                allow: true,
                decision_id: "dec-1",
                reasons: [{ code: "oap.allowed", message: "ok" }],
              }), "utf8").digest("hex")}`,
            },
          };
        },
      };
    };

    try {
      const beforeToolCall = await registerPlugin({ mode: "api", agentId: "ap_test" });
      const result = await beforeToolCall({ toolName: "write", params: { path: "README.md", content: "hi" } });
      assert.deepStrictEqual(result, {});
      assert.ok(seenBody);
      assert.strictEqual(seenBody.context.file_path, "README.md");
      assert.strictEqual(seenBody.context.path, "README.md");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("scanner compatibility", () => {
  it("keeps dangerous runtime patterns out of plugin source files", async () => {
    const entries = await readdir(pluginDir);
    const sourceFiles = entries.filter((entry) => entry.endsWith(".js") || entry.endsWith(".ts"));

    assert.ok(!sourceFiles.includes("index.ts"), "plugin should not ship stale TypeScript entrypoints");
    assert.ok(!sourceFiles.includes("test.js"), "plugin should not ship test.js inside the extension bundle");

    for (const sourceFile of sourceFiles) {
      const contents = await readFile(path.join(pluginDir, sourceFile), "utf8");
      assert.ok(!contents.includes("child_process"), `${sourceFile} should not reference child_process`);
      assert.ok(!contents.includes("process.env"), `${sourceFile} should not reference process.env`);
    }
  });

  it("publishes only runtime files and declares current OpenClaw compatibility metadata", async () => {
    const packageJson = JSON.parse(await readFile(path.join(pluginDir, "package.json"), "utf8"));
    assert.ok(Array.isArray(packageJson.files), "package.json should whitelist published plugin files");
    assert.ok(packageJson.files.includes("index.js"));
    assert.ok(!packageJson.files.some((entry) => entry.endsWith(".ts")), "published files should not include TypeScript source");
    assert.ok(!packageJson.files.some((entry) => entry.includes("test")), "published files should not include test artifacts");
    assert.strictEqual(packageJson.openclaw.install.minHostVersion, ">=2026.4.11");
    assert.strictEqual(packageJson.openclaw.compat.pluginApi, ">=2026.4.11");
    assert.strictEqual(packageJson.openclaw.build.openclawVersion, "2026.4.11");
    const manifest = JSON.parse(await readFile(path.join(pluginDir, "openclaw.plugin.json"), "utf8"));
    assert.ok(Object.prototype.hasOwnProperty.call(manifest.configSchema.properties, "alwaysVerifyEachToolCall"));
    assert.match(manifest.configSchema.properties.alwaysVerifyEachToolCall.description, /Deprecated compatibility field/);
    await access(path.join(pluginDir, "openclaw.plugin.json"));
  });
});
