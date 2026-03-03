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

### ralph-setup.sh

The single deliverable. A self-contained bash script that users `curl | bash` or run locally against their project. All template content is **inlined as heredocs** — the `templates/` directory is the source of truth but the setup script must contain identical copies.

Key sections:
- **Platform gate** — OS detection, dependency checks
- **Ecosystem detection** — scans for package.json, Cargo.toml, go.mod, etc. to configure allowed network domains
- **Framework detection + quality gates** — identifies build tools, test runners, linters; generates quality gate commands
- **Uninstall** — `ralph-setup.sh --uninstall`
- **Main setup flow** — interactive prompts for git strategy, PR strategy, review config; writes all files to target project

Template emit functions (`emit_ralph_md`, `emit_settings_template`, `emit_preflight_hook`, etc.) contain heredocs that must stay in sync with `templates/`.

### ralph-watch.sh

Optional monitoring utility. Run in a second terminal to watch a loop in real time — tails the Claude session JSONL log and `.claude/ralph/` session files, displaying color-coded events (tool calls, sub-agent spawns, errors). Requires `jq`.

### templates/ (source of truth)

- `RALPH.md` — Rules for Ralph behavior (sub-agent architecture, progress tracking, git/PR strategy options)
- `.claude/settings.local.json.template` — Sandbox config + hook registration
- `.claude/hooks/ralph-preflight.sh` — PreToolUse hook that validates environment, manages sessions, auto-creates feature branches
- `.claude/ralph/progress.md.template` — Blank progress file template

### .claude/.ref/ralph-wiggum/

Read-only reference copy of the upstream ralph-wiggum plugin. Used for understanding plugin behavior, not modified.

## Key Design Decisions

- **Templates are inlined in ralph-setup.sh** so the script works standalone via `curl | bash`. Any change to `templates/` must be reflected in the corresponding `emit_*` function in the setup script.
- **RALPH.md uses HTML comments** (`<!--ralph-option:...-->`) as conditional blocks that the setup script strips/keeps based on user choices (git strategy, PR strategy, review config).
- **The preflight hook** fires on `PreToolUse` for the `Skill` tool, only acting on `ralph-loop` invocations. It validates sandbox+bypass-permissions, manages session IDs (`.active` file), archives stale sessions, and auto-branches from main/master.
- **The postsetup hook** fires on `PostToolUse` for the `Bash` tool. It rewrites the loop state file to replace the full inline task with a minimal `Continue per <session-file-path>` prompt, preventing full task re-injection on every iteration.
- **Sandbox security**: OS-level sandbox (bubblewrap/Seatbelt) provides network isolation (ecosystem-detected domains only) and filesystem protection. Required — preflight hook blocks loops if not enabled.

@README.md
