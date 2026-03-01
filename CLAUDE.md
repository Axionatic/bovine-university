# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Bovine University is a configuration toolkit for Anthropic's [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum). It teaches Claude Code to run autonomously in small, iterative loops using sub-agents for context isolation, inside an OS-level sandbox with `--dangerously-skip-permissions`.

## Validation

Syntax-check the setup script:
```bash
bash -n ralph-setup.sh
```

There are no tests, linters, or build steps. The project is pure bash + markdown templates.

## Architecture

### ralph-setup.sh (1650 lines)

The single deliverable. A self-contained bash script that users `curl | bash` or run locally against their project. All template content is **inlined as heredocs** — the `templates/` directory is the source of truth but the setup script must contain identical copies.

Key sections:
- **Platform gate** (~line 24) — OS detection, dependency checks
- **Ecosystem detection** (~line 606) — scans for package.json, Cargo.toml, go.mod, etc. to configure allowed network domains
- **Framework detection + quality gates** (~line 726) — identifies build tools, test runners, linters; generates quality gate commands
- **Uninstall** (~line 1310) — `ralph-setup.sh --uninstall`
- **Main setup flow** (~line 1379) — interactive prompts for git strategy, PR strategy, review config; writes all files to target project

Template emit functions (`emit_ralph_md`, `emit_settings_template`, `emit_preflight_hook`, etc.) contain heredocs that must stay in sync with `templates/`.

### templates/ (source of truth)

- `RALPH.md` — Rules for Ralph behavior (sub-agent architecture, progress tracking, git/PR strategy options)
- `.claude/settings.local.json.template` — Deny rules, sandbox config, preflight hook registration
- `.claude/hooks/ralph-preflight.sh` — PreToolUse hook that validates environment, manages sessions, auto-creates feature branches
- `.claude/ralph/progress.md.template` — Blank progress file template

### .claude/.ref/ralph-wiggum/

Read-only reference copy of the upstream ralph-wiggum plugin. Used for understanding plugin behavior, not modified.

## Key Design Decisions

- **Templates are inlined in ralph-setup.sh** so the script works standalone via `curl | bash`. Any change to `templates/` must be reflected in the corresponding `emit_*` function in the setup script.
- **RALPH.md uses HTML comments** (`<!--ralph-option:...-->`) as conditional blocks that the setup script strips/keeps based on user choices (git strategy, PR strategy, review config).
- **The preflight hook** fires on `PreToolUse` for the `Skill` tool, only acting on `ralph-loop` invocations. It validates sandbox+bypass-permissions, manages session IDs (`.active` file), archives stale sessions, and auto-branches from main/master.
- **Two-layer security**: OS-level sandbox (bubblewrap/Seatbelt) for network+filesystem isolation, plus application-level deny rules for dangerous commands.

@README.md
