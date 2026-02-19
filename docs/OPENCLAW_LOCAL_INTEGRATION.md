# OpenClaw Local Integration Guide

**Get OpenClaw secure with APort in under 5 minutes - No cloud required!**

This guide shows you how to integrate APort's policy enforcement with OpenClaw using **local passport and policy files**. Perfect for individual developers who want pre-action authorization without cloud dependencies.

---

## 🎯 What You'll Get

✅ **Pre-action verification** - Commands and MCP tools checked before execution  
✅ **Graduated controls** - Set limits (max commands, blocked patterns, etc.)  
✅ **Security patterns** - Built-in protection against injection, path traversal, etc.  
✅ **Audit logging** - All decisions logged locally  
✅ **Kill switch** - Emergency stop via local file  

**No cloud API needed** - Everything works offline!

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Start APort API Server

**Use the agent-passport API server** - it runs locally and provides the full evaluation engine.

```bash
# Start agent-passport server (from agent-passport repo)
cd /path/to/agent-passport
npm run dev
# Server runs on https://api.aport.io (or your self-hosted API)
```

**Note:** The evaluation engine runs in the `agent-passport` server. This guardrail repo provides examples and SDKs that call the API.

---

### Step 2: Create Local Passport

Create `~/.openclaw/passport.json`:

```json
{
  "agent_id": "ap_openclaw_local_001",
  "name": "OpenClaw Local Agent",
  "controller_type": "person",
  "description": "Local OpenClaw agent with APort policy enforcement",
  "owner_id": "user@example.com",
  "owner": "Your Name",
  "role": "Developer",
  "capabilities": [
    { "id": "system.command.execute", "description": "System command execution" },
    { "id": "mcp.tool.execute", "description": "MCP tool execution" },
    { "id": "agent.session.create", "description": "Agent session creation" },
    { "id": "agent.tool.register", "description": "Tool registration" }
  ],
  "limits": {
    "allowed_commands": ["npm", "git", "node", "python", "make", "curl"],
    "max_execution_time": 300,
    "blocked_patterns": ["rm -rf", "sudo"],
    "allowed_servers": ["https://mcp.github.com", "https://mcp.openai.com"],
    "max_calls_per_minute": 60,
    "allowed_tools": ["github.pull_requests.create", "github.issues.create"],
    "max_sessions_per_day": 10,
    "max_tools_per_session": 50
  },
  "regions": ["US"],
  "status": "active",
  "assurance_level": "L2",
  "contact": "user@example.com",
  "version": "1.0.0",
  "created_at": "2026-02-08T00:00:00Z",
  "expires_at": "2026-03-08T00:00:00Z"
}
```

---

### Step 3: Create Policy Files

Copy the 4 OpenClaw policies to `~/.openclaw/policies/`:

```bash
mkdir -p ~/.openclaw/policies

# Copy from agent-passport repo
cp /Users/uchi/Downloads/projects/agent-passport/policies/system.command.execute.v1/policy.json ~/.openclaw/policies/
cp /Users/uchi/Downloads/projects/agent-passport/policies/mcp.tool.execute.v1/policy.json ~/.openclaw/policies/
cp /Users/uchi/Downloads/projects/agent-passport/policies/agent.session.create.v1/policy.json ~/.openclaw/policies/
cp /Users/uchi/Downloads/projects/agent-passport/policies/agent.tool.register.v1/policy.json ~/.openclaw/policies/
```

---

### Step 4: Verify API Server is Running

Make sure the agent-passport server is running:

```bash
# Check if server is running
curl https://api.aport.io/health || echo "API not reachable - check APORT_API_URL or network"
```

The API server provides the full evaluation engine - no need to copy code!

---

## 📋 Integration Examples

### Example 1: Command Execution Verification

**Before executing any command in OpenClaw:**

**Option A: Using Local Server (Recommended)**

```python
import subprocess
import json
import os
import requests

def verify_command(command, args=None):
    """Verify command execution against APort policy via local server"""
    passport_file = os.path.expanduser("~/.openclaw/passport.json")
    api_base = os.getenv("APORT_API_BASE", "https://api.aport.io")
    
    # Load agent_id from passport
    with open(passport_file) as f:
        passport = json.load(f)
        agent_id = passport["agent_id"]
    
    # Build context
    context = {
        "agent_id": agent_id,
        "policy_id": "system.command.execute.v1",
        "command": command,
        "args": args or []
    }
    
    # Call verification API (local server)
    response = requests.post(
        f"{api_base}/api/verify/policy/system.command.execute.v1",
        json={"context": context}
    )
    
    decision = response.json().get("decision") or response.json()
    
    if not decision.get("allow"):
        reasons = decision.get("reasons", [])
        reason_text = ", ".join([r.get("message", "") for r in reasons])
        raise PermissionError(f"Policy denied: {reason_text}")
    
    return decision
```

**Option B: Using Evaluation Engine Directly (Advanced)**

```python
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src', 'evaluator'))

from generic_evaluator import evaluateGenericPolicyV2
import json

# Mock env for local use (no KV/D1 needed for basic evaluation)
class MockEnv:
    pass

def verify_command(command, args=None):
    """Verify command execution using evaluation engine directly"""
    passport_file = os.path.expanduser("~/.openclaw/passport.json")
    
    # Load passport
    with open(passport_file) as f:
        passport = json.load(f)
    
    # Build context
    context = {
        "command": command,
        "args": args or []
    }
    
    # Evaluate policy directly (no API call needed)
    decision = await evaluateGenericPolicyV2(
        MockEnv(),  # Mock env - no DB access needed for basic checks
        "system.command.execute.v1",
        passport,
        context
    )
    
    if not decision.get("allow"):
        reasons = decision.get("reasons", [])
        reason_text = ", ".join([r.get("message", "") for r in reasons])
        raise PermissionError(f"Policy denied: {reason_text}")
    
    return decision
```

# Usage in OpenClaw
def execute_command(command, args=None):
    # Pre-action verification
    verify_command(command, args)
    
    # Execute command (if allowed)
    subprocess.run([command] + (args or []))
```

**Test it:**

```python
# This should be ALLOWED
execute_command("npm", ["install"])

# This should be DENIED (blocked pattern)
try:
    execute_command("rm", ["-rf", "/"])
except PermissionError as e:
    print(f"Blocked: {e}")

# This should be DENIED (not in allowlist)
try:
    execute_command("sudo", ["apt", "update"])
except PermissionError as e:
    print(f"Blocked: {e}")
```

---

### Example 2: MCP Tool Verification

**Before calling any MCP tool:**

```python
def verify_mcp_tool(server, tool, parameters):
    """Verify MCP tool execution against APort policy"""
    passport_file = os.path.expanduser("~/.openclaw/passport.json")
    api_base = os.getenv("APORT_API_BASE", "https://api.aport.io")
    
    # Load agent_id from passport
    with open(passport_file) as f:
        passport = json.load(f)
        agent_id = passport["agent_id"]
    
    # Build context
    context = {
        "agent_id": agent_id,
        "policy_id": "mcp.tool.execute.v1",
        "server": server,
        "tool": tool,
        "parameters": parameters
    }
    
    # Call verification API
    import requests
    response = requests.post(
        f"{api_base}/api/verify/policy/mcp.tool.execute.v1",
        json={"context": context}
    )
    
    decision = response.json().get("decision") or response.json()
    
    if not decision.get("allow"):
        reasons = decision.get("reasons", [])
        reason_text = ", ".join([r.get("message", "") for r in reasons])
        raise PermissionError(f"Policy denied: {reason_text}")
    
    return decision

# Usage in OpenClaw MCP integration
def call_mcp_tool(server, tool, parameters):
    # Pre-action verification
    verify_mcp_tool(server, tool, parameters)
    
    # Call MCP tool (if allowed)
    # ... your MCP client code here ...
    pass
```

**Test it:**

```python
# This should be ALLOWED (server in allowlist, tool allowed)
call_mcp_tool(
    "https://mcp.github.com",
    "github.pull_requests.create",
    {"repo": "test/repo", "title": "Test PR"}
)

# This should be DENIED (server not in allowlist)
try:
    call_mcp_tool(
        "https://evil-server.com",
        "malicious.tool",
        {}
    )
except PermissionError as e:
    print(f"Blocked: {e}")

# This should be DENIED (tool not allowed)
try:
    call_mcp_tool(
        "https://mcp.github.com",
        "github.repos.delete",
        {"repo": "test/repo"}
    )
except PermissionError as e:
    print(f"Blocked: {e}")
```

---

### Example 3: Complete OpenClaw Integration

**Wrap OpenClaw's tool execution:**

```python
# .openclaw/extensions/aport.py

import os
import json
import requests
from typing import Dict, Any, Optional

class APortGuardrail:
    """APort policy enforcement for OpenClaw"""
    
    def __init__(self, passport_file: Optional[str] = None, api_base: Optional[str] = None):
        self.passport_file = passport_file or os.path.expanduser("~/.openclaw/passport.json")
        self.api_base = api_base or os.getenv("APORT_API_BASE", "https://api.aport.io")
        self._agent_id = None
    
    @property
    def agent_id(self) -> str:
        """Lazy load agent_id from passport"""
        if self._agent_id is None:
            with open(self.passport_file) as f:
                passport = json.load(f)
                self._agent_id = passport["agent_id"]
        return self._agent_id
    
    def verify(self, policy_id: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Verify action against policy"""
        full_context = {
            "agent_id": self.agent_id,
            "policy_id": policy_id,
            **context
        }
        
        response = requests.post(
            f"{self.api_base}/api/verify/policy/{policy_id}",
            json={"context": full_context}
        )
        
        decision = response.json().get("decision") or response.json()
        
        if not decision.get("allow"):
            reasons = decision.get("reasons", [])
            reason_text = ", ".join([r.get("message", "") for r in reasons])
            raise PermissionError(f"Policy denied: {reason_text}")
        
        return decision
    
    def verify_command(self, command: str, args: list = None) -> Dict[str, Any]:
        """Verify command execution"""
        return self.verify("system.command.execute.v1", {
            "command": command,
            "args": args or []
        })
    
    def verify_mcp_tool(self, server: str, tool: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Verify MCP tool execution"""
        return self.verify("mcp.tool.execute.v1", {
            "server": server,
            "tool": tool,
            "parameters": parameters
        })
    
    def verify_session_create(self, session_config: Dict[str, Any]) -> Dict[str, Any]:
        """Verify agent session creation"""
        return self.verify("agent.session.create.v1", session_config)
    
    def verify_tool_register(self, tool_config: Dict[str, Any]) -> Dict[str, Any]:
        """Verify tool registration"""
        return self.verify("agent.tool.register.v1", tool_config)


# Usage in OpenClaw agent
guardrail = APortGuardrail()

# Before executing command
try:
    guardrail.verify_command("npm", ["install"])
    # Execute command...
except PermissionError as e:
    print(f"Command blocked: {e}")

# Before calling MCP tool
try:
    guardrail.verify_mcp_tool(
        "https://mcp.github.com",
        "github.pull_requests.create",
        {"repo": "test/repo"}
    )
    # Call MCP tool...
except PermissionError as e:
    print(f"MCP tool blocked: {e}")
```

---

## 🔒 Security Features

### Built-in Security Patterns

The `system.command.execute.v1` policy includes **40+ built-in security patterns** that are **always enforced**, even if not in your `blocked_patterns`:

✅ **Command Injection** - Blocks `;`, `|`, `&`, `` ` ``, `$()`, `&&`, `||`  
✅ **Script Execution** - Blocks `bash -c`, `python -c`, `node -e`  
✅ **Path Traversal** - Blocks `../`, `..\`  
✅ **Privilege Escalation** - Blocks `sudo`, `su`, `doas`  
✅ **Dangerous Operations** - Blocks `rm -rf`, `format`, `dd if=`  
✅ **Environment Files** - Blocks `.env` file access  
✅ **Config Files** - Blocks `nginx.conf`, `apache2.conf` access  
✅ **Credentials** - Blocks AWS credentials, SSH keys, etc.  
✅ **Network Exfiltration** - Blocks `curl`, `wget` with URLs  
✅ **And 30+ more patterns...**

**These cannot be bypassed** - even if you add commands to `allowed_commands`, dangerous patterns are still blocked!

---

## 📊 Policy Mapping

| OpenClaw Action | Policy Pack | Policy File |
|----------------|-------------|-------------|
| `exec.run("npm install")` | `system.command.execute.v1` | `system.command.execute.v1/policy.json` |
| `mcp.call("github.pull_requests.create")` | `mcp.tool.execute.v1` | `mcp.tool.execute.v1/policy.json` |
| `agent.create_session()` | `agent.session.create.v1` | `agent.session.create.v1/policy.json` |
| `agent.register_tool()` | `agent.tool.register.v1` | `agent.tool.register.v1/policy.json` |

---

## 🧪 Testing

### Test Command Verification

```bash
# Should ALLOW
bin/aport-guardrail.sh system.command.execute.v1 '{
  "command": "npm",
  "args": ["install"]
}'

# Should DENY (blocked pattern)
bin/aport-guardrail.sh system.command.execute.v1 '{
  "command": "rm",
  "args": ["-rf", "/"]
}'

# Should DENY (not in allowlist)
bin/aport-guardrail.sh system.command.execute.v1 '{
  "command": "sudo",
  "args": ["apt", "update"]
}'
```

### Test MCP Tool Verification

```bash
# Should ALLOW
bin/aport-guardrail.sh mcp.tool.execute.v1 '{
  "server": "https://mcp.github.com",
  "tool": "github.pull_requests.create",
  "parameters": {"repo": "test/repo"}
}'

# Should DENY (server not in allowlist)
bin/aport-guardrail.sh mcp.tool.execute.v1 '{
  "server": "https://evil-server.com",
  "tool": "malicious.tool",
  "parameters": {}
}'
```

---

## 🚨 Suspend agent (kill switch = passport status)

**Passport is the source of truth.** To suspend the agent, set passport `status` to `suspended`:

```bash
# Suspend: set passport status to suspended
jq '.status = "suspended"' ~/.openclaw/aport/passport.json > /tmp/passport.tmp && mv /tmp/passport.tmp ~/.openclaw/aport/passport.json

# All verifications will now DENY with oap.passport_suspended
bin/aport-guardrail.sh system.command.execute '{"command":"npm install"}'
# Exit 1, decision has allow: false, reasons[0].code: oap.passport_suspended

# Resume: set status back to active
jq '.status = "active"' ~/.openclaw/aport/passport.json > /tmp/passport.tmp && mv /tmp/passport.tmp ~/.openclaw/aport/passport.json
```

---

## 📝 Audit Logging

All decisions are logged to `~/.openclaw/audit.log`:

```
2026-02-08T10:00:00Z | system.command.execute.v1 | ALLOW | npm install | decision_id=abc123
2026-02-08T10:01:00Z | system.command.execute.v1 | DENY | rm -rf / | reason=blocked_pattern
2026-02-08T10:02:00Z | mcp.tool.execute.v1 | ALLOW | github.pull_requests.create | decision_id=def456
```

View recent activity:
```bash
tail -f ~/.openclaw/audit.log
```

---

## 🔄 Upgrading to Cloud (Optional)

When you're ready for team collaboration and global kill switch:

1. **Sign up** at https://aport.io
2. **Get API key** from dashboard
3. **Update passport** with `agent_id` from cloud registry
4. **Set environment variable:**
   ```bash
   export APORT_API_BASE=https://api.aport.io
   export APORT_API_KEY=ap_live_xxxxx
   ```

**Benefits:**
- ✅ Global kill switch (<15 seconds)
- ✅ Multi-machine sync
- ✅ Ed25519 signed receipts
- ✅ Team collaboration
- ✅ Analytics dashboard

---

## 🆘 Troubleshooting

### Problem: "Passport not found"
```bash
# Create passport
cat > ~/.openclaw/passport.json <<EOF
{
  "agent_id": "ap_openclaw_local_001",
  "status": "active",
  ...
}
EOF
```

### Problem: "API server not running"
```bash
# Start local API server
cd /Users/uchi/Downloads/projects/agent-passport
npm run dev
```

### Problem: "All commands denied"
```bash
# Check passport status (source of truth)
jq '.status' ~/.openclaw/aport/passport.json
# Should be "active"; if "suspended" or "revoked", set back to "active" to resume
```

---

## 📚 Next Steps

1. ✅ **Customize limits** - Edit `~/.openclaw/passport.json` limits
2. ✅ **Add more policies** - Copy additional policies from agent-passport repo
3. ✅ **Integrate with OpenClaw** - Add verification to your agent code
4. ✅ **Monitor audit logs** - Set up alerts for policy violations
5. ✅ **Upgrade to cloud** - When ready for team features

---

## 🎉 You're Done!

OpenClaw is now secure with APort policy enforcement. All commands and MCP tools are verified before execution, with built-in protection against injection, path traversal, and other attacks.

**Questions?** Check out:
- [QuickStart: OpenClaw Plugin](QUICKSTART_OPENCLAW_PLUGIN.md)
- [Tool / Policy Mapping](TOOL_POLICY_MAPPING.md)
- [GitHub Issues](https://github.com/aporthq/aport-agent-guardrails/issues)

---

**Made with ❤️ by Uchi (https://github.com/uchibeke/)**
