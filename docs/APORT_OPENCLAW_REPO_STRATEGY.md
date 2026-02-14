# APort × OpenClaw: Repository Strategy & Structure

**Date:** February 14, 2026  
**Decision:** Repository structure and contribution model

---

## Executive Summary

**Recommendation:** Create **standalone repo** `aporthq/aport-agent-guardrails` with **community-first** structure (different from SDK/policy repos which are more controlled).

**Why:** Agent guardrails integration is:
- ✅ **Installable CLI tool** (needs npm/pip packaging)
- ✅ **Community-contributed** (users will add policy packs, tools)
- ✅ **Standalone product** (not just an example)
- ✅ **Framework-agnostic** (works with OpenClaw, IronClaw, Go version, etc.)
- ✅ **Different from SDKs** (SDKs are controlled releases, this is open contribution)

**Key Insight:** APort doesn't compete with IronClaw—it **complements** it:
- **IronClaw** = Runtime security (sandboxing, isolation, credential protection)
- **APort** = Policy enforcement (business rules, limits, audit, kill switch)

---

## Repository Structure Comparison

### Current Pattern (SDKs, Policies, Specs)

**Structure:** Monorepo folder → Auto-published to separate repo

```
agent-passport/                    # Private monorepo
├── policies/                      # → aporthq/aport-policies
├── sdk/                          # → aporthq/aport-sdks-and-middlewares
├── spec/                         # → aporthq/aport-spec
└── examples/
    └── mcp-policy-gate-example/  # → aporthq/mcp-policy-gate-example
```

**Characteristics:**
- ✅ Controlled releases (via publish workflow)
- ✅ Versioned with main repo
- ✅ Auto-synced from monorepo
- ❌ Not ideal for community contributions (PRs go to monorepo, not target repo)

---

### Recommended Pattern (Agent Guardrails Integration)

**Structure:** Standalone repo with community contribution model

```
aporthq/aport-agent-guardrails/  # Public standalone repo
├── bin/                              # CLI executables
│   ├── aport                         # Main CLI entry point
│   ├── aport-create-passport.sh
│   ├── aport-status.sh
│   ├── aport-guardrail.sh
│   └── aport-renew-passport.sh
├── templates/                         # Passport templates
│   ├── passport.template.json
│   ├── passport.developer.json
│   ├── passport.ci-cd.json
│   └── passport.enterprise.json
├── policies/                          # Policy pack definitions
│   ├── code.repository.merge.json
│   ├── system.command.execute.json
│   ├── messaging.message.send.json
│   └── data.export.json
├── examples/                          # Integration examples
│   ├── basic-setup/
│   ├── github-actions/
│   └── docker/
├── docs/                              # Documentation
│   ├── README.md
│   ├── QUICKSTART.md
│   ├── UPGRADE_TO_CLOUD.md
│   └── POLICY_PACK_GUIDE.md
├── tests/                             # Test suite
│   ├── test-passport-creation.sh
│   ├── test-policy-evaluation.sh
│   └── test-kill-switch.sh
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                    # Test on PR
│   │   └── release.yml               # Publish to npm/brew
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── policy_pack.md            # Template for community policy packs
│   └── PULL_REQUEST_TEMPLATE.md
├── package.json                       # npm package definition
├── Makefile                           # Install/test commands
├── LICENSE                            # Apache 2.0
├── CONTRIBUTING.md                    # Contribution guidelines
└── CHANGELOG.md                       # Version history
```

**Characteristics:**
- ✅ Direct community contributions (PRs to this repo)
- ✅ Independent versioning (semver)
- ✅ Installable via npm/brew/pip
- ✅ Community policy packs welcome
- ✅ Own CI/CD pipeline

---

## Why Standalone Repo (Not Monorepo Folder)?

### 1. **Community Contributions**

**Monorepo Pattern (SDKs/Policies):**
- PRs go to private `agent-passport` repo
- Requires access to private repo
- Controlled release cycle
- Good for: Official SDKs, specs, policy packs

**Standalone Repo Pattern:**
- PRs go directly to `aporthq/aport-agent-guardrails`
- Public, anyone can contribute
- Faster iteration
- Good for: Community integrations, examples, tools

### 2. **Installation Model**

**SDKs/Policies:**
- Installed via: `npm install @aporthq/sdk-node`
- Versioned with main repo
- Controlled releases

**Agent Guardrails Integration:**
- Installed via: `npm install -g @aport/agent-guardrails` or `brew install aport-agent-guardrails`
- Needs independent versioning
- Community expects frequent updates

### 3. **Contribution Types**

**What Community Will Contribute:**
- ✅ New policy packs (e.g., `kubernetes.deploy.v1.json`)
- ✅ Tool wrappers (e.g., `aport-wrapped-docker.sh`)
- ✅ Integration examples (e.g., `examples/vscode-extension/`)
- ✅ Documentation improvements
- ✅ Bug fixes

**These contributions are better suited for standalone repo** because:
- Faster review cycle (no monorepo complexity)
- Clear ownership (this repo = OpenClaw integration)
- Community can fork/contribute easily

---

## Repository Setup

### Step 1: Create Repository

```bash
# Create public repo
gh repo create aporthq/aport-agent-guardrails \
  --public \
  --description "Policy enforcement guardrails for OpenClaw-compatible agent frameworks - Add pre-action authorization, graduated controls, and cryptographic audit trails to OpenClaw, IronClaw, and other compatible frameworks" \
  --add-readme \
  --license Apache-2.0
```

### Step 2: Initial Structure

```bash
cd /Users/uchi/Downloads/projects
git clone git@github.com:aporthq/aport-agent-guardrails.git
cd aport-agent-guardrails

# Copy from current example
cp -r /Users/uchi/Downloads/projects/open-work/openclaw-aport-example/* .

# Reorganize into proper structure
mkdir -p bin templates policies examples docs tests .github/workflows
mv aport-guardrail.sh bin/
mv passport.json templates/passport.template.json
mv AGENTS.md.example docs/AGENTS.md.example
```

### Step 3: Add Package Definition

**`package.json`:**
```json
{
  "name": "@aport/agent-guardrails",
  "version": "0.1.0",
  "description": "Policy enforcement guardrails for OpenClaw-compatible agent frameworks",
  "bin": {
    "aport": "./bin/aport"
  },
  "scripts": {
    "test": "make test",
    "install": "make install"
  },
  "keywords": [
    "openclaw",
    "aport",
    "agent",
    "security",
    "authorization",
    "policy",
    "guardrails"
  ],
  "author": "APort Inc.",
  "license": "Apache-2.0",
  "repository": {
    "type": "git",
    "url": "https://github.com/aporthq/aport-agent-guardrails.git"
  },
  "files": [
    "bin/",
    "templates/",
    "policies/",
    "docs/",
    "LICENSE",
    "README.md"
  ]
}
```

### Step 4: Add CI/CD Workflow

**`.github/workflows/ci.yml`:**
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq
      - name: Run tests
        run: |
          make test
      - name: Validate passport schema
        run: |
          # Validate against OAP v1.0 schema
          jq . templates/passport.template.json > /dev/null
      - name: Test guardrail script
        run: |
          chmod +x bin/aport-guardrail.sh
          bin/aport-guardrail.sh git.create_pr '{"repo":"test","files_changed":5}' || exit 1
```

**`.github/workflows/release.yml`:**
```yaml
name: Release

on:
  release:
    types: [created]

jobs:
  publish-npm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          registry-url: 'https://registry.npmjs.org'
      - run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

---

## Contribution Model

### Community Policy Packs

**Template:** `.github/ISSUE_TEMPLATE/policy_pack.md`

```markdown
## Policy Pack Proposal

**Policy ID:** `[e.g., kubernetes.deploy.v1]`

**Description:**
[What does this policy enforce?]

**Tools Covered:**
- `kubectl.apply`
- `kubectl.delete`
- `helm.install`

**Limits:**
- Max deployments per day: [number]
- Allowed namespaces: [list]
- Blocked resources: [list]

**Use Case:**
[Why is this needed?]
```

**Process:**
1. Community member opens issue with policy pack proposal
2. APort team reviews (or community votes)
3. Contributor creates PR with policy JSON + tests
4. Merge → Available to all users

### Community Tool Wrappers

**Example:** User contributes `bin/aport-wrapped-docker.sh`

**Process:**
1. Fork repo
2. Add wrapper script
3. Add tests
4. Submit PR
5. Merge → Available in next release

---

## Relationship to Monorepo

### Option A: Keep Separate (Recommended)

**Structure:**
```
agent-passport/                    # Private monorepo
└── (no agent guardrails folder)

aporthq/aport-agent-guardrails/  # Public standalone repo
└── (complete standalone integration)
```

**Pros:**
- ✅ Clear separation (private vs. public)
- ✅ Independent versioning
- ✅ Community can contribute directly
- ✅ Faster iteration

**Cons:**
- ❌ No auto-sync from monorepo
- ❌ Manual updates if needed

### Option B: Hybrid (Reference in Monorepo)

**Structure:**
```
agent-passport/                    # Private monorepo
└── examples/
    └── agent-guardrails/          # Reference/symlink
        └── README.md → Points to standalone repo

aporthq/aport-agent-guardrails/  # Public standalone repo
└── (actual implementation)
```

**Pros:**
- ✅ Discoverable from monorepo
- ✅ Can reference in docs
- ✅ Still standalone for contributions

**Cons:**
- ⚠️ Slight duplication

**Recommendation:** **Option A** (keep completely separate)

---

## Publishing Strategy

### npm Package

**Name:** `@aport/agent-guardrails`

**Install:**
```bash
npm install -g @aport/agent-guardrails
```

**Usage:**
```bash
aport init          # Create passport
aport status        # View status
aport verify        # Verify passport
```

### Homebrew Tap

**Formula:** `aport-agent-guardrails.rb`

**Install:**
```bash
brew tap aporthq/aport
brew install aport-agent-guardrails
```

### GitHub Releases

**Release Process:**
1. Tag version: `git tag v0.1.0`
2. Push tag: `git push origin v0.1.0`
3. GitHub Actions:
   - Runs tests
   - Publishes to npm
   - Creates GitHub release
   - Updates Homebrew formula

---

## File Structure Details

### `/bin/` - CLI Executables

```
bin/
├── aport                        # Main CLI (Node.js wrapper)
├── aport-create-passport.sh     # Passport creation wizard
├── aport-status.sh              # Status dashboard
├── aport-guardrail.sh           # Policy evaluator
├── aport-renew-passport.sh      # Renew expired passport
└── aport-kill-switch.sh         # Kill switch management
```

### `/templates/` - Passport Templates

```
templates/
├── passport.template.json        # Basic template
├── passport.developer.json       # Developer preset (PRs, commands)
├── passport.ci-cd.json           # CI/CD preset (deployments)
└── passport.enterprise.json      # Enterprise preset (strict limits)
```

### `/policies/` - Policy Pack Definitions

```
policies/
├── code.repository.merge.json   # Git operations
├── system.command.execute.json  # Command execution
├── messaging.message.send.json   # Message sending
├── data.export.json             # Data exports
└── README.md                    # Policy pack guide
```

**Community Contributions Welcome:**
- Users can add new policy packs via PR
- Policy packs follow OAP v1.0 schema
- Each policy pack includes:
  - JSON definition
  - Documentation
  - Example usage
  - Tests

### `/examples/` - Integration Examples

```
examples/
├── basic-setup/                 # Minimal setup guide
├── github-actions/              # CI/CD integration
├── docker/                      # Containerized workflows
└── vscode-extension/            # VS Code integration (future)
```

### `/docs/` - Documentation

```
docs/
├── README.md                    # Main documentation
├── QUICKSTART.md                # 5-minute setup
├── UPGRADE_TO_CLOUD.md          # Cloud migration guide
├── POLICY_PACK_GUIDE.md         # How to write policies
├── AGENTS.md.example            # OpenClaw AGENTS.md template
└── COMPLIANCE.md                # SOC 2, IIROC, HIPAA guidance
```

---

## Comparison: Examples vs. Integration

### Examples (mcp-policy-gate-example)

**Purpose:** Show how to use APort with MCP  
**Structure:** Single example, minimal files  
**Contribution:** Limited (mostly bug fixes)  
**Publishing:** Auto-published from monorepo

### Integration (openclaw-integration)

**Purpose:** Full integration product  
**Structure:** Complete CLI tool with multiple components  
**Contribution:** Extensive (policy packs, wrappers, examples)  
**Publishing:** Standalone repo with own CI/CD

---

## Recommendation Summary

### ✅ **Create Standalone Repo**

**Repository:** `aporthq/aport-openclaw-integration`

**Structure:**
- ✅ Standalone (not in monorepo)
- ✅ Community-first (easy PRs)
- ✅ Installable (npm/brew/pip)
- ✅ Independent versioning

### ✅ **Improve Current Example**

**Current Location:** `/Users/uchi/Downloads/projects/open-work/openclaw-aport-example/`

**Improvements Needed:**
1. ✅ CLI tools (`aport-create-passport.sh`, `aport-status.sh`) - **DONE**
2. Add rate limiting enforcement
3. Add audit log chaining (SHA-256)
4. Add policy pack templates
5. Add package.json for npm publishing
6. Add CI/CD workflows
7. Add contribution guidelines
8. Add LICENSE file (Apache 2.0 with cloud API notice)

### ✅ **Migration Path (Accelerated)**

1. **Week 1:** Improve current example + Create repo + Migrate code + Set up CI/CD
2. **Week 2:** Publish to npm + Create Homebrew tap + Launch + Announce

**Why Accelerated:**
- 85% of code already done (CLI tools created)
- Repo creation takes <1 hour
- Migration takes <1 day
- Can combine phases for faster launch

---

## Next Steps

1. ✅ **Review this strategy** - Validate approach
2. ✅ **Improve current example** - Add missing features from roadmap
3. ✅ **Create repo structure** - Set up `aporthq/aport-openclaw-integration`
4. ✅ **Migrate code** - Move improved example to repo
5. ✅ **Set up CI/CD** - GitHub Actions for testing + publishing
6. ✅ **Publish to npm** - Make installable
7. ✅ **Announce** - Blog post, GitHub release

---

## Questions Answered

### Q: Should it be in its own repo?
**A:** ✅ **YES** - Standalone repo `aporthq/aport-agent-guardrails`

### Q: Should it follow the monorepo publish pattern?
**A:** ❌ **NO** - Different model:
- SDKs/Policies = Controlled releases (monorepo → publish workflow)
- Agent Guardrails = Community contributions (standalone repo)

### Q: Should people be able to contribute?
**A:** ✅ **YES** - Community-first:
- Policy packs (PRs welcome)
- Framework adapters (OpenClaw, IronClaw, Go version)
- Tool wrappers (PRs welcome)
- Examples (PRs welcome)
- Documentation (PRs welcome)

### Q: How does it relate to agent-passport monorepo?
**A:** **Independent** - No auto-sync needed:
- Agent guardrails is standalone product
- Can reference in monorepo docs (link to repo)
- Community contributes directly to integration repo

### Q: How does it relate to IronClaw?
**A:** **Complements, doesn't compete**:
- **IronClaw** = Runtime security (WASM sandbox, credential protection)
- **APort** = Policy enforcement (business rules, limits, audit)
- Use both for complete defense-in-depth security

---

---

## Open-Core Strategy

### Free Tier (Open Source)

**What's Included:**
- ✅ Local passport evaluation (bash scripts)
- ✅ CLI tools (`aport init`, `aport status`, `aport verify`)
- ✅ Community policy packs
- ✅ Basic audit logs (plain text)
- ✅ Single-machine kill switch (file-based)
- ✅ Full documentation & examples

**Target Users:** Individual developers, hobbyists, open-source projects, students

**Conversion Goal:** 10-15% upgrade to Pro after 30 days

---

### Pro Tier ($99/user/month)

**Target:** Teams of 20-100 developers

**Exclusive Features:**
- 💰 **Multi-machine sync** - Passport changes propagate <15 seconds across all agents
- 💰 **Global kill switch** - Suspend passport globally from dashboard (not per-machine file)
- 💰 **Ed25519 signed receipts** - Cryptographically signed audit logs (court-admissible)
- 💰 **Team collaboration** - Shared passports, role-based policies, approval workflows
- 💰 **Analytics dashboard** - Usage metrics, risk scoring, anomaly detection
- 💰 **Policy marketplace** - Pre-built policy packs for industries (legal, finance, healthcare)
- 💰 **Priority support** - Email/Slack support, 24-hour response SLA

**ROI Justification:**
- Prevents 1x $500K malpractice claim = 21 months of service paid back
- Global kill switch saves 2 hours of incident response × $400/hour = $800 per incident
- Team of 50 devs = $4,950/month → Prevents 1 major compliance violation = ROI in <1 month

---

### Enterprise Tier ($149/user/month)

**Target:** Large organizations (100-500+ developers)

**Everything in Pro, PLUS:**
- 💰 **Private instance** - Dedicated infrastructure (AWS/GCP/Azure)
- 💰 **On-premises option** - Self-hosted in customer data center
- 💰 **Dedicated CSM** - Customer Success Manager for onboarding/support
- 💰 **Custom policies** - Tailor-made policy packs for specific use cases
- 💰 **24/7 support** - Phone/Slack support with 1-hour SLA
- 💰 **Compliance reports** - SOC 2, IIROC, HIPAA, OSFI audit-ready reports
- 💰 **SSO/SAML** - Enterprise identity integration

**ROI Justification:**
- SOC 2 audit prep: Reduces from 40 days to 5 days → $100K savings
- Regulatory fine avoidance (GDPR): €20M → $149 × 100 users × 12 months = $178K (0.89% of potential fine)
- Enterprise deal size: 100 users × $149/month × 12 = $178,800 ARR per customer

---

### How It Works

**Free Tier Users:**
1. Install via npm: `npm install -g @aport/agent-guardrails`
2. Create local passport: `aport init`
3. Use for 7-30 days (sees upgrade hints 1x/day)
4. Upgrade prompts shown non-intrusively (once per day max)

**Upgrade Hints:**
- Shown after successful local verification
- Non-intrusive (once per day)
- Clear value proposition (global kill switch, team collaboration, compliance)

**Conversion Funnel:**
```
Developer discovers → Installs free CLI → Uses for 7-30 days
    ↓
Needs team collaboration? OR Needs compliance audit?
    ↓
Upgrades to Pro ($99/user/mo)
    ↓
Uses for 3-6 months
    ↓
Needs private instance? OR Needs on-prem? OR Needs 24/7 support?
    ↓
Upgrades to Enterprise ($149/user/mo)
```

**Target Conversion Rates:**
- Free → Pro: 10-15% within 90 days
- Pro → Enterprise: 30-40% within 12 months
- Free tier churn: <5% monthly
- Pro tier churn: <2% monthly

---

## Success Metrics

### Installation Metrics (via npm)

**Track:**
- Weekly downloads (`npm stats`)
- GitHub stars (community engagement)
- Issue/PR velocity (contribution rate)
- Framework adoption (OpenClaw vs. IronClaw vs. Go)

**Implementation:**
- npm automatically tracks downloads
- GitHub provides stars/forks metrics
- Issue templates track contribution types

---

### Conversion Metrics (via upgrade hints)

**Track:**
- Free users who click "Learn More" (hint engagement)
- Free → Pro conversion rate (within 90 days)
- Time to first upgrade (days from install to upgrade)
- Upgrade hint click-through rate

**Implementation:**
- Add opt-in telemetry to CLI (privacy-preserving)
- Track: installations, active users, upgrade hint clicks
- Store: Local file (`~/.aport/metrics.json`), optionally upload to APort (opt-in)
- Privacy: No PII, only aggregate metrics (install count, hint clicks)

**Example Metrics File:**
```json
{
  "install_date": "2026-02-14",
  "hint_clicks": 3,
  "last_hint_date": "2026-02-20",
  "upgrade_clicked": false
}
```

---

### Usage Metrics (via audit logs)

**Track:**
- Policy checks per day (usage intensity)
- Denial rate (policy effectiveness)
- Most-used policy packs (popular policies)
- Average decision latency (performance)

**Implementation:**
- Parse audit logs locally (no cloud upload)
- Aggregate metrics in `aport status` command
- Optional: Upload aggregate stats to APort (opt-in, anonymized)

---

### Business Metrics

**Track:**
- API usage (increased API calls due to open-source adoption)
- User growth (new users from open-source community)
- Partner integrations (increased partner adoption)
- Revenue growth (indirect revenue from open-source adoption)

**Targets (Year 1):**
- 1,000+ npm downloads/week
- 500+ GitHub stars
- 50+ community policy packs
- 10-15% free → Pro conversion rate
- $500K ARR from conversions

---

**Prepared by:** Claude (AI Assistant)  
**Date:** February 14, 2026  
**Status:** Ready for Implementation
