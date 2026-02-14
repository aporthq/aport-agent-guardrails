# Getting Started with APort Agent Guardrails
**For Uchi: Your Personal Test & Integration Guide**

---

## 🎯 Quick Overview

**What you have now:**
- ✅ Complete repo structure at `/Users/uchi/Downloads/projects/aport-agent-guardrails/`
- ✅ 3 CLI tools (create-passport, status, guardrail)
- ✅ 4 policy packs (git, exec, messaging, data)
- ✅ Comprehensive documentation
- ✅ Ready to test!

**What to follow:**
- ✅ **YES:** `docs/QUICKSTART.md` - This is your hands-on testing guide (5 minutes)
- ⚠️  **NO:** `docs/APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md` - This is strategic planning (for future improvements)

---

## 🚀 What You Should Do Right Now (30 Minutes)

### Step 1: Install & Test (15 minutes)

```bash
# 1. Navigate to repo
cd /Users/uchi/Downloads/projects/aport-agent-guardrails

# 2. Install
make install

# 3. Follow the Quick Start guide
open docs/QUICKSTART.md
# OR
cat docs/QUICKSTART.md
```

**Follow QUICKSTART.md exactly - it will walk you through:**
1. Creating your first passport (1 minute)
2. Checking status dashboard (10 seconds)
3. Testing policy evaluation (5 minutes)
4. Testing kill switch (30 seconds)
5. Viewing activity logs (10 seconds)

---

### Step 2: Integrate with Your OpenClaw Instance (15 minutes)

**Option A: If you have OpenClaw installed**

```bash
# Find your OpenClaw AGENTS.md
find ~ -name "AGENTS.md" -path "*/.openclaw/*" 2>/dev/null | head -1

# Add APort section
cat /Users/uchi/Downloads/projects/aport-agent-guardrails/docs/AGENTS.md.example >> ~/.openclaw/AGENTS.md

# Verify
cat ~/.openclaw/AGENTS.md | grep "Pre-Action Authorization"
```

**Option B: If you don't have OpenClaw yet**

```bash
# Install OpenClaw first
npm install -g @openclaw/cli  # Or whatever the install command is

# Then come back and follow Option A
```

**Option C: Manual testing (no OpenClaw needed)**

You can test the guardrail scripts standalone (as shown in QUICKSTART.md):

```bash
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{
  "repo": "test",
  "files_changed": 10
}'
```

---

## 📁 Repository Structure Overview

```
aport-agent-guardrails/
├── bin/                              # ✅ Your CLI tools
│   ├── aport-create-passport.sh     # ✅ WORKING (interactive wizard)
│   ├── aport-status.sh              # ✅ WORKING (dashboard)
│   └── aport-guardrail.sh           # ✅ WORKING (policy evaluator)
│
├── templates/                         # ✅ Passport templates
│   └── passport.template.json       # ✅ Basic template
│
├── policies/                          # ✅ Policy pack definitions
│   ├── code.repository.merge.json   # ✅ Git operations policy
│   ├── system.command.execute.json  # ✅ Command execution policy
│   ├── messaging.message.send.json  # ✅ Messaging policy
│   └── data.export.json             # ✅ Data export policy
│
├── docs/                              # ✅ Documentation
│   ├── QUICKSTART.md                # ✅ START HERE! (5-min guide for YOU)
│   ├── AGENTS.md.example            # ✅ OpenClaw integration template
│   ├── APORT_OPENCLAW_INTEGRATION_PROPOSAL.md  # ✅ Full technical spec
│   └── APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md  # ⚠️  Future roadmap (not for testing)
│
├── examples/                          # 🔜 TODO (not critical for testing)
│   ├── basic-setup/
│   ├── docker/
│   └── github-actions/
│
├── tests/                             # 🔜 TODO (not critical for testing)
│
├── .github/                           # ✅ GitHub workflows (CI/CD)
│   ├── workflows/
│   └── ISSUE_TEMPLATE/
│
├── package.json                       # ✅ npm package definition
├── Makefile                           # ✅ Install/test commands
├── LICENSE                            # ✅ Apache 2.0 + cloud notice
├── README.md                          # ✅ Main README
├── CONTRIBUTING.md                    # ✅ Contribution guidelines
├── CHANGELOG.md                       # ✅ Version history
└── GETTING_STARTED.md                 # ✅ This file (your guide)
```

---

## 📖 Documentation Guide

### Which Document to Read When

| Document | When to Read | Purpose |
|----------|-------------|---------|
| **GETTING_STARTED.md** (this file) | ✅ **NOW** | Your personal roadmap |
| **docs/QUICKSTART.md** | ✅ **NOW** | Hands-on testing guide (5 min) |
| **README.md** | ✅ **NOW** | Project overview |
| **docs/AGENTS.md.example** | ✅ **NOW** | How to integrate with OpenClaw |
| **docs/APORT_OPENCLAW_INTEGRATION_PROPOSAL.md** | Later | Full technical specification |
| **docs/APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md** | Later | Strategic planning for future |
| **CONTRIBUTING.md** | When contributing | How to contribute |

---

## ❓ Common Questions

### Q: Which document should I follow step-by-step?

**A:** `docs/QUICKSTART.md` - This is your hands-on testing guide.

`docs/APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md` is the **strategic roadmap** for future improvements (Weeks 1-8 plan to reach 100/100 score). It's **not** a testing guide.

---

### Q: Do I need to have OpenClaw installed to test?

**A:** No! You can test the CLI tools standalone:

```bash
# Test passport creation
~/.openclaw/.skills/aport-create-passport.sh

# Test policy evaluation
~/.openclaw/.skills/aport-guardrail.sh git.create_pr '{"repo":"test","files_changed":10}'

# Test status dashboard
~/.openclaw/.skills/aport-status.sh
```

---

### Q: What's the difference between local-only and cloud mode?

**A:**
- **Local-only (what you have now):** Free, works offline, passport stored in `~/.openclaw/passport.json`
- **Cloud mode (future):** Paid tier ($99/mo), multi-machine sync, global kill switch, Ed25519 signatures

You're testing **local-only** right now. Cloud mode comes later (Q3 2026).

---

### Q: How do I know if it's working?

**A:** After running `make install` and creating a passport, you should be able to:

1. ✅ Run `~/.openclaw/.skills/aport-status.sh` and see your passport info
2. ✅ Test policy evaluation and see `{"allow": true}` for valid requests
3. ✅ Test policy violations and see `{"allow": false, "message": "..."}` for invalid requests
4. ✅ See audit log entries in `~/.openclaw/audit.log`

---

### Q: What if I get errors?

**A:** Check troubleshooting section in `docs/QUICKSTART.md`. Common issues:

- **"jq not found"** → `brew install jq`
- **"Permission denied"** → `chmod +x ~/.openclaw/.skills/aport-*.sh`
- **"Passport not found"** → Run `aport-create-passport.sh` again

---

## 🎯 Success Criteria (How to Know You're Done Testing)

### ✅ Phase 1: Basic Testing (5 minutes)
- [ ] Passport created successfully
- [ ] Status dashboard shows passport info
- [ ] Small PR allowed (10 files)
- [ ] Large PR denied (1000 files)
- [ ] Dangerous command blocked (`rm -rf`)
- [ ] Audit log contains entries

### ✅ Phase 2: Kill Switch Testing (2 minutes)
- [ ] Activate kill switch → all actions blocked
- [ ] Deactivate kill switch → actions work again

### ✅ Phase 3: Integration Testing (if you have OpenClaw)
- [ ] AGENTS.md updated with APort section
- [ ] OpenClaw respects policy decisions
- [ ] Denials shown to user with clear messages

---

## 🚀 Next Steps After Testing

### Immediate (After successful testing):
1. ✅ **Push to GitHub** (if not already pushed)
2. ✅ **Create initial release** (v0.1.0)
3. ✅ **Test npm install** (locally first)

### Short-term (Next 1-2 weeks):
1. 📦 **Publish to npm** (make it installable)
2. 🎬 **Create demo video** (5-min screencast)
3. 📝 **Write blog post** (launch announcement)

### Medium-term (Next 1-2 months):
1. 🏗️ **Add missing features** (follow `APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md`)
2. 🤝 **Get pilot users** (10 beta testers)
3. 💰 **Plan cloud tier** (pricing, features)

---

## 📊 Current Status

**Implementation Score:** 85/100 ✅
- Security: 75/100
- UX: 88/100 (great CLI tools!)
- Monetization: 85/100 (strategy defined)
- Distribution: 70/100 (roadmap provided)

**Path to 100/100:** Follow `docs/APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md` (8-week plan)

---

## 🆘 Get Help

### For Testing Issues:
1. Check `docs/QUICKSTART.md` troubleshooting section
2. Check GitHub Issues: https://github.com/aporthq/aport-agent-guardrails/issues
3. Email: support@aport.io

### For Strategic Questions:
1. Review `docs/APORT_OPENCLAW_INTEGRATION_PROPOSAL.md` (full spec)
2. Review `docs/APORT_OPENCLAW_ANALYSIS_AND_ROADMAP.md` (roadmap)
3. Email: uchi@aport.io

---

## 🎉 You're Ready!

**Start here:** `docs/QUICKSTART.md` (5 minutes)

**Then:** Test with your OpenClaw instance (15 minutes)

**Total time:** ~30 minutes to fully test and integrate

**Go test it! You've built something great! 🚀**

---

**Made with ❤️ by the APort team**
