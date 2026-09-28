# Reuse a passport across frameworks

Each framework installer keeps its passport in its own state directory (`~/.claude/aport`, `~/.cursor/aport`, `~/.aport/codex/aport`, and so on; see `get_config_dir` in `bin/lib/config.sh`). Before this change every install created a new passport, so one person with three tools ended up with three passports to keep in step.

The installer now looks for passports the other frameworks already have on the device and offers them before the usual hosted or local choice.

## Interactive

```
  Existing APort passports on this device:
    1. cursor (local, ~/.cursor/aport/passport.json)
    2. codex (hosted, ap_1234567890abcdef1234567890abcdef)
    n. Create a new passport for claude-code

  Reuse one? [1-2/n]:
```

Picking a hosted entry configures the install with that `agent_id`, plus the API key and URL recorded in the source framework's `guardrail-mode.env`. Picking a local entry copies the `passport.json` into the new framework's `aport/` directory (mode 600) and skips the wizard. Answering `n` continues to the normal `1/2/3` menu. The menu never offers to copy over a passport the framework already has; on a rerun only hosted entries are listed, and the installer's own overwrite prompt owns the local file.

## Non-interactive

Nothing is reused unless asked; a CI install never guesses.

```bash
npx @aporthq/aport-agent-guardrails claude-code --non-interactive --reuse-from=cursor
npx @aporthq/aport-agent-guardrails codex --non-interactive --reuse-from=~/.cursor/aport/passport.json
npx @aporthq/aport-agent-guardrails goose --non-interactive --reuse-from=ap_1234567890abcdef1234567890abcdef
APORT_REUSE_PASSPORT_FROM=cursor npx @aporthq/aport-agent-guardrails gemini-cli --non-interactive
```

`--reuse-from` accepts a framework name (the first passport that framework has), a path to a `passport.json`, or a hosted agent id. With `--mode=local` only local passports are offered or accepted. An explicit `--reuse-from` beats an `APORT_AGENT_ID` inherited from the environment and the framework's own saved config; combined with `--agent-id` it is refused. When it replaces a local passport that is already there, the old file is kept as `passport.json.bak`. The flag belongs to the installer; `aport-agent-guardrails mode` rejects it.

## What is and is not shared

A local passport is copied, not linked. Editing one copy does not change the others; that is deliberate, since a framework's tool coverage may need its own `allowed_commands` or `blocked_paths`. A hosted passport is shared by id, so a change in the dashboard applies everywhere at once.

The schema is framework independent (`spec_version: oap/1.0`). One caveat: the OpenClaw installer post-processes its passport to merge default `allowed_commands`; a passport created by another framework and reused for OpenClaw may need that list widened.

## Implementation

`bin/lib/passport-reuse.sh`: `aport_list_device_passports`, `aport_apply_reused_passport`, `aport_resolve_reuse_ref`, `aport_maybe_reuse_device_passport`. Called from `aport_maybe_configure_hosted_passport` in `bin/lib/quick-hosted.sh`, so every framework installer gets it. Callers skip the wizard when `APORT_PASSPORT_REUSED=1` (`setup_from_agentsmd_or_wizard`, `bin/frameworks/generic.sh`, `bin/openclaw`). Tests: `tests/unit/test-passport-reuse.sh`.
