# Contributing to APort Agent Guardrails

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Policy Packs

Policy packs are JSON files that define rules for specific actions. To contribute a new policy pack:

1. Open an issue using the [Policy Pack Proposal template](.github/ISSUE_TEMPLATE/policy_pack.md)
2. Get feedback from maintainers
3. Create a PR with:
   - Policy JSON file in `policies/`
   - Documentation
   - Example usage
   - Tests (if applicable)

### Framework Adapters

We welcome adapters for new frameworks (Rust, Go, Python, etc.):

1. Create adapter in `adapters/[framework-name]/`
2. Include integration examples
3. Add documentation
4. Submit PR

### Bug Reports

Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md) and include:
- Clear description
- Steps to reproduce
- Expected vs. actual behavior
- Environment details

### Feature Requests

Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md) and include:
- Use case
- Proposed solution
- Alternatives considered

## Versioning and releases

We keep **one version number** across all packages (Node core, Python core, and framework adapters). Releases are driven by [Changesets](.changeset/README.md). For the full flow (bump, changelog, publish, tag), see **[docs/RELEASE.md](docs/RELEASE.md)**.

## Development Setup

```bash
# Clone the repo
git clone https://github.com/aporthq/aport-agent-guardrails.git
cd aport-agent-guardrails

# Install dependencies
make install

# Run tests
make test
```

## Code Style

- Follow existing code style
- Add comments for complex logic
- Update documentation when adding features
- Write tests for new functionality

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit PR with clear description
6. Address review feedback

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
