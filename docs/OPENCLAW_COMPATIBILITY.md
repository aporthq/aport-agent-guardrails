# OpenClaw Compatibility

**Last reviewed:** 2026-09-24, against the OpenClaw v2026.9.5 source (`src/plugins/hook-types.ts`, `src/plugins/hook-before-tool-call-result.ts`, `src/plugins/hooks.ts`), the live [tool policy hooks doc](https://docs.openclaw.ai/plugins/hooks/tool-policy), the [plugin manifest reference](https://docs.openclaw.ai/plugins/manifest), and the release notes for 2026.8.1 through 2026.9.6. Trigger: framework drift report issue #107.

**Plugin:** `@aporthq/openclaw-aport` ([extensions/openclaw-aport](../extensions/openclaw-aport)).
**Minimum host:** OpenClaw `>=2026.4.11` (`openclaw.install.minHostVersion` and `openclaw.compat.pluginApi` in `extensions/openclaw-aport/package.json`).
**Latest upstream tag at review time:** v2026.9.6 (npm/Gateway package; the macOS app build of 2026.9.6 was withdrawn for a launch crash, which does not affect the plugin).

`tests/unit/test-openclaw-plugin-contract.sh` pins the plugin to the contract described in section 1 and checks that the badge, manifest, package metadata, and this doc agree.

---

## 1. Hook contract: what the plugin uses vs. what v2026.9.5 ships

| Surface | OpenClaw v2026.9.5 | APort plugin | Status |
|---------|--------------------|--------------|--------|
| Registration | Typed hook: `api.on("before_tool_call", handler, { matcher?, priority? })`. `api.registerHook(...)` with an underscore name such as `before_tool_call` logs a warning and is never invoked by the typed runner. | `api.on("before_tool_call", handler)` with no matcher, so every tool call is evaluated. | OK |
| Entry point | `definePluginEntry` from `openclaw/plugin-sdk/plugin-entry`. | Same import. | OK |
| Config access | `api.pluginConfig` (the `plugin-sdk/config-runtime` subpath is deprecated, removal gate 2026-10-01). | `api.pluginConfig`. | OK |
| Event fields | `toolName`, `params`, optional `toolKind`, `toolInputKind`, `runId`, `toolCallId`, `derivedPaths`. | Reads `toolName`, `params`, and `toolCallId` (idempotency seed for API mode). | OK. `toolKind` is not read yet; see section 6. |
| Context fields | `agentId`, `sessionKey`, `sessionId`, `runId`, `abortSignal`, `trace`, `toolName`, `toolKind`, `toolInputKind`, `toolCallId`, `channelId`, `requester` (`channel`, `accountId`, `senderId`, `senderIsOwner`, `roleIds`). | Reads `abortSignal` (passed to the hosted API fetch) and `toolCallId`. | OK |
| Return shape | `{ params?, block?, blockReason?, requireApproval? }`. `block: true` is terminal and skips lower-priority handlers. `block: false` is treated as no decision. | `{}` on allow. `{ block: true, blockReason: "<notice>" }` on deny, on unmapped tools, on integrity failure, and on evaluator error when `failClosed` is true. | OK |
| Hook timeout | 15,000 ms default for `before_tool_call`. Timeout ends the host's await, not plugin work; handlers should honor `ctx.abortSignal`. | API mode passes `abortSignal` to `fetch`. Local mode is synchronous. | OK. Hosted API round trips must stay well under 15 s. |
| Parameter rewrites | Returning `params` rewrites host-owned tool parameters. Rejected for Codex native tool relays. | Never returns `params`. | n/a |
| Approvals | First `requireApproval` wins; `timeoutBehavior` is deprecated because unresolved approvals always deny; `onResolution` receives the typed `PluginApprovalResolution` union. | Not used. | n/a |
| Trusted policy tier | `api.registerTrustedToolPolicy(...)` runs before ordinary hooks. Installed plugins must declare each id in `contracts.trustedToolPolicies`. | Not used. The plugin runs in the ordinary hook tier. | n/a |
| Host policy ordering | Sandbox, exec approvals, owner-only core tools, and channel policies still apply. A hook can veto a tool but cannot grant past host policy or add tools the host omitted. | Same. APort only ever narrows. | OK |

## 2. Manifest and package metadata

`openclaw.plugin.json`:

- `id`, `name`, `description`, `version`, `configSchema`. The schema is inline JSON Schema (not zod) with `additionalProperties: false`; OpenClaw validates plugin config against it before loading plugin code, and a missing or invalid manifest is a plugin error.
- `activation.onStartup: true`. Upstream now says every plugin should set `onStartup` explicitly and that omitting it no longer startup-loads the plugin. The plugin sets it.
- `activation.onCapabilities: ["hook"]`. The accepted values are `provider`, `channel`, `tool`, `hook`.
- `alwaysVerifyEachToolCall` and `guardrailScript` stay in the schema as deprecated compatibility fields so older configs still validate under the strict schema.

`package.json#openclaw`:

- `extensions: ["./index.js"]` declares the native entrypoint.
- `install.minHostVersion: ">=2026.4.11"` is enforced during install and manifest registry loading for non-bundled plugins.
- `compat.pluginApi: ">=2026.4.11"` is enforced during package install. Upstream states that `peerDependencies.openclaw` is npm metadata only and that `compat.pluginApi` is the compatibility contract.
- `build.openclawVersion` is an APort-only field. OpenClaw does not read it.

## 3. Host requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| OpenClaw | `>=2026.4.11` | Floor at which the `block`/`blockReason` return shape and `api.pluginConfig` were verified. Nothing added between 2026.4.11 and 2026.9.6 is required by the plugin. |
| Node (host) | 24.16.0+ on 24.x, or 26.1.0+ | Breaking change in OpenClaw 2026.9.3: Node 22, Node 25, and earlier 24.x/26.x builds are no longer supported by the host. Upgrade Node before OpenClaw. |
| Node (plugin) | `engines.node >=22` | The plugin code itself runs on Node 22+, which keeps it installable on 2026.4.x through 2026.9.2 hosts. The host requirement above wins on newer releases. |

## 4. Upstream changes reviewed, 2026.8.1 through 2026.9.6

| Release | Change | Impact on APort |
|---------|--------|-----------------|
| 2026.8.1 | Deprecation notice: `plugin-sdk-config-runtime-subpath` moves to `api.pluginConfig`; `channel-*` and `infra-runtime` subpaths move to focused imports. | None. The plugin imports only `openclaw/plugin-sdk/plugin-entry` and already uses `api.pluginConfig`. |
| 2026.8.1 | OpenProse plugin removed; `codex/*` model refs migrate to `openai/*`. | None. |
| 2026.8.2 | Same subpath deprecations restated; removal target 2026-09-01. | None. |
| 2026.9.1 | Removal date for those subpaths renewed to 2026-10-01. Plugin install and registry freshness fixes. | None. |
| 2026.9.2 | Untrusted-named prompt-context aliases become removable after 2026-09-08. | None. |
| 2026.9.3 | Node 24.16+/26.1+ required by the host. Execution-policy, approval, and SDK alias breaking changes for plugins that imported `infra-runtime` or the approval helpers. | Host requirement documented above. No plugin code change; none of the retired helpers are imported. |
| 2026.9.4 | Hooks documentation split into task pages, including the tool-policy page the drift checker watches. Plugin manifest and registry types shared. | The watched page changed; the required markers (`before_tool_call`, `matcher`, `timeoutMs`, `block: true`) are all still present. |
| 2026.9.5 | Synchronous plugin storage deprecated in favor of awaited APIs. Plugin manifest hash and permission fixes in builds. | None. The plugin does not use host storage. |
| 2026.9.6 | Code Mode executes plain JavaScript only. Deprecated `channel-message` exports preserved with their existing deadline. Late native hook responses now time out. | None for the hook contract. See section 6 for Code Mode `exec`. |

The tool-policy page itself now documents `toolKind`, `toolInputKind`, `derivedPaths`, `ctx.requester`, the 15 s timeout, the trusted policy tier, and the `resolve_exec_env` and transcript persistence hooks. None of those rename or remove anything the plugin depends on.

## 5. Deprecations checked

None of these are used by the plugin. Listed so the next review does not have to re-derive the answer.

- `requireApproval.timeoutBehavior`: deprecated, will be removed after one release train. Unresolved approvals always deny.
- `requireApproval.onResolution`: now typed as `PluginApprovalResolution` instead of a free-form string.
- SDK subpaths `config-runtime`, `infra-runtime`, `channel-message`, `channel-lifecycle`, `channel-reply-pipeline`: removal gate 2026-10-01.
- SDK subpaths `zod`, `text-runtime`, `channel-logging`, `channel-secret-runtime`, `channel-streaming`, `group-access`, `matrix`, `agent-config-primitives`: retired August 2026. Import `zod` from the `zod` package if ever needed.
- `agent-media-payload` and the `MsgContext Media*` fields: removal gate 2026-10-01.
- Runtime-entry `OpenClawPluginDefinition.kind`: deprecated 2026-07-25; declare `kind` in the manifest instead. The plugin declares no kind.
- `api.on("deactivate")`: removed; use `gateway_stop`.
- `api.registerSessionExtension` and `api.enqueueNextTurnInjection` top-level aliases: deprecated.
- Synchronous plugin keyed stores (`api.runtime.state.openSyncKeyedStore`): gated on the next Plugin SDK major.

## 6. Risks and recommendations

These were not changed in the drift review because they alter enforcement behavior and need their own decision.

1. **Code Mode `exec`.** Outer Code Mode exec calls reach `before_tool_call` with `toolKind: "code_mode_exec"` and `toolInputKind: "javascript"`. The host mirrors the `code` parameter into `command` before the hook runs, so the plugin currently evaluates JavaScript source as a shell string against `system.command.execute` limits (`allowed_commands` prefix match, `blocked_patterns` substring match). That is fail-closed in practice, since most JavaScript will not start with an allowed shell command, but the decision is not meaningful. Recommendation: read `event.toolKind` and either map `code_mode_exec` to a dedicated policy or deny it explicitly with a clear reason.
2. **Hook timeout in API mode.** OpenClaw stops waiting after 15 s. A slow hosted verification would be treated by the host as a timed-out hook. Confirm what the host does with a timed-out `before_tool_call` in your deployment and keep `failClosed: true`.
3. **`ctx.requester`.** Sender identity is now available to hooks. The plugin does not use it. It could feed the passport `owner_id` or a sender allowlist later.
4. **Stale lockfile.** `extensions/openclaw-aport/package-lock.json` still records `peerDependencies.openclaw: ">=2026.2.0"` and a dev install of `openclaw@2026.2.26`, while `package.json` says `>=2026.4.11`. Regenerate the lockfile when the dev dependency is next bumped.
5. **Installer preflight.** `bin/openclaw` does not check the installed OpenClaw version against `minHostVersion`. OpenClaw itself rejects the install on an older host, so the failure is visible, but a preflight message would be friendlier.
6. **Drift markers.** `scripts/framework-drift-check.mjs` could also require `blockReason` and `toolCallId` on the tool-policy page so a rename of either is caught by the weekly run.

## 7. Paths and layout

| Area | Notes |
|------|-------|
| Config and state | `~/.openclaw`. Override with `OPENCLAW_HOME` or `OPENCLAW_STATE_DIR`. `bin/openclaw` defaults to `~/.openclaw` and honors both aliases, with APort-specific overrides (`APORT_OPENCLAW_CONFIG_DIR`, `OPENCLAW_CONFIG_DIR`) taking precedence. |
| Plugin config | `plugins.entries.openclaw-aport.config` in `config.yaml` and `openclaw.json`, written by the installer. |
| Wrappers | `CONFIG_DIR/.skills/aport-*` for manual guardrail and status commands. The plugin does not depend on them. |
| Workspace | `~/.openclaw/workspace` (AGENTS.md, TOOLS.md, SOUL.md). Setup writes the APort rule into `workspace/AGENTS.md`. |
| Messaging | `openclaw message send` and cron use `target`. Our policy tool names (`messaging.message.send`) are our own convention and are unaffected. |

Project-specific home: if `OPENCLAW_HOME` points at a project directory, OpenClaw uses that directory for config, auth, workspace, and skills. That home has its own auth store (`$OPENCLAW_HOME/.openclaw/agents/main/agent/auth-profiles.json`), so configure a provider there (`OPENCLAW_HOME=/path openclaw configure`) or copy auth from the default install on a machine you control.

## 8. Enforcement model

The `before_tool_call` plugin is the deterministic path: OpenClaw calls the plugin before every tool execution, regardless of what the model decides. The AGENTS.md rule that setup writes into the workspace is a best-effort stopgap for installs without the plugin; the model may skip it, forget it, or be prompted to bypass it. Runtime hooks do not trust repository-controlled AGENTS.md passport settings unless the machine owner sets `APORT_TRUST_REPO_POLICY=1`.

Our policy tool names (`system.command.execute`, `messaging.message.send`, and so on) are an APort convention for policy mapping, not OpenClaw tool ids. Renames of OpenClaw's internal tool names only affect `extensions/openclaw-aport/tool-mapping.js`.

---

## 9. References

- Tool policy hooks: https://docs.openclaw.ai/plugins/hooks/tool-policy
- Hook catalog and deprecations: https://docs.openclaw.ai/plugins/hooks
- Plugin manifest: https://docs.openclaw.ai/plugins/manifest
- Manifest vs package.json (`minHostVersion`, `compat.pluginApi`): https://docs.openclaw.ai/plugins/manifest/package-json
- SDK removal timeline: https://docs.openclaw.ai/plugins/sdk-migration/removal-timeline
- Releases: https://github.com/openclaw/openclaw/releases
- Hook types at v2026.9.5: https://github.com/openclaw/openclaw/blob/v2026.9.5/src/plugins/hook-types.ts
- Plugin: [extensions/openclaw-aport/README.md](../extensions/openclaw-aport/README.md)
- Drift process: [FRAMEWORK_DRIFT_WATCH.md](FRAMEWORK_DRIFT_WATCH.md)
