# bovine-university
> "When I grow up, I'm going to Bovine University!"
>
> \- Ralph Wiggum, S07E05

Ralph Wiggum is a sweet kid. Sure, he has some issues. Don't we all?

Unfortunately, Ralph is not a good match for Claude Code.
- Ralph likes to keep it basic. Claude is a bit of a braniac.
- Ralph prefers short, bite-sized tasks. Claude likes to do everything, all at once.
- Ralph likes to be dangerous (chuckles). Claude takes great care to be safe. Usually.
- Ralph is quick to give up when something doesn't work. Claude will hammer away until your wallet cries out in pain.
- Ralph quite happily forgets things. Claude tries very hard to remember everything (but sometimes forgets anyway).

Bovine University is a simple set of rules to teach Anthropic's [official ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) to be more ralph-like and less claude-like.
If you've tried using the plugin, you might have noticed:
- Even though Ralph is supposed to do things in small, iterative loops, Claude tries to complete the entire prompt in one go.
- Even though Ralph is supposed to run autonomously, Claude frequently pauses and asks for permissions.
- Even though Ralph is supposed to keep context short by looping rather than compacting, Claude often runs-compacts-runs-compacts-runs-compacts.

## Caveat Emptor

Bovine University runs Claude Code with `--dangerously-skip-permissions` inside an OS-level sandbox. This means Claude can execute **any command** that isn't explicitly denied. The sandbox restricts network and filesystem access, but Claude has full control within your project directory.

**Recommendations:**
- Use feature branches (the preflight hook creates them automatically)
- Enable GitHub branch protection on main
- For maximum safety, run in ephemeral/disposable environments

**Platform requirements:** Linux (bubblewrap) or macOS (Seatbelt). For Windows, use [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Axionatic/bovine-university/main/ralph-setup.sh | bash
```

The setup script will:
1. **Detect your ecosystem** — scans for package.json, Cargo.toml, go.mod, pyproject.toml, etc. and configures allowed network domains accordingly
2. **Detect frameworks** — identifies build tools, test runners, and linters to set up quality gate commands
3. Ask about **git strategy** (never / once / each / squash)
4. Ask about **PR strategy** (open PR / open PR and auto-merge / keep local)
5. Ask about **code review** (pr-review-toolkit yes/no)

## What Gets Installed

```
your-project/
├── .claude/
│   ├── RALPH.md                    # Rules for Ralph behavior
│   ├── settings.local.json         # Deny rules + sandbox config
│   ├── ralph/
│   │   ├── progress.md             # Task file (edit before starting)
│   │   └── .progress-template      # Blank template for session reset
│   └── hooks/
│       └── ralph-preflight.sh      # Validates environment + auto-branches
└── CLAUDE.md                       # Updated to reference RALPH.md
```

At runtime, the preflight hook also creates:
- `.claude/ralph/.active` — current session ID marker
- `.claude/ralph/progress-<session-id>.md` — session-stamped progress file
- `.claude/ralph/archive/` — archived progress files from previous sessions (max 10)

The ralph-wiggum plugin creates `.claude/ralph-loop.local.md` while a loop is running. The preflight hook uses this to detect and block concurrent loops.

## How It Works: Sub-Agent Architecture

The key insight is that **sub-agents provide context isolation**. Instead of the main session doing all the work (and accumulating context), we use a parent orchestrator that:

1. Reads the session progress file to determine the next step
2. Spawns a sub-agent with a minimal, step-specific prompt
3. Receives only the summary back (not the full working context)
4. Updates the session progress file with results
5. Stops (loop restarts fresh)

```
┌─────────────────────────────────────────────────────────────┐
│  Parent Orchestrator (minimal context)                      │
│  ├── Reads session progress file                            │
│  ├── Determines next step                                   │
│  ├── Generates minimal, step-specific prompt                │
│  ├── Spawns sub-agent ──────────┐                           │
│  │                              ▼                           │
│  │                    ┌──────────────────────┐              │
│  │                    │  Sub-Agent           │              │
│  │                    │  (isolated context)  │              │
│  │                    │  - Does actual work  │              │
│  │                    │  - Full tool access  │              │
│  │                    │  - Returns summary   │              │
│  │                    └──────────────────────┘              │
│  │                               │                          │
│  ├── Receives summary only ◄─────┘                          │
│  ├── Updates session progress file                          │
│  └── Loop or complete                                       │
└─────────────────────────────────────────────────────────────┘
```

### Why This Matters

The official ralph-wiggum plugin has two context issues:

1. **Context accumulation**: The stop hook restarts within the SAME session, so context accumulates across iterations
2. **Prompt duplication**: The SAME prompt is re-injected every iteration, wasting tokens

The sub-agent approach solves both:
- Sub-agent context is isolated and discarded after each step
- The prompt is minimal ("Continue per progress.md") — task details live in the file

## Security Model

Two layers provide defense in depth:

```
Layer 1: Built-in Sandbox (OS-level)
  - Network isolation (only detected ecosystem domains allowed)
  - Filesystem read protection (~/.ssh, ~/.aws, ~/.gnupg, ~/.config/gcloud,
    ~/.kube, ~/.docker, ~/.git-credentials, ~/.config/gh, ~/.npmrc, ~/.netrc)
  - Filesystem write protection (.env, .env.*, *.pem, *.key,
    .claude/settings*, .claude/RALPH.md, .claude/hooks/*)
  - Blocks unsandboxed commands (allowUnsandboxedCommands: false)
  - Uses bubblewrap (Linux) or Seatbelt (macOS)

Layer 2: Deny Rules (Application-level)
  - Blocks: sudo, su, privilege escalation (chmod +s, chown)
  - Blocks: shell interpreters (bash -c, sh -c, zsh -c, dash -c, ksh -c)
  - Blocks: inline code execution (python -c, perl -e, ruby -e, node -e)
  - Blocks: pipe-to-shell (curl|bash, curl|sh, wget|bash, wget|sh)
  - Blocks: force-push to main/master (--force, -f, --force-with-lease, +refspec)
  - Blocks: eval, exec
```

The preflight hook validates the environment (sandbox enabled, bypass-permissions active) before allowing a ralph-loop to start.

## Ecosystem Detection

The setup script auto-detects your project's language ecosystems and frameworks:

| What | How |
|------|-----|
| **Ecosystems** | Scans for indicator files (package.json, Cargo.toml, go.mod, etc.) |
| **Network domains** | Maps ecosystems to registry domains (npmjs.org, crates.io, pypi.org, etc.) |
| **Frameworks** | Checks dependencies and config files for specific frameworks |
| **Quality gates** | Generates build/test/lint commands based on detected frameworks |

Supported ecosystems: Node.js, TypeScript, Deno, Bun, Python, Rust, Go, Java/Kotlin, Ruby, PHP, Dart/Flutter, C#/.NET, C/C++, Swift, R, Scala, Lua.

## Usage

### Step 1: Write Your Task

Edit `.claude/ralph/progress.md` and fill in the Task section:

```markdown
## Task
Build a REST API with CRUD operations for a todo app.
Use Express.js with TypeScript. Include input validation,
comprehensive tests, error handling, and API documentation.

## Plan
(to be generated by first iteration)

## Current
Step: 0
Status: not_started

## Completed
(none yet)

## Blockers
(none)

## Iteration Log
(pending)
```

> **Note:** When the loop starts, the preflight hook copies your task into a session-stamped file (`progress-<session-id>.md`) and resets `progress.md` to a blank template. Claude works with the session file, not `progress.md` directly.

### Step 2: Start the Loop

```bash
claude --dangerously-skip-permissions
/ralph-loop "Continue per .claude/ralph/progress.md" --max-iterations 50 --completion-promise "TASK COMPLETE"
```

The preflight hook automatically:
- Verifies sandbox is enabled
- Verifies `--dangerously-skip-permissions` is active
- Detects and blocks concurrent loops
- Archives stale sessions from cancelled runs
- Creates a session-stamped progress file from your task
- Creates a `ralph/<task-slug>` branch if on main/master (or switches to it if it already exists)
- Checks for dirty working directory before branching

Only "Continue per .claude/ralph/progress.md" gets duplicated each iteration — the actual task lives in the file.

## What Do We Teach Claude at BU?

- You are in a loop. Do one single step of your task, then stop. The loop will handle the rest.
- **Use sub-agents**: Never do implementation work directly. Spawn a sub-agent for each step.
- **Update the session progress file before stopping** — this is the single most important rule. If it isn't updated, the next iteration repeats the same work.
- **Keep prompts minimal**: Generate step-specific prompts for sub-agents. Never pass the full task description repeatedly.
- If the current step is taking a long time, check your context window. If it's > 50% full, stop immediately and let the loop take over.
- **Document blockers**: If truly blocked, log it in the progress file, skip to the next unblocked step, and stop.
- First loop plans. Then implement (one step per loop). Then review. Then fix issues. Then complete (push, PR, completion promise).
- **Completion promise**: When done, output `<promise>YOUR_PHRASE</promise>` (XML tags required).

## How Can We Be Fully Autonomous?

With `--dangerously-skip-permissions`, deny rules still take precedence. We:
- Run inside Claude Code's built-in sandbox for OS-level network and filesystem isolation
- Define deny rules in `.claude/settings.local.json` to block dangerous commands (sudo, su, shell interpreters, inline code execution, pipe-to-shell, force-push to main, privilege escalation)
- Use a preflight hook that validates the environment before allowing a loop to start

No external tools, no wrapper scripts, no scratchpad directories. Just `claude --dangerously-skip-permissions`.

## Optional: pr-review-toolkit

Bovine University optionally integrates with Anthropic's [pr-review-toolkit plugin](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) for automated code review during the review phase. It's good but consumes tokens quickly.

## Credits

- The [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) by Anthropic
- The bash loop approach by [Geoffrey Huntley](https://ghuntley.com/claude-agent/)
- Bovine University by [Axionatic](https://github.com/Axionatic)
