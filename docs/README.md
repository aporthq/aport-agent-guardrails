# APort Integration for OpenClaw

> **Pre-action authorization guardrails** using Open Agent Passport (OAP) v1.0 specification

This directory contains a complete implementation of APort-style pre-action authorization for OpenClaw, supporting both **local file-based** and **cloud API** approaches.

---

## Quick Start

### 1. Install Dependencies

```bash
# Install jq (required for JSON parsing)
brew install jq  # macOS
# or
apt-get install jq  # Linux
```

### 2. Copy Files to OpenClaw Directory

```bash
# Create OpenClaw config directory
mkdir -p ~/.openclaw/.skills

# Copy passport template
cp passport.json ~/.openclaw/passport.json

# Copy guardrail script
cp aport-guardrail.sh ~/.openclaw/.skills/aport-guardrail.sh
chmod +x ~/.openclaw/.skills/aport-guardrail.sh

# Copy AGENTS.md example (merge into your existing AGENTS.md)
cat AGENTS.md.example >> ~/.openclaw/AGENTS.md
```

### 3. Customize Passport

Edit `~/.openclaw/passport.json` to match your needs:

```bash
vim ~/.openclaw/passport.json
```

Key settings:
- `capabilities`: What your agent can do
- `limits`: Operational limits (PR size, commands, recipients, etc.)
- `status`: Set to `"active"` to enable

### 4. Test It

```bash
# Test with a git PR creation
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{"repo":"test","branch":"feature/test","files_changed":5}'

# Check decision
cat ~/.openclaw/decision.json

# View audit log
tail ~/.openclaw/audit.log
```

---

## Architecture

### Local File-Based (Current Implementation)

```
┌─────────────┐
│  OpenClaw   │
│   Agent     │
└──────┬──────┘
       │
       │ 1. Tool execution requested
       ▼
┌─────────────────────┐
│  AGENTS.md Rule     │
│  (Pre-action check) │
└──────┬──────────────┘
       │
       │ 2. Call guardrail script
       ▼
┌─────────────────────┐
│ aport-guardrail.sh   │
│ (Policy Evaluator)   │
└──────┬───────────────┘
       │
       ├─► 3a. Check kill-switch
       ├─► 3b. Load passport.json
       ├─► 3c. Evaluate policy limits
       └─► 3d. Write decision.json
       │
       ▼
┌─────────────────────┐
│  decision.json       │
│  {allow: true/false}│
└──────┬──────────────┘
       │
       │ 4. Read decision
       ▼
┌─────────────────────┐
│  Execute or Deny    │
└─────────────────────┘
```

### Cloud API (Future)

Same flow, but `aport-guardrail.sh` calls APort API instead of local evaluation:

```bash
curl -X POST https://api.aport.io/api/verify/policy/code.repository.merge.v1 \
  -H "Content-Type: application/json" \
  -d '{"passport_id": "...", "context": {...}}'
```

---

## Files

| File | Purpose | Location |
|------|---------|----------|
| `passport.json` | OAP v1.0 passport with capabilities and limits | `~/.openclaw/passport.json` |
| `aport-guardrail.sh` | Policy evaluation script | `~/.openclaw/.skills/aport-guardrail.sh` |
| `AGENTS.md.example` | Example agent rules | Merge into `~/.openclaw/AGENTS.md` |
| `decision.json` | Latest authorization decision | `~/.openclaw/decision.json` (auto-generated) |
| `audit.log` | Immutable action log | `~/.openclaw/audit.log` (auto-generated) |
| `kill-switch` | Emergency stop file | `~/.openclaw/kill-switch` (create to activate) |

---

## Usage Examples

### Allow a Git PR

```bash
# Context: Creating PR with 10 files changed
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{"repo":"open-work","branch":"feature/auth","files_changed":10}'

# Check result
cat ~/.openclaw/decision.json
# {"allow": true, "decision_id": "550e8400-...", "policy": "code.repository.merge"}
```

### Deny a Dangerous Command

```bash
# Context: Trying to run rm -rf
~/.openclaw/.skills/aport-guardrail.sh exec.run '{"command":"rm -rf /tmp"}'

# Check result
cat ~/.openclaw/decision.json
# {"allow": false, "reason": "blocked_pattern", "message": "Command contains blocked pattern: rm -rf"}
```

### Activate Kill Switch

```bash
# Block all actions
touch ~/.openclaw/kill-switch

# Try any action - will be denied
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{"repo":"test","files_changed":1}'

# Check result
cat ~/.openclaw/decision.json
# {"allow": false, "reason": "kill_switch_active"}

# Resume actions
rm ~/.openclaw/kill-switch
```

---

## Policy Packs Supported

### `code.repository.merge`
- **Tools**: `git.create_pr`, `git.merge`, `git.push`
- **Limits**: PR size, daily PRs, allowed repos/branches
- **Context**: `repo`, `branch`, `files_changed`, `lines_added`

### `system.command.execute`
- **Tools**: `exec.run`, `exec.*`, `system.*`
- **Limits**: Allowed commands, blocked patterns, execution time
- **Context**: `command`, `args`, `cwd`

### `messaging.message.send`
- **Tools**: `message.send`, `message.*`
- **Limits**: Messages per minute/day, allowed recipients
- **Context**: `recipient`, `channel`, `content_length`

### `data.export`
- **Tools**: `database.write`, `data.export`
- **Limits**: Max rows, PII restrictions, allowed collections
- **Context**: `collection`, `operation`, `rows_affected`

---

## Customization

### Add New Policy Pack

1. Edit `aport-guardrail.sh`:
   - Add tool mapping in `case` statement
   - Add policy evaluation logic

2. Update `passport.json`:
   - Add capability to `capabilities` array
   - Add limits to `limits` object

3. Update `AGENTS.md`:
   - Add tool to "Effectful Tools" list
   - Add context example

### Modify Limits

Edit `~/.openclaw/passport.json`:

```json
{
  "limits": {
    "code.repository.merge": {
      "max_pr_size_kb": 1000,  // Increase from 500
      "max_prs_per_day": 20    // Increase from 10
    }
  }
}
```

---

## Migration to Cloud API

When APort cloud API is ready, modify `aport-guardrail.sh`:

```bash
# Replace local evaluation with API call
RESPONSE=$(curl -s -X POST "https://api.aport.io/api/verify/policy/$POLICY" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $APORT_API_KEY" \
  -d "{\"passport_id\": \"$PASSPORT_ID\", \"context\": $CONTEXT_JSON}")

echo "$RESPONSE" | jq . > "$DECISION_FILE"
```

The interface remains the same - just swap the implementation.

---

## Troubleshooting

### "jq not found"
```bash
brew install jq  # macOS
```

### "Passport not found"
```bash
cp passport.json ~/.openclaw/passport.json
```

### "Decision file not created"
Check script permissions:
```bash
chmod +x ~/.openclaw/.skills/aport-guardrail.sh
```

### "All actions denied"
1. Check passport status: `jq .status ~/.openclaw/passport.json`
2. Check kill switch: `ls ~/.openclaw/kill-switch`
3. Check audit log: `tail ~/.openclaw/audit.log`

---

## References

- [APort Integration Guide](../APORT-OPENCLAW-INTEGRATION.md) - Full integration documentation
- [OAP v1.0 Specification](https://github.com/aporthq/aport-spec)
- [APort Goose Architecture](https://github.com/aporthq/.github/blob/main/profile/APORT_GOOSE_ARCHITECTURE.md)
- [OpenAI Agents Python Issue #2022](https://github.com/openai/openai-agents-python/issues/2022)

---

## License

MIT License - See LICENSE file
