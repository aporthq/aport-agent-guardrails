# Upgrade Guide

## Upgrading from 0.1.0 to 1.0.0

### Breaking Changes
None - 1.0.0 is the first production release.

### New Features
- OpenClaw plugin with `before_tool_call` enforcement
- API mode support (in addition to local mode)
- Enhanced exec handling with recursive guardrail detection
- Improved error messages with OAP codes

### Migration Steps

**If upgrading from 0.1.0:**

1. Update your installation:
   ```bash
   git pull
   git submodule update --init --recursive
   ```

2. Re-run setup to install plugin:
   ```bash
   ./bin/openclaw
   ```

3. Update OpenClaw config (if using plugin):
   ```yaml
   plugins:
     entries:
       openclaw-aport:
         enabled: true
         config:
           mode: local  # or "api"
           passportFile: ~/.openclaw/passport.json
   ```

4. Verify passport has `allowed_commands`:
   ```bash
   jq '.limits.system.command.execute.allowed_commands' ~/.openclaw/passport.json
   ```
   If empty or missing, re-run passport wizard or add manually.

**No other changes required.**
