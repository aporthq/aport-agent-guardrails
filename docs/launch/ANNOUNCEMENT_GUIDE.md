# OpenClaw + APort Announcement Guide

**Ready to announce OpenClaw is secure!** This guide helps you create announcement materials.

---

## 🎯 Key Messages

### Primary Message
**"OpenClaw is now secure with APort - Pre-action authorization for commands and MCP tools. One command, no clone required."**

### Supporting Points
1. ✅ **One-command setup** - `npx @aporthq/aport-agent-guardrails` (no clone); optional hosted passport via `npx @aporthq/aport-agent-guardrails <agent_id>`
2. ✅ **Local-first or API** - Works offline (bash) or with APort API (default in wizard) for full OAP
3. ✅ **40+ built-in security patterns** - Protection against injection, path traversal, privilege escalation
4. ✅ **4 OpenClaw policies** - Commands, MCP tools, sessions, tool registration
5. ✅ **Sub-300ms performance** - Fast enough for real-time agent workflows

---

## 📝 Tweet Draft

```
🚀 OpenClaw is now secure with APort!

✅ Pre-action authorization for commands & MCP tools
✅ One command: npx @aporthq/aport-agent-guardrails (no clone)
✅ 40+ built-in security patterns (injection, path traversal, etc.)
✅ 5-minute setup • Hosted passport optional (use your agent_id)

🔗 https://github.com/aporthq/aport-agent-guardrails
📖 https://aport.io/openclaw

#OpenClaw #AISecurity #PolicyEnforcement
```

---

## 📝 Blog Post Outline

### Title
**"Securing OpenClaw with APort: Pre-Action Authorization in 5 Minutes"**

### Structure

1. **Introduction** (2 paragraphs)
   - OpenClaw's security challenges
   - APort's solution: pre-action authorization

2. **The Problem** (3 paragraphs)
   - TrustClaw addresses runtime security (OAuth, sandboxing)
   - Missing: Pre-action policy enforcement
   - Need for graduated controls (max amounts, daily caps)

3. **The Solution** (4 paragraphs)
   - APort's 4 OpenClaw policies
   - Local-first approach (no cloud dependency)
   - Built-in security patterns
   - Easy integration

4. **Quick Start** (5 paragraphs)
   - One command: `npx @aporthq/aport-agent-guardrails` (no clone); optional `npx @aporthq/aport-agent-guardrails <agent_id>` for hosted passport
   - 5-minute setup guide (wizard installs plugin, passport, smoke test)
   - Code examples and test commands

5. **Security Features** (3 paragraphs)
   - 40+ built-in patterns
   - Cannot be bypassed
   - Defense-in-depth

6. **Performance** (2 paragraphs)
   - Sub-100ms API latency (~60–65 ms mean); local sub-300ms
   - Fast enough for real-time workflows

7. **Next Steps** (2 paragraphs)
   - Try it locally
   - Upgrade to cloud for team features

---

## 🎬 Demo Script

### Video Script (2 minutes)

**0:00 - 0:15: Introduction**
- "OpenClaw is powerful, but needs security"
- "APort adds pre-action authorization"
- "Works locally, no cloud required"

**0:15 - 0:45: Setup**
- Run: `npx @aporthq/aport-agent-guardrails` (wizard: config dir, passport choice — hosted or wizard, mode API/local)
- Show plugin installed; optional: show passport.json or hosted agent_id

**0:45 - 1:15: Demo - Command Verification**
- Show `~/.openclaw/.skills/aport-guardrail.sh system.command.execute '{"command":"mkdir test"}'` (ALLOW)
- Show `... '{"command":"rm -rf /"}'` (DENY - blocked pattern)
- Show sudo / dangerous command (DENIED)

**1:15 - 1:45: Demo - MCP Tool Verification**
- Show github.pull_requests.create (ALLOWED)
- Show evil-server.com (DENIED - server not allowed)

**1:45 - 2:00: Wrap-up**
- "40+ built-in security patterns"
- "5-minute setup"
- "Link in description"

---

## 📊 Code Examples for Announcement

### Example 1: Command Verification

```python
from aport_guardrail import APortGuardrail

guardrail = APortGuardrail()

# This is ALLOWED
guardrail.verify_command("npm", ["install"])

# This is DENIED (blocked pattern)
try:
    guardrail.verify_command("rm", ["-rf", "/"])
except PermissionError:
    print("Dangerous command blocked!")
```

### Example 2: MCP Tool Verification

```python
# This is ALLOWED
guardrail.verify_mcp_tool(
    "https://mcp.github.com",
    "github.pull_requests.create",
    {"repo": "test/repo"}
)

# This is DENIED (server not allowed)
try:
    guardrail.verify_mcp_tool(
        "https://evil-server.com",
        "malicious.tool",
        {}
    )
except PermissionError:
    print("MCP tool blocked!")
```

---

## 📈 Performance Metrics

### Key Numbers to Highlight

- **P95 Latency**: 268ms (generic evaluators)
- **Mean Latency**: 178ms
- **Success Rate**: 100%
- **Security Patterns**: 40+ built-in patterns
- **Setup Time**: 5 minutes
- **Policies**: 4 OpenClaw-specific policies

### Comparison

| Metric | Manual Evaluators | Generic Evaluators | Target |
|--------|------------------|-------------------|--------|
| P95 Latency | 239ms | 268ms | <200ms |
| Mean Latency | 165ms | 178ms | <150ms |
| Success Rate | 100% | 100% | 100% |

**Note**: Generic evaluators are 11.8% slower but provide:
- ✅ Policy-driven (no hardcoded logic)
- ✅ Easier to maintain
- ✅ Consistent across all policies

---

## 🎨 Visual Assets

### Screenshot Ideas

1. **Terminal showing verification**
   ```
   ✅ npm install - ALLOWED
   ❌ rm -rf / - DENIED (blocked pattern)
   ❌ sudo apt update - DENIED (not in allowlist)
   ```

2. **Code example showing integration**
   - Python code with APortGuardrail class
   - Clean, readable, well-commented

3. **Architecture diagram**
   - OpenClaw → APort → Policy Evaluation → Allow/Deny

---

## 🔗 Links to Include

- **GitHub Repo**: https://github.com/aporthq/aport-agent-guardrails
- **Integration Guide**: docs/OPENCLAW_LOCAL_INTEGRATION.md
- **Example Code**: examples/openclaw-integration-example.py
- **Policy Docs**: policies/system.command.execute.v1/README.md
- **Website**: https://aport.io
- **OpenClaw quickstart**: https://aport.io/openclaw (one command: `npx @aporthq/aport-agent-guardrails`)

---

## 📋 Checklist Before Announcement

- [ ] Local API server tested and working
- [ ] Example scripts tested
- [ ] Documentation reviewed
- [ ] Performance metrics verified
- [ ] Security patterns tested
- [ ] Demo video recorded (optional)
- [ ] Blog post written (optional)
- [ ] Social media posts scheduled (optional)

---

## 🚀 Launch Day Checklist

- [ ] Post on Twitter/X
- [ ] Post on LinkedIn
- [ ] Post on Reddit (r/MachineLearning, r/OpenSource)
- [ ] Post on Hacker News
- [ ] Update GitHub README
- [ ] Send to OpenClaw community
- [ ] Monitor for questions/feedback

---

## 💬 FAQ for Announcement

### Q: Do I need cloud API?
**A:** No! Works completely locally. Cloud API is optional for team features.

### Q: How fast is it?
**A:** Sub-100ms API (P95 ~70 ms); local sub-300ms — fast enough for real-time agent workflows.

### Q: What's protected?
**A:** Commands, MCP tools, agent sessions, and tool registration. 40+ built-in security patterns.

### Q: Can I bypass the security?
**A:** No. Built-in security patterns are always enforced, even if you add commands to allowlist.

### Q: How do I upgrade to cloud?
**A:** Sign up at aport.io, get API key, set environment variables. See docs/UPGRADE_TO_CLOUD.md.

---

## 🎉 Ready to Launch!

You have everything you need:
- ✅ Working implementation
- ✅ Documentation
- ✅ Examples
- ✅ Performance metrics
- ✅ Security features

**Go ahead and announce! 🚀**

---

**Made with ❤️ by the APort team**
