# Adding a new framework

This doc describes how to add a new framework so that **passport and config logic are shared** and only framework-specific steps live in the new code. Goal: **&lt;50 lines of bash** plus a config template.

## 1. Shared layer (no copying)

All frameworks use:

- **`bin/lib/common.sh`** — logging, `ROOT_DIR`, `require_cmd`
- **`bin/lib/passport.sh`** — `run_passport_wizard` (delegates to `bin/aport-create-passport.sh`)
- **`bin/lib/config.sh`** — `get_config_dir`, `write_config_template` (creates framework config dir and copies `bin/lib/templates/config.yaml` if present)
- **`bin/lib/detect.sh`** — optional; add your project files so the dispatcher can detect the framework

Do **not** duplicate passport or config logic in the new framework script.

## 2. Add a framework script (&lt;50 lines)

Create **`bin/frameworks/<name>.sh`** (e.g. `bin/frameworks/myframework.sh`):

1. Source lib: `common.sh`, `passport.sh`, `config.sh`
2. Call `run_passport_wizard "$@"`
3. Call `write_config_template <name>` to create the config dir (and optional `config.yaml`)
4. Print **next steps** (snippet + doc link)

Example (same pattern as LangChain/CrewAI/n8n):

```bash
#!/usr/bin/env bash
# MyFramework installer/setup

LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")/../lib" && pwd)"
source "$LIB/common.sh"
source "$LIB/passport.sh"
source "$LIB/config.sh"

run_setup() {
  log_info "Setting up APort guardrails for MyFramework..."
  run_passport_wizard "$@"
  config_dir="$(write_config_template myframework)"
  echo ""
  echo "  Next steps (MyFramework):"
  echo "  1. Config written to: $config_dir"
  echo "  2. ... (framework-specific snippet)"
  echo "  See: docs/frameworks/myframework.md"
  echo ""
}

run_setup "$@"
```

Add **`get_config_dir`** support in `bin/lib/config.sh` for your framework name and default path (e.g. `$HOME/.aport/myframework`).

## 3. Add integration directory

Create **`integrations/<name>/`** with:

- **README.md** — What this integration does; where the real implementation lives (e.g. `python/myframework_adapter/`, or “plugin in `extensions/`”).
- **Middleware / plugin / examples** — Framework-specific code or pointers. Can be stubs that reference the actual package (e.g. `python/langchain_adapter/`).

Optionally add **`bin/lib/templates/<name>.yaml`** if your framework needs a different config template; otherwise the shared `config.yaml` in `bin/lib/templates/` is copied by `write_config_template` for supported frameworks.

## 4. Wire up the dispatcher

- In **`bin/agent-guardrails`**, the dispatcher runs `bin/frameworks/<framework>.sh` when `--framework=<name>` or the first arg is `<name>`. Adding `bin/frameworks/myframework.sh` is enough for `--framework=myframework`.
- If you want **detection from the project directory**, add your project files (e.g. `myframework.toml`) to **`bin/lib/detect.sh`** in `detect_frameworks_list` / `detect_framework`.

## 5. Add a framework doc and tests

- **`docs/frameworks/<name>.md`** — Setup, config location, suspend (kill switch) = passport status, next steps.
- **Integration test:** In **`tests/frameworks/<name>/setup.sh`**, run the CLI (e.g. `APORT_FRAMEWORK=myframework` or `--framework=myframework` with non-interactive inputs) and assert the expected config directory and files exist.

## Checklist

- [ ] `bin/frameworks/<name>.sh` &lt;50 lines; only sources lib + wizard + config + next steps
- [ ] `bin/lib/config.sh`: `get_config_dir` handles `<name>`; `write_config_template` can create its dir (template copy is automatic if `bin/lib/templates/config.yaml` exists)
- [ ] `integrations/<name>/README.md` (and optional middleware/examples)
- [ ] `docs/frameworks/<name>.md`
- [ ] `tests/frameworks/<name>/setup.sh` (run CLI, assert config)

## Reference: existing frameworks

| Framework  | Script (lines) | Integration dir        | Notes                          |
|-----------|----------------|-------------------------|--------------------------------|
| OpenClaw  | 19 (delegates) | integrations/openclaw/  | Full installer in `bin/openclaw` |
| LangChain | 30             | integrations/langchain/ | Python middleware in python/   |
| CrewAI    | 31             | integrations/crewai/    | Python decorator in python/    |
| n8n       | 28             | integrations/n8n/        | Custom node / HTTP + credentials |
