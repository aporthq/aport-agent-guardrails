.PHONY: install test clean install-git-hooks openclaw-setup

# Interactive OpenClaw setup: prompts for config path, runs passport wizard, installs wrappers
openclaw-setup:
	@chmod +x bin/openclaw 2>/dev/null || true
	@./bin/openclaw

install:
	@echo "Installing APort Agent Guardrails..."
	@mkdir -p ~/.openclaw/.skills
	@cp bin/*.sh ~/.openclaw/.skills/
	@chmod +x ~/.openclaw/.skills/*.sh
	@echo "✅ Installation complete!"
	@echo "Run 'aport-create-passport.sh' to create your first passport"

test:
	@echo "Running tests (unit, OAP, integration)..."
	@chmod +x bin/*.sh bin/lib/*.sh tests/*.sh tests/unit/*.sh tests/frameworks/openclaw/setup.sh 2>/dev/null || true
	@bash tests/run.sh
	@echo "✅ Tests complete"

clean:
	@echo "Cleaning up..."
	@rm -rf ~/.openclaw/.skills/aport-*.sh
	@echo "✅ Cleanup complete"

# Use repo's git hooks so every push runs submodule update check (run once per clone)
install-git-hooks:
	@git config core.hooksPath scripts/git-hooks
	@echo "✅ Git hooks path set to scripts/git-hooks"
	@echo "   Every git push will run scripts/ensure-submodules-updated.sh --update-remote"
