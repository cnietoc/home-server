# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

HMS (Home Server Management System) is a Python 3.11+ CLI tool that manages Docker Compose stacks on a home server. It provides a plugin-based command dispatcher, an APScheduler-based daemon, and TOML-driven configuration to orchestrate infrastructure and application stacks.

## Development Commands

```bash
# Setup
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"

# Run locally
python -m hms --help

# Tests
pytest
pytest tests/path/to/test_file.py::test_name   # single test
pytest --cov=hms                                # with coverage

# Code quality
black hms/          # format (line-length: 100)
ruff check hms/     # lint (target: py311)
mypy hms/           # type checking
```

## Architecture

### Plugin System

The CLI is entirely plugin-driven. Plugins are auto-discovered from `hms/plugins/`:

- **Global plugins** (`hms/plugins/common/`) — system-wide commands (`start`, `stop`, `list`, `install`)
- **Stack plugins** (`hms/plugins/stacks/`) — per-stack commands (`up`, `down`, `logs`, `info`, `backup`)

All plugins inherit from `BasePlugin`, `GlobalPlugin`, or `StackPlugin` and must implement `get_name()`, `get_description()`, `get_help()`, and `run(args)`.

### Configuration

`config.toml` is the single source of truth. At runtime it is deep-merged with `config.default.toml`. Environment variables are injected into Docker Compose templates from config values. Required fields: `global.domain`, `infra.cloudflare.*`, `infra.auth.*`.

### Stack Layout

Each stack lives in `stacks/<name>/` and contains:
- `docker-compose.yml` — with an `x-hms` metadata block (name, description, version)
- Optional `pre-deploy.sh` or `pre-deploy.py` — runs before `docker compose up`
- Data is persisted to `data/<name>/` (bind-mounted, not named volumes)

All stacks join the external `hms-network` managed by the mandatory `infra` stack (Traefik + TinyAuth + Beszel).

### Daemon

`hms/daemon/` runs APScheduler for automated jobs (backups, Cloudflare DNS refresh). Jobs are defined in `config.toml` under `[jobs.*]` and loaded as plugins.

### Key Directories

| Path | Purpose |
|------|---------|
| `hms/cli/` | CLI dispatcher and argument routing |
| `hms/core/` | Base plugin classes and Docker operations |
| `hms/lib/` | Config loader, stack discovery, plugin loader utilities |
| `hms/daemon/` | Background scheduler and optional FastAPI API |
| `stacks/` | Stack definitions (docker-compose + pre-deploy) |
| `core/infra/` | Docker Compose for the infra stack itself |
| `data/` | Runtime persistent data (gitignored) |

## Adding a New Stack

1. Create `stacks/<name>/docker-compose.yml` with an `x-hms` block.
2. Use `${STACK_DATA}`, `${STACK_PREFIX}`, `${DOMAIN}`, `${PUID}`, `${PGID}`, `${TZ}` as variables.
3. Add a `[<name>]` section to `config.default.toml` if the stack needs configuration.
4. Optionally add `stacks/<name>/pre-deploy.sh` for first-run setup.
5. Add the stack to `docs/stacks/README.md` (table entry) and create `docs/stacks/<name>.md`.

## Adding a New Plugin

Create a file in `hms/plugins/common/` (global) or `hms/plugins/stacks/` (stack-scoped). Subclass the appropriate base class and implement the four required methods. The plugin loader discovers it automatically — no registration needed.

## Documentation

Documentation lives in `docs/`. When adding or significantly changing a stack, keep these in sync:

- `docs/stacks/README.md` — add a row to the stacks table
- `docs/stacks/<name>.md` — create/update the stack-specific guide (follow the pattern of existing game server docs like `corekeeper.md` or `terraria.md`)

## Adding a New Config Option

When adding a new config field, always update all three places:

1. `config.default.toml` — add the field with a sensible default or empty string (never `__REQUIRED__` unless truly mandatory)
2. `config.example.toml` — add the field with a placeholder and a short comment explaining the format
3. `docs/installation.md` — document it in the relevant section (mandatory vs optional)

## Logging vs UI Output

HMS separates user-facing output from diagnostic logging:

| What | How | Goes to |
|------|-----|---------|
| Message for the user | `ui.info/ok/warn/err` (`hms/lib/ui.py`) | stdout/stderr, always visible |
| Internal diagnostic | `logger.info/debug` | `logs/hms.log` only — not shown in console |
| Error the user should see | `logger.warning/error/exception` | `logs/hms.log` + stderr (colored) |

Rule of thumb: if a message **must** be seen when the user runs a command, use `ui.*`. If it's internal progress or diagnostic detail, use `logger.*`.
