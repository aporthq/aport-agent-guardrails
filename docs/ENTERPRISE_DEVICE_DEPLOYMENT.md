# Enterprise Device Deployment

Use this guide when an IT team wants to deploy APort guardrails to one or many developer machines through a device-management tool, remote shell, or manual test run.

The deployment scripts are generic. They work for MDM tools, endpoint-management tools, remote shell runners, or a saved script executed by an administrator.

## What Gets Installed

The deploy script:

1. Identifies the target device and user.
2. Reuses an existing passport instance for that device when one already exists.
3. Creates a new instance from the template passport only when needed.
4. Mints a narrow runtime setup key for that instance.
5. Runs `npx @aporthq/aport-agent-guardrails <framework> <agent_id> --mode=api`.
6. Writes the framework hook/config for the target user.

The org enrollment key is not stored for runtime. Hooks use the minted runtime key.

## Requirements

Each target device needs:

- Node.js 18+
- npm/npx
- curl
- The target agent framework installed or available to the developer, for example Claude Code or Cursor

APort setup requires:

- A template passport in the APort org.
- An org API key with `issue` scope. Use the narrowest key available; do not use a broad admin key.
- The framework name, for example `claude-code` or `cursor`.

## Recommended First Test

Run the deploy script on one developer test machine first.

```bash
export APORT_API_KEY="apk_..."
export APORT_TEMPLATE_ID="ap_..."
export APORT_FRAMEWORK="claude-code"

curl -fsSL "https://api.aport.io/enterprise/scripts/deploy?version=1.0.29" | bash
```

If the script runs as `root`, set the developer account explicitly:

```bash
export APORT_TARGET_USER="developer"
export APORT_TARGET_HOME="/Users/developer"
```

For Linux, `APORT_TARGET_HOME` is usually `/home/<user>`.

## Script Commands

| Command | URL | Purpose |
| --- | --- | --- |
| Deploy | `https://api.aport.io/enterprise/scripts/deploy?version=1.0.29` | Initial install or repair |
| Enforce | `https://api.aport.io/enterprise/scripts/enforce?version=1.0.29` | Validate state and reinstall if the hook/config is missing |
| Uninstall | `https://api.aport.io/enterprise/scripts/uninstall?version=1.0.29` | Remove APort-owned wiring and local state |

Use `deploy` for the first test. Use `enforce` as the recurring compliance script. Use `uninstall` only for approved removal.

## Configuration Variables

| Variable | Required | Description |
| --- | --- | --- |
| `APORT_API_KEY` | Deploy/enforce | Org enrollment key with `issue` scope |
| `APORT_TEMPLATE_ID` | Deploy/enforce | Template passport ID to instantiate per device/user |
| `APORT_FRAMEWORK` | All | `claude-code`, `cursor`, `openclaw`, `langchain`, `crewai`, `deerflow`, or `n8n` |
| `APORT_API_URL` | No | Defaults to `https://api.aport.io` |
| `APORT_TARGET_USER` | No | Developer account that runs the agent framework |
| `APORT_TARGET_HOME` | No | Home/profile directory for the target user |
| `APORT_DEVICE_ID` | No | Stable device identifier; auto-detected when unset |
| `APORT_STATE_DIR` | No | Override local system state directory |
| `DISABLE_DEVICE_INFO` | No | Set to `1` to skip device metadata collection |

## How Device Identity Works

The script derives a stable `tenant_ref` from:

- device ID
- target username
- framework
- template passport ID

This prevents duplicate passport instances when the deploy or enforce script runs again on the same device for the same user/framework/template.

Device ID is auto-detected from:

- macOS: hardware serial number
- Linux: machine ID
- Windows: BIOS serial number
- fallback: hostname

Set `APORT_DEVICE_ID` if the device-management system has a stronger stable identifier.

## Verify The Install

After deploy:

1. Open APort and switch to the org context.
2. Open the template passport.
3. Confirm an instance exists for the test device.
4. Ask the developer to run a normal Claude Code or Cursor task.
5. Confirm allow/deny decisions appear in APort audit.

For a pilot, use a test repository and prompts that exercise both normal developer actions and blocked actions, for example safe repo inspection, test execution, destructive cleanup, privileged commands, and sensitive file reads.

## Enforcement Script

Run this as the recurring compliance check:

```bash
export APORT_API_KEY="apk_..."
export APORT_TEMPLATE_ID="ap_..."
export APORT_FRAMEWORK="claude-code"

curl -fsSL "https://api.aport.io/enterprise/scripts/enforce?version=1.0.29" | bash
```

`enforce` reuses existing local state when present. If the framework hook/config is missing, it reinstalls without creating a duplicate passport instance.

## Uninstall

Use only for approved removal:

```bash
export APORT_FRAMEWORK="claude-code"

curl -fsSL "https://api.aport.io/enterprise/scripts/uninstall?version=1.0.29" | bash
```

Uninstall removes APort-owned framework wiring and local APort state for the selected framework. It does not delete the passport or audit records from APort.

## Auditable Download

For stricter change-control, fetch the manifest and verify the script hash before execution:

```bash
curl -fsSL "https://api.aport.io/enterprise/scripts?version=1.0.29"
curl -fsSL "https://api.aport.io/enterprise/scripts/deploy?version=1.0.29" -o /tmp/aport-deploy.sh
shasum -a 256 /tmp/aport-deploy.sh
bash /tmp/aport-deploy.sh
```

Compare the `shasum` output to the manifest’s `sha256` value.

## More Detail

The source scripts and implementation notes are in [`enterprise-scripts/README.md`](../enterprise-scripts/README.md).
