# APort Agent Guardrails

> **Pre-action authorization guardrails for AI agents** - Works with OpenClaw, IronClaw, and compatible frameworks

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![npm version](https://img.shields.io/npm/v/@aport/agent-guardrails.svg)](https://www.npmjs.com/package/@aport/agent-guardrails)

APort Agent Guardrails adds policy enforcement, graduated controls, and cryptographic audit trails to OpenClaw, IronClaw, and other compatible agent frameworks. Works alongside runtime security (sandboxing) to provide defense-in-depth protection.

## 🎯 What It Does

- ✅ **Pre-action authorization** - Verify permissions before executing tools
- ✅ **Graduated controls** - Set limits (max PR size, daily caps, etc.)
- ✅ **Business logic** - Enforce policies based on context
- ✅ **Audit trails** - Tamper-evident logs of all decisions
- ✅ **Kill switch** - Globally suspend agent if compromised
- ✅ **Framework-agnostic** - Works with OpenClaw, IronClaw, Go version, etc.

## 🚀 Quick Start

### Installation

```bash
# Via npm (coming soon)
npm install -g @aport/agent-guardrails

# Or clone and install manually
git clone https://github.com/aporthq/aport-agent-guardrails.git
cd aport-agent-guardrails
make install
```

### Create Your First Passport

```bash
aport-create-passport.sh
```

### Check Status

```bash
aport-status.sh
```

## 📚 Documentation

- [Quick Start Guide](docs/QUICKSTART.md) - 5-minute setup
- [OpenClaw Integration](docs/AGENTS.md.example) - AGENTS.md template
- [Policy Pack Guide](docs/POLICY_PACK_GUIDE.md) - How to write policies
- [Upgrade to Cloud](docs/UPGRADE_TO_CLOUD.md) - Cloud migration guide

## 🏗️ Architecture

APort Agent Guardrails works alongside runtime security frameworks:

- **IronClaw** = Runtime security (WASM sandbox, credential protection)
- **APort** = Policy enforcement (business rules, limits, audit)

Together = Complete defense-in-depth security

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- Policy packs (PRs welcome)
- Framework adapters (OpenClaw, IronClaw, Go version)
- Tool wrappers (PRs welcome)
- Documentation improvements (PRs welcome)

## 📄 License

Apache 2.0 - See [LICENSE](LICENSE) for details.

**Cloud API Notice:** The APort Cloud API (api.aport.io) is proprietary software. Access requires a paid subscription. See [pricing](https://aport.io/pricing).

## 🔗 Links

- [Website](https://aport.io)
- [Documentation](https://docs.aport.io)
- [GitHub Issues](https://github.com/aporthq/aport-agent-guardrails/issues)
- [Discussions](https://github.com/aporthq/aport-agent-guardrails/discussions)

---

Made with ❤️ by the APort team
