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

Or clone the repo and run locally (works offline — all templates are inlined):

```bash
git clone https://github.com/Axionatic/bovine-university.git
cd your-project && bash /path/to/bovine-university/ralph-setup.sh
```

To uninstall:

```bash
bash ralph-setup.sh --uninstall
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
│   ├── settings.local.json         # Sandbox config + hook registration
│   ├── ralph/
│   │   ├── progress.md             # Task file (optional pre-write)
│   │   ├── start-ralph.sh          # Helper to launch a loop session
│   │   └── .progress-template      # Blank template for session reset
│   └── hooks/
│       ├── ralph-preflight.sh      # Validates environment + auto-branches
│       └── ralph-postsetup.sh      # Rewrites loop prompt to minimal form
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

The sandbox is required — the preflight hook validates it before allowing a loop to start:

```
Sandbox (OS-level, required)
  - Network isolation (only detected ecosystem domains allowed)
  - Filesystem read protection (~/.ssh, ~/.aws, ~/.gnupg, ~/.config/gcloud,
    ~/.kube, ~/.docker, ~/.git-credentials, ~/.config/gh, ~/.npmrc, ~/.netrc)
  - Filesystem write protection (.env, .env.*, *.pem, *.key,
    .claude/settings*, .claude/RALPH.md, .claude/hooks/*)
  - Blocks unsandboxed commands (allowUnsandboxedCommands: false)
  - Uses bubblewrap (Linux) or Seatbelt (macOS)
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

### Step 1: Write Your Task (Optional)

You can pass your task directly in the loop command — no pre-writing needed:

```bash
/ralph-loop "Build a REST API with CRUD operations for a todo app using Express.js with TypeScript" --max-iterations 50 --completion-promise "TASK COMPLETE"
```

The preflight hook captures your task, creates a session progress file, and auto-branches. The postsetup hook rewrites the loop state file so your full task is not re-injected on every iteration — only a minimal "Continue per \<session-file\>" prompt is used.

Alternatively, pre-write your task in `.claude/ralph/progress.md` and use legacy mode:

```bash
/ralph-loop "Continue per .claude/ralph/progress.md" --max-iterations 50 --completion-promise "TASK COMPLETE"
```

### Step 2: Start the Loop

Using the helper script:

```bash
.claude/ralph/start-ralph.sh
```

Or manually:

```bash
claude --dangerously-skip-permissions
/ralph-loop "Your task here" --max-iterations 50 --completion-promise "TASK COMPLETE"
```

The preflight hook automatically:
- Verifies sandbox is enabled
- Verifies `--dangerously-skip-permissions` is active
- Detects and blocks concurrent loops
- Archives stale sessions from cancelled runs
- Creates a session-stamped progress file from your task (inline or from progress.md)
- Creates a `ralph/<task-slug>` branch if on main/master (or switches to it if it already exists)
- Checks for dirty working directory before branching

The postsetup hook then rewrites the loop state file so each iteration re-injects only `Continue per <session-file-path>` — not the full task.

## Monitoring

`ralph-watch.sh` is an optional real-time observer for watching a ralph loop from a second terminal.
It tails the Claude session JSONL log and `.claude/ralph/` session files to display a live event stream:

```bash
bash ralph-watch.sh                        # watch current directory
bash ralph-watch.sh /path/to/your-project  # watch a specific project
```

Requires `jq`. Output is color-coded by event type: session lifecycle, tool calls, sub-agent spawns, errors.

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

With `--dangerously-skip-permissions`, the sandbox still enforces restrictions. We:
- Run inside Claude Code's built-in sandbox for OS-level network and filesystem isolation
- Use a preflight hook that validates the environment and creates the session progress file before allowing a loop to start
- Use a postsetup hook that rewrites the loop state file to a minimal prompt, preventing full task re-injection on every iteration

No external tools, no wrapper scripts, no scratchpad directories. Just `claude --dangerously-skip-permissions`.

## Optional: pr-review-toolkit

Bovine University optionally integrates with Anthropic's [pr-review-toolkit plugin](https://github.com/anthropics/claude-code/tree/main/plugins/pr-review-toolkit) for automated code review during the review phase. It's good but consumes tokens quickly.

## Credits

- The [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) by Anthropic
- The bash loop approach by [Geoffrey Huntley](https://ghuntley.com/claude-agent/)
- Bovine University by [Axionatic](https://github.com/Axionatic)
