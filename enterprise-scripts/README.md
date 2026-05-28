# APort Enterprise Device Scripts

Generic **install / enforce / uninstall** scripts for IT teams to deploy APort guardrails on employee devices where an agent framework (Claude Code, Cursor, OpenClaw, etc.) is already in use.

**Supported platforms:** macOS, Linux, and Windows.

**Requirements on each device:** Node.js 18+, npm/npx, and `curl`.

The same workflow runs on every OS: register the device with APort, mint a narrow runtime setup key, then invoke `npx @aporthq/aport-agent-guardrails <framework>` in API mode.

## Scripts

| File | Command | Purpose |
| --- | --- | --- |
| `aport-device-deploy.sh` / `.ps1` | `install` | Initial install |
| `aport-device-enforce.sh` / `.ps1` | `enforce` | Re-check state and hooks; reinstall if needed |
| `aport-device-uninstall.sh` / `.ps1` | `uninstall` | Remove hooks and local state |
| `aport-device-core.mjs` | — | Cross-platform implementation (Node.js) |
| `aport-device-lib.sh` | — | Unix launcher only (exec Node core) |

On **Windows**, run the `.ps1` scripts in PowerShell (or set the same environment variables and run `node aport-device-core.mjs install`). On **macOS and Linux**, use the `.sh` scripts (Bash).

## How it works

1. IT edits the **configuration block** at the top of the deploy/enforce script (API key, template ID, framework).
2. The script calls `aport-device-core.mjs`, which:
   - Resolves the target user and home directory (or uses `APORT_TARGET_USER` / `APORT_TARGET_HOME`).
   - Derives a stable `tenant_ref` from device ID + user + framework + template.
   - Calls `GET /api/check-instance` to avoid duplicate passport instances.
   - Creates an instance and mints a read-scoped setup key when needed.
   - Runs `npx @aporthq/aport-agent-guardrails <framework> <agent_id> --mode=api`.
   - Writes `guardrail-mode.env` under the framework config directory (e.g. `~/.claude/aport/`).

Enrollment API keys are **not** stored for hook runtime; only the minted setup key is persisted.

### API keys: enrollment (`issue`) vs runtime (`read`)

This matches the hosted developer flow on `/agents?download=<passport_id>` (`PassportDownloadUI` in the agent-passport web app):

| Key | How you get it | Scopes | Used for |
| --- | --- | --- | --- |
| **Enrollment key** | Org dashboard → API keys → create with **`issue` only** (recommended) | `issue` | `POST /api/passports/{template_id}/instances`, `POST /api/passports/{agent_id}/setup-key` |
| **Runtime setup key** | Minted by the device script (or “Create fresh setup key” on the download page) | **`read` only** (server-enforced) | `npx @aporthq/aport-agent-guardrails … --mode=api` and hook verification |

**Download page (single developer):** Passport instance already exists. An authenticated owner clicks **Create fresh setup key** → `POST /api/passports/{agent_id}/setup-key` → plaintext **`read`** key shown once → pasted into the `npx` command.

**Enterprise script (many devices):** IT embeds an org **`issue`** key in the deploy script. The script creates (or reuses) a **template instance** per device, calls the same **`setup-key`** endpoint, and writes the minted **`read`** key to `state.env` and `~/.claude/aport/guardrail-mode.env` (or equivalent). Hooks never use the enrollment key.

The setup-key API **always** creates `scopes: ["read"]` and does not accept custom scopes (`agent-passport`: `functions/api/passports/[agent_id]/setup-key.ts`). Policy verification requires `read`; an `issue` key must not be placed in `guardrail-mode.env`.

`GET /api/check-instance` is **unauthenticated** (lookup only); instance creation and setup-key minting require the enrollment bearer token.

## Configuration

| Variable | Required | Purpose |
| --- | --- | --- |
| `APORT_API_KEY` | Deploy/enforce | Org enrollment key with **`issue`** scope (`apk_…`); not the runtime setup key |
| `APORT_TEMPLATE_ID` | Deploy/enforce | Template passport ID (`ap_…` / `apt_…`); script creates per-device **instances** (`agt_inst_…` / `ap_…`) |
| `APORT_FRAMEWORK` | All | e.g. `claude-code`, `cursor` |
| `APORT_TARGET_USER` | No | Account that runs the agent (auto-detected if unset) |
| `APORT_TARGET_HOME` | No | Profile/home path (auto-detected if unset) |
| `APORT_DEVICE_ID` | No | Stable device ID (serial / machine-id / hostname) |
| `APORT_STATE_DIR` | No | Where install state is stored (OS default if unset) |
| `DISABLE_DEVICE_INFO` | No | Set to `1` to skip device metadata on create |
| `APORT_SKIP_USER_SWITCH` | No | Set to `1` when the script already runs as the target user |

### Default state directories

| OS | Default `APORT_STATE_DIR` |
| --- | --- |
| macOS | `/Library/Application Support/APort/<framework>` |
| Linux | `/var/lib/aport/<framework>` |
| Windows | `%ProgramData%\APort\<framework>` |

### Running as administrator

If the script runs as **root** (Linux/macOS) or **Administrator** (Windows), set `APORT_TARGET_USER` and `APORT_TARGET_HOME` to the employee account that runs Claude Code or Cursor. On Unix, the core uses `sudo -u` for `npx` when appropriate; on Windows, run the script in a user context or use the `.ps1` launcher under that user.

For `curl | bash` on Linux/macOS, run the **bash process** as root/admin:

```bash
export APORT_API_KEY="apk_..."
export APORT_TEMPLATE_ID="ap_..."
export APORT_FRAMEWORK="claude-code"

curl -fsSL "https://api.aport.io/enterprise/scripts/deploy?version=1.0.29" | sudo -E bash
```

Do **not** use `sudo curl ... | bash`; that only runs `curl` as root and leaves the installer running as the current user, which cannot write the default administrator-owned state directory.

## Release bundles

On each tag `v*`, CI produces self-contained Unix bundles and ships `aport-device-core.mjs` plus PowerShell entrypoints:

| Artifact | Purpose |
| --- | --- |
| `aport-device-deploy.bundled.sh` | Single-file install (config + inlined Node core) |
| `aport-device-enforce.bundled.sh` | Single-file enforce |
| `aport-device-uninstall.bundled.sh` | Single-file uninstall |
| `aport-device-core.mjs` | Shared core for Windows / custom wrappers |
| `aport-device-*.ps1` | Windows entrypoints |
| `enterprise-scripts-manifest.json` | SHA-256 checksums |

### Download (auditable)

The API serves **bundled** scripts (config header + inlined `aport-device-core.mjs`). They are safe for `curl | bash`.

Do **not** pipe the thin repo scripts (`enterprise-scripts/aport-device-*.sh`) through bash; those require `aport-device-lib.sh` on disk.

```bash
curl -fsSL "https://api.aport.io/enterprise/scripts?version=1.0.29"
curl -fsSL "https://api.aport.io/enterprise/scripts/deploy?version=1.0.29" -o /tmp/aport-deploy.sh
shasum -a 256 -c <<< "<sha256>  /tmp/aport-deploy.sh"
sudo -E bash /tmp/aport-deploy.sh
```

Set `APORT_API_KEY` (issue scope) and `APORT_TEMPLATE_ID` before running, or edit the config block in a saved copy of the bundled script.

### Local bundle (maintainers)

```bash
./scripts/bundle-enterprise-scripts.sh
# -> dist/enterprise-scripts/
```

## Security notes

- **Enrollment key** (`APORT_API_KEY` with `issue` scope) is used only during install/enforce API calls; the script persists a **narrow runtime setup key** for hooks, not the enrollment key.
- **State directory** (`APORT_STATE_DIR`) is created mode `0700`; `state.env` is mode `0600`. Restrict access to administrators on shared systems.
- **`guardrail-mode.env`** in the user profile contains the runtime API key (mode `0600`). Treat like a credential file.
- Set **`APORT_TARGET_USER`** explicitly when running as root/Administrator so the installer never targets the wrong account.
- Verify **SHA-256** from `enterprise-scripts-manifest.json` before executing downloaded bundles.

## Local development

Edit shared logic in **`aport-device-core.mjs`**. Unix `.sh` files only export configuration and invoke the core.

```bash
export APORT_API_KEY=apk_...
export APORT_TEMPLATE_ID=ap_...
export APORT_FRAMEWORK=claude-code
export APORT_SKIP_USER_SWITCH=1
export APORT_TARGET_USER="$USER"
export APORT_TARGET_HOME="$HOME"
export APORT_STATE_DIR="/tmp/aport-test-state"
./enterprise-scripts/aport-device-deploy.sh
```
