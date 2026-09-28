#!/bin/bash
# Pin the OpenClaw plugin to the before_tool_call contract reviewed against OpenClaw v2026.9.5
# (docs/OPENCLAW_COMPATIBILITY.md) and keep the README badge, manifest, package metadata,
# compatibility doc, and drift baseline in agreement.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="${APORT_TEST_DIR:-$(mktemp -d 2> /dev/null || echo "$REPO_ROOT/tests/output")}"
mkdir -p "$TEST_DIR"

node --input-type=module - "$REPO_ROOT" "$TEST_DIR" << 'NODE'
import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [repoRoot, testDir] = process.argv.slice(2);
const pluginDir = path.join(repoRoot, "extensions", "openclaw-aport");
const readJson = async (p) => JSON.parse(await readFile(p, "utf8"));

const pkg = await readJson(path.join(pluginDir, "package.json"));
const manifest = await readJson(path.join(pluginDir, "openclaw.plugin.json"));
const baseline = await readJson(path.join(repoRoot, "docs", "framework-drift-baseline.json"));
const readme = await readFile(path.join(repoRoot, "README.md"), "utf8");
const compatDoc = await readFile(path.join(repoRoot, "docs", "OPENCLAW_COMPATIBILITY.md"), "utf8");
const indexSource = await readFile(path.join(pluginDir, "index.js"), "utf8");

// 1. Host version floors: one value, semver floor syntax, mirrored in the README badge and compat doc.
const minHost = pkg.openclaw?.install?.minHostVersion;
const pluginApi = pkg.openclaw?.compat?.pluginApi;
assert.match(minHost, /^>=\d{4}\.\d+\.\d+$/, "openclaw.install.minHostVersion must be a semver floor like >=2026.4.11");
assert.equal(pluginApi, minHost, "openclaw.compat.pluginApi must match openclaw.install.minHostVersion");
const badge = readme.match(/OpenClaw-%3E%3D([0-9.]+)-blue/);
assert.ok(badge, "README.md should carry the OpenClaw version badge");
assert.equal(`>=${badge[1]}`, minHost, "README OpenClaw badge must match package.json minHostVersion");
assert.ok(compatDoc.includes(minHost), "docs/OPENCLAW_COMPATIBILITY.md must state the minimum host version");
const latestTag = baseline.sources?.["openclaw-tags"]?.latestTag;
assert.match(latestTag || "", /^v\d{4}\.\d+\.\d+$/, "drift baseline must record the latest OpenClaw tag");
assert.ok(
  compatDoc.includes(latestTag),
  `docs/OPENCLAW_COMPATIBILITY.md must mention the baseline tag ${latestTag}; re-review before bumping the baseline`,
);

// 2. Manifest shape the host validates before loading plugin code.
assert.equal(manifest.id, "openclaw-aport");
assert.equal(manifest.version, pkg.version, "manifest version must match package version");
assert.equal(typeof manifest.activation?.onStartup, "boolean", "activation.onStartup must be set explicitly");
const allowedCapabilities = new Set(["provider", "channel", "tool", "hook"]);
for (const capability of manifest.activation?.onCapabilities || []) {
  assert.ok(allowedCapabilities.has(capability), `unknown activation.onCapabilities value: ${capability}`);
}
assert.ok((manifest.activation?.onCapabilities || []).includes("hook"), "activation.onCapabilities must include hook");
assert.equal(manifest.configSchema?.type, "object");
assert.equal(manifest.configSchema?.additionalProperties, false, "configSchema must stay strict");
assert.deepEqual(pkg.openclaw?.extensions, ["./index.js"], "package.json#openclaw.extensions must point at index.js");

// 3. SDK imports: only the current plugin-entry subpath, none of the deprecated ones.
const sdkImports = [...indexSource.matchAll(/from\s+["'](openclaw\/[^"']+)["']/g)].map((m) => m[1]);
assert.deepEqual(sdkImports, ["openclaw/plugin-sdk/plugin-entry"], `unexpected openclaw SDK imports: ${sdkImports.join(", ")}`);
const retiredSubpaths = [
  "plugin-sdk/config-runtime",
  "plugin-sdk/infra-runtime",
  "plugin-sdk/channel-message",
  "plugin-sdk/channel-lifecycle",
  "plugin-sdk/channel-reply-pipeline",
  "plugin-sdk/zod",
  "plugin-sdk/text-runtime",
];
for (const subpath of retiredSubpaths) {
  assert.ok(!indexSource.includes(subpath), `index.js must not import deprecated ${subpath}`);
}
assert.ok(!/registerHook\(/.test(indexSource), "typed hooks must be registered with api.on, not api.registerHook");

// 4. Registration: exactly one typed hook, named before_tool_call, optional options limited to matcher/priority.
const plugin = (await import(pathToFileURL(path.join(pluginDir, "index.js")).href)).default;
const registrations = [];
plugin.register({
  pluginConfig: { mode: "local", passportFile: path.join(testDir, "aport", "passport.json") },
  logger: { info() {}, warn() {}, error() {} },
  on(name, handler, options) {
    registrations.push({ name, handler, options });
  },
});
assert.equal(registrations.length, 1, "plugin should register exactly one hook");
assert.equal(registrations[0].name, "before_tool_call");
assert.equal(typeof registrations[0].handler, "function");
if (registrations[0].options !== undefined) {
  const optionKeys = Object.keys(registrations[0].options);
  assert.ok(optionKeys.every((key) => key === "matcher" || key === "priority"), `unexpected hook options: ${optionKeys}`);
}
const beforeToolCall = registrations[0].handler;

// 5. Return contract against a v2026.9.5-shaped event and context.
await mkdir(path.join(testDir, "aport"), { recursive: true });
await writeFile(
  path.join(testDir, "aport", "passport.json"),
  JSON.stringify({
    spec_version: "oap/1.0",
    status: "active",
    passport_id: "ap_contract_test",
    agent_id: "ap_contract_test",
    owner_id: "owner-1",
    assurance_level: "L0",
    capabilities: [{ id: "system.command.execute" }],
    limits: {
      "system.command.execute": {
        allowed_commands: ["ls", "git"],
        blocked_patterns: ["sudo", "rm -rf"],
        max_execution_time: 300,
      },
    },
  }),
  "utf8",
);

const allowedResultKeys = new Set(["params", "block", "blockReason", "requireApproval"]);
const controller = new AbortController();
const ctx = {
  agentId: "main",
  sessionKey: "agent:main:main",
  sessionId: "session-1",
  runId: "run-1",
  toolName: "exec",
  toolCallId: "call-1",
  abortSignal: controller.signal,
  trace: { traceId: "trace-1" },
  requester: { channel: "discord", accountId: "ops", senderId: "user-1", senderIsOwner: false, roleIds: [] },
};
const event = (params, extra = {}) => ({
  toolName: "exec",
  params,
  toolKind: "exec",
  runId: "run-1",
  toolCallId: "call-1",
  ...extra,
});
const assertContract = (result, label) => {
  assert.ok(result && typeof result === "object", `${label}: handler must return an object`);
  for (const key of Object.keys(result)) {
    assert.ok(allowedResultKeys.has(key), `${label}: undocumented before_tool_call result field ${key}`);
  }
  assert.ok(!("params" in result), `${label}: plugin must not rewrite params`);
  assert.ok(!("requireApproval" in result), `${label}: plugin must not request approvals`);
};

const allow = await beforeToolCall(event({ command: "ls -la" }), ctx);
assertContract(allow, "allow");
assert.notEqual(allow.block, true, "allowed command must not be blocked");

const deny = await beforeToolCall(event({ command: "sudo ls" }), ctx);
assertContract(deny, "deny");
assert.equal(deny.block, true, "blocked command must return block: true");
assert.equal(typeof deny.blockReason, "string");
assert.ok(deny.blockReason.trim().length > 0, "blockReason must be a non-empty string");

const unmapped = await beforeToolCall({ toolName: "brand_new_host_tool", params: {}, toolCallId: "call-2" }, { ...ctx, toolName: "brand_new_host_tool", toolCallId: "call-2" });
assertContract(unmapped, "unmapped");
assert.equal(unmapped.block, true, "unmapped tools stay blocked by default");

// Code Mode exec: the host mirrors `code` into `command` and tags the event. The plugin must still answer within the contract.
const codeMode = await beforeToolCall(
  event({ code: "console.log(1)", command: "console.log(1)" }, { toolKind: "code_mode_exec", toolInputKind: "javascript" }),
  { ...ctx, toolKind: "code_mode_exec", toolInputKind: "javascript" },
);
assertContract(codeMode, "code_mode_exec");
assert.equal(typeof codeMode.block === "boolean" || codeMode.block === undefined, true);

console.log("contract checks passed");
NODE

echo "  ✅ openclaw-aport matches the OpenClaw before_tool_call contract and version metadata agree"
