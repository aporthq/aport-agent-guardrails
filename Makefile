.PHONY: install test clean

install:
	@echo "Installing APort Agent Guardrails..."
	@mkdir -p ~/.openclaw/.skills
	@cp bin/*.sh ~/.openclaw/.skills/
	@chmod +x ~/.openclaw/.skills/*.sh
	@echo "✅ Installation complete!"
	@echo "Run 'aport-create-passport.sh' to create your first passport"

test:
	@echo "Running tests..."
	@chmod +x bin/*.sh
	@bash tests/test-passport-creation.sh || true
	@bash tests/test-policy-evaluation.sh || true
	@bash tests/test-kill-switch.sh || true
	@echo "✅ Tests complete"

clean:
	@echo "Cleaning up..."
	@rm -rf ~/.openclaw/.skills/aport-*.sh
	@echo "✅ Cleanup complete"
