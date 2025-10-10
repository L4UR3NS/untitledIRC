# Repository Guidance

## Scope
This file applies to the entire repository unless a more specific `AGENTS.md` overrides it.

## General Conventions
- All shell scripts **must** start with `#!/usr/bin/env bash` and enable `set -Eeuo pipefail`.
- Prefer POSIX-compliant tooling available on a minimal Ubuntu 22.04 installation.
- Handle errors gracefully and provide actionable messages.
- Keep scripts idempotent so rerunning them does not cause unintended side effects.
- Use English for all code comments, logs, and documentation.
- When adding new configuration values, ensure they are documented in `.env.example` and consumed via the main automation scripts.
- Update this file whenever repository-level conventions change so future work can reference it quickly.

## Logging & Debugging
- Provide informative logging at key steps using `echo` or `printf` with clear prefixes (e.g., `[INFO]`, `[WARN]`, `[ERROR]`).
- Prefer structured, multi-line status messages for long operations.
- Ensure every shell script passes `shellcheck` locally; CI enforces this via `.github/workflows/shellcheck.yml`.
- Configuration templates live in `unrealircd/templates/` and `anope/templates/` and use `{{PLACEHOLDER}}` syntax rendered by `scripts/install.sh`.
- Systemd unit definitions in `systemd/` are also treated as templates and rendered during installation.

## Testing
- When scripts perform remote calls or system modifications, include verification steps or dry-run options when feasible.
- Always include or update helper scripts under `scripts/` to make validation repeatable.

