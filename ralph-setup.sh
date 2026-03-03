#!/bin/bash
set -e

# Bovine University Setup Script
# Configures any project for the ralph-wiggum plugin
# https://github.com/Axionatic/bovine-university

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ========================================
# Platform gate
# ========================================
detect_os() {
  case "$(uname)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

OS=$(detect_os)
if [[ "$OS" == "windows" ]]; then
  echo ""
  echo -e "${RED}Bovine University requires Linux or macOS for OS-level sandboxing.${NC}"
  echo ""
  echo "To use on Windows:"
  echo "  1. Install WSL2: wsl --install"
  echo "  2. Open a WSL2 terminal"
  echo "  3. Re-run this setup script from within WSL2"
  exit 1
fi

# Check dependencies
check_deps() {
  command -v jq >/dev/null 2>&1 || error "jq is required. Install: brew install jq / apt install jq"
  command -v curl >/dev/null 2>&1 || warn "curl not found (not required for setup, but needed for the install one-liner)"
  command -v git >/dev/null 2>&1 || error "git is required"
  if ! command -v claude >/dev/null 2>&1; then
    warn "claude CLI not found. Install: npm install -g @anthropic-ai/claude-code"
  else
    if ! claude plugins list 2>/dev/null | grep -q 'ralph-wiggum'; then
      warn "ralph-wiggum plugin not found. Install: claude plugins add ralph-wiggum"
    else
      success "ralph-wiggum plugin detected"
    fi
  fi
}

# Find project root (look for .git, package.json, etc.)
find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]] || [[ -f "$dir/package.json" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/go.mod" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  echo "$PWD"
}

# Emit template content — inlined from templates/ directory.
# Source of truth is the templates/ directory in the repo; keep these in sync.

emit_ralph_md() {
  cat <<'TEMPLATE_EOF'
# Ralph Loop Guidelines

Autonomous development via [ralph-wiggum](https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md). Rules here, task in progress file.

## Core Rules (Parent Orchestrator)

1. **USE SUB-AGENTS**: Never do implementation work directly. Use the **Task tool** to spawn a sub-agent for each step. This keeps your context minimal.
2. **One step per iteration**: Determine ONE logical step, spawn sub-agent, receive summary, update progress. Then stop.
3. **Context window**: If context is > 50% full, stop immediately and let the loop restart fresh.
4. **Minimal prompts**: Generate step-specific prompts for sub-agents. Never pass the full task description repeatedly.
5. **CRITICAL: Update your session progress file BEFORE stopping.** Every iteration MUST end with an update to your session progress file (path in `.claude/ralph/.current-progress`). The next iteration reads this file to determine what to do — if you don't update it, the next iteration will repeat the same work or get confused. Update the Current section, move completed items to Completed, and log the step.
6. **Sandbox + bypass mode**: You are running with `--dangerously-skip-permissions` inside a sandbox. Deny rules in `.claude/settings.local.json` block dangerous commands. The sandbox blocks unauthorized network and filesystem access. Sub-agents inherit all sandbox restrictions and deny rules from the parent session.
7. **Feature branches**: The preflight hook auto-creates a `ralph/<task-slug>` branch when on main/master. Do not force-push to main or master.
8. **Document blockers**: If truly blocked, log the issue in the Blockers section of your session progress file, skip to the next unblocked step, and stop. The next iteration will pick up from there.
9. **Completion promise format**: When task is complete, output `<promise>YOUR_PHRASE</promise>` (XML tags required). The parent orchestrator must output this directly — do not delegate to a sub-agent. The phrase is case-sensitive and must match exactly.

## Session Management

The preflight hook creates a session-stamped progress file for each run:
- **Inline mode**: parses your task from the `/ralph-loop` prompt argument, writes it into `progress-<session-id>.md`
- **Legacy mode**: copies your task from `progress.md` into `progress-<session-id>.md`, resets `progress.md` to blank template
- Writes the session ID to `.claude/ralph/.active`
- Writes the full path to `.claude/ralph/.current-progress`

The postsetup hook then rewrites the loop state file so each iteration re-injects
`Continue per <session-file-path>` rather than the full task description.

**Resolving your progress file (every iteration):**
Read `.claude/ralph/.current-progress` to get the full path to your session progress file. Do NOT use `progress.md`.

**On task completion:** Delete `.claude/ralph/.active` and `.claude/ralph/.current-progress` after outputting the completion promise.

## Sub-Agent Prompt Template

Use the **Task tool** to spawn sub-agents. Provide this minimal prompt format:

```
Step: [Specific action to take]
Location: [File path(s) if applicable]
Context: [1-2 sentences of relevant context]
Report: [What to return - summary, line count, status, etc.]
```

## Progress Tracking

**Enabled**: Progress tracked in session progress file (path in `.claude/ralph/.current-progress`). This is the source of truth.

### Workflow (with sub-agents)
1. **Plan** - First iteration: Spawn sub-agent to analyze task, produce step list
2. **Implement** - Each iteration: Spawn sub-agent for ONE step, update progress
3. **Review** - After implementation: Spawn review sub-agent (optionally with pr-review-toolkit)
4. **Fix** - Spawn sub-agent for each fix
5. **Complete** - Push, create PR if configured, output completion promise

### Progress File Format
```markdown
## Task
[Original task description - written once, never duplicated in prompts]

## Plan
- [ ] Step 1: Description
- [ ] Step 2: Description
- [ ] Step 3: Description

## Current
Step: 2
Status: in_progress
Sub-agent: Implementing createTodo function

## Completed
- [x] Step 1: Set up API routes (iteration 2)
  Summary: Created src/api/index.ts with GET/POST/PUT/DELETE routes

## Blockers
- [Issue and why it's blocked]

## Step Log
- Step 1: Planning phase, created 5 steps
- Step 2: Completed step 1 (API routes)
- Step 3: Working on step 2 (createTodo)
```

### Sub-Agent Interaction Pattern
```
Parent reads session progress file -> "Step 2 is next: Implement createTodo"
                         |
                         v
Parent spawns sub-agent: "Implement createTodo in src/api/todos.ts.
                          API routes already set up in src/api/index.ts.
                          Return: summary of what was implemented"
                         |
                         v
Sub-agent works (isolated context)
                         |
                         v
Sub-agent returns: "Implemented createTodo with validation, 45 lines"
                         |
                         v
Parent updates session progress file with summary
                         |
                         v
Parent stops (loop restarts fresh)
```

<!--ralph-option:git_strategy
{
  "id": "git_strategy",
  "question": "Git commit strategy?",
  "default": 4,
  "options": [
    {"value": "never", "label": "Never - I'll handle git myself"},
    {"value": "once", "label": "Once - Commit when task is complete"},
    {"value": "each", "label": "Each loop - Commit after every iteration"},
    {"value": "squash", "label": "Squash - Commit each loop, squash when done (Recommended)"}
  ]
}
-->

## Git Strategy

<!--ralph-option:git_never-->
**Manual**: Do not make commits. User handles all git operations.
<!--/ralph-option:git_never-->

<!--ralph-option:git_once-->
**On Completion**: Commit once when the task is fully complete.
- Use descriptive commit message summarizing all changes
<!--/ralph-option:git_once-->

<!--ralph-option:git_each-->
**Each Loop**: Commit after every iteration.
- Prefix: `ralph: <brief description>`
- After each step: (1) update session progress file, (2) run quality gates, (3) `git add` + `git commit`, (4) stop
- Creates detailed history, may need manual cleanup
<!--/ralph-option:git_each-->

<!--ralph-option:git_squash-->
**Squash**: Commit after each loop, squash when task completes.
- During: `WIP: ralph - <step description>`
- Final: Squash all WIP commits into a single descriptive commit:
  ```bash
  git reset --soft $(git merge-base HEAD <base-branch>) && git commit -m "<descriptive message>"
  ```
  where `<base-branch>` is the branch you branched from (typically `main` or `master`).
<!--/ralph-option:git_squash-->

<!--ralph-option:pr_open-->
**Branch Strategy**: Push branch and open a PR when task is complete.
<!--/ralph-option:pr_open-->

<!--ralph-option:pr_merge-->
**Branch Strategy**: Push branch, open a PR, and auto-merge if there are no conflicts.
<!--/ralph-option:pr_merge-->

<!--ralph-option:pr_no-->
**Branch Strategy**: Work in a feature branch but do not push or open a PR.
<!--/ralph-option:pr_no-->

<!--/ralph-option:git_strategy-->

### On Task Completion
- Commit final changes (per git strategy above)
<!--ralph-option:pr_push-->
- Push branch to origin: `git push -u origin HEAD`
- Open PR if none exists:
  - Check: `gh pr list --head $(git branch --show-current) --json number`
  - Create: `gh pr create --fill`
<!--/ralph-option:pr_push-->
<!--ralph-option:pr_automerge-->
- Auto-merge if no conflicts: `gh pr merge --auto --merge`
<!--/ralph-option:pr_automerge-->
<!--ralph-option:pr_push-->
- **If push or PR creation fails** (e.g. `gh` not available, auth issues, network blocked): log the failure in your session progress file and output a warning: `⚠️ Could not push/create PR automatically. Please push the branch and open a PR manually.` Do NOT let this block the completion promise.
<!--/ralph-option:pr_push-->
- **If any git/push/PR operation fails**: log the failure in your session progress file and output a warning. Do NOT let it block the completion promise.
- Output completion promise
- Delete `.claude/ralph/.active` and `.claude/ralph/.current-progress`

<!--ralph-option:pr_review_toolkit
{
  "id": "pr_review_toolkit",
  "question": "Use pr-review-toolkit for code review?",
  "default": 1,
  "options": [
    {"value": "yes", "label": "Yes - Run code review agents during review phase (Recommended)"},
    {"value": "no", "label": "No - Skip automated review"}
  ]
}
-->

## Code Review

<!--ralph-option:pr_review_yes-->
Use pr-review-toolkit agents during the **review phase** (workflow step 3, after all implementation steps are complete):
- `code-reviewer` - Check adherence to guidelines
- `silent-failure-hunter` - Find error handling issues
- `comment-analyzer` - Verify comment accuracy

**Invocation:** Only invoke during review iterations. Do not invoke during planning or implementation.
**Fallback:** If pr-review-toolkit agents are unavailable (tool not found, plugin not installed), fall back to manual self-review: re-read all changed files and check for obvious issues, missed edge cases, and guideline violations.
Note: Consumes additional tokens. Disable if context is limited.
<!--/ralph-option:pr_review_yes-->

<!--ralph-option:pr_review_no-->
Skip automated review. Manual review only.
<!--/ralph-option:pr_review_no-->

<!--/ralph-option:pr_review_toolkit-->

## Quality Gates
<!--ralph-option:quality_gates-->
Run these commands to validate changes before committing:
<!--ralph-quality-gate-commands-->
All quality gate commands must exit 0 before committing. If any gate fails:
1. Fix the issues identified by the failing gate
2. Re-run the gate to confirm the fix
3. Only then proceed to commit
<!--/ralph-option:quality_gates-->

## Invocation

### Pass your task directly in the prompt

```bash
/ralph-loop "Your task description here" --max-iterations %%MAX_ITERATIONS%% --completion-promise "%%COMPLETION_PHRASE%%"
```

The preflight hook captures your task, creates a session progress file, and auto-branches.
The postsetup hook rewrites the loop state file to a minimal prompt — your full task
is not re-injected on every iteration.

### Legacy mode (pre-written task)

If you prefer to write your task in `progress.md` first:

```bash
/ralph-loop "Continue per .claude/ralph/progress.md" --max-iterations %%MAX_ITERATIONS%% --completion-promise "%%COMPLETION_PHRASE%%"
```
TEMPLATE_EOF
}

emit_progress_template() {
  cat <<'TEMPLATE_EOF'
## Task
[Describe your task here. Be specific about requirements, constraints, and expected outcomes.]

## Plan
(to be generated by first iteration)

## Current
Step: 0
Status: not_started

## Completed
(none yet)

## Blockers
(none)

## Step Log
(pending)
TEMPLATE_EOF
}

emit_settings_template() {
  cat <<'TEMPLATE_EOF'
{
  "permissions": {
    "deny": [
      "Bash(sudo:*)", "Bash(su :*)",
      "Bash(chmod +s:*)", "Bash(chmod u+s:*)", "Bash(chown:*)",
      "Bash(eval:*)", "Bash(exec:*)",
      "Bash(bash -c:*)", "Bash(sh -c:*)",
      "Bash(zsh -c:*)", "Bash(dash -c:*)", "Bash(ksh -c:*)",
      "Bash(python -c:*)", "Bash(python3 -c:*)",
      "Bash(perl -e:*)", "Bash(perl -E:*)",
      "Bash(ruby -e:*)",
      "Bash(node -e:*)", "Bash(node --eval:*)",
      "Bash(curl * | bash:*)", "Bash(curl * | sh:*)",
      "Bash(wget * | bash:*)", "Bash(wget * | sh:*)",
      "Bash(git push --force origin main:*)",
      "Bash(git push --force origin master:*)",
      "Bash(git push -f origin main:*)",
      "Bash(git push -f origin master:*)",
      "Bash(git push --force-with-lease origin main:*)",
      "Bash(git push --force-with-lease origin master:*)",
      "Bash(git push origin +refs/heads/main:*)",
      "Bash(git push origin +refs/heads/master:*)",
      "Bash(git push origin +main:*)",
      "Bash(git push origin +master:*)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "allowedDomains": []
    },
    "filesystem": {
      "denyRead": [
        "~/.ssh", "~/.aws", "~/.gnupg", "~/.config/gcloud",
        "~/.kube", "~/.docker", "~/.git-credentials",
        "~/.config/gh", "~/.npmrc", "~/.netrc"
      ],
      "denyWrite": [
        ".claude/settings*", ".claude/RALPH.md",
        ".claude/hooks/*",
        ".env", ".env.*", "*.pem", "*.key"
      ]
    }
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/ralph-preflight.sh\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/ralph-postsetup.sh\""
          }
        ]
      }
    ]
  }
}
TEMPLATE_EOF
}

emit_preflight_hook() {
  cat <<'TEMPLATE_EOF'
#!/bin/bash
# Ralph preflight hook — validates environment and auto-creates feature branch.
# Fires on PreToolUse for the Skill tool; ignores everything except ralph-loop.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')

# Only care about ralph-loop invocations
if [[ "$TOOL" != "Skill" || "$SKILL" != *"ralph-loop"* ]]; then
  echo "ralph-preflight: skipping (tool=$TOOL, skill=$SKILL)" >&2
  exit 0
fi

# --- Validate environment ---
MODE=$(echo "$INPUT" | jq -r '.permission_mode')
SETTINGS="$CLAUDE_PROJECT_DIR/.claude/settings.local.json"
SANDBOX=$(jq -r '.sandbox.enabled // false' "$SETTINGS" 2>/dev/null)

ERRORS=""
if [[ "$MODE" == "null" || -z "$MODE" ]]; then
  ERRORS+="• permission_mode field not found (unexpected platform change?)\n"
elif [[ "$MODE" != "bypassPermissions" ]]; then
  ERRORS+="• --dangerously-skip-permissions is not active (mode: $MODE)\n"
fi
[[ "$SANDBOX" != "true" ]] && ERRORS+="• Sandbox is not enabled in .claude/settings.local.json\n"

if [[ -n "$ERRORS" ]]; then
  jq -n --arg msg "$(printf "Ralph loop requires BOTH bypass permissions AND sandbox:\n${ERRORS}\nStart claude with: claude --dangerously-skip-permissions\nEnsure sandbox.enabled is true in .claude/settings.local.json")" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $msg
      }
    }'
  exit 0
fi

# --- Pre-session checks ---
RALPH_DIR="$CLAUDE_PROJECT_DIR/.claude/ralph"
ACTIVE_FILE="$RALPH_DIR/.active"
ARCHIVE_DIR="$RALPH_DIR/archive"
TEMPLATE_FILE="$RALPH_DIR/.progress-template"

# Check for concurrent loop or stale session
LOOP_MARKER="$CLAUDE_PROJECT_DIR/.claude/ralph-loop.local.md"
if [[ -f "$ACTIVE_FILE" ]]; then
  if [[ -f "$LOOP_MARKER" ]]; then
    # A loop is currently running — deny
    jq -n --arg msg "A ralph-loop is already running (session: $(cat "$ACTIVE_FILE")). Stop the current loop before starting a new one." \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $msg
        }
      }'
    exit 0
  fi

  # No loop running but .active exists — stale from cancelled run, clean up
  OLD_SESSION=$(cat "$ACTIVE_FILE")
  OLD_PROGRESS="$RALPH_DIR/progress-${OLD_SESSION}.md"
  if [[ -f "$OLD_PROGRESS" ]]; then
    mkdir -p "$ARCHIVE_DIR"
    mv "$OLD_PROGRESS" "$ARCHIVE_DIR/"
    # Rotate archive: keep only 10 most recent
    if [[ -d "$ARCHIVE_DIR" ]]; then
      ARCHIVE_COUNT=$(ls -1 "$ARCHIVE_DIR" 2>/dev/null | wc -l)
      if [[ "$ARCHIVE_COUNT" -gt 10 ]]; then
        ls -1t "$ARCHIVE_DIR" | tail -n +11 | while read -r old; do
          rm -f "$ARCHIVE_DIR/$old"
        done
      fi
    fi
    echo "Archived stale session: $OLD_SESSION" >&2
  fi
  rm -f "$ACTIVE_FILE"
  rm -f "$RALPH_DIR/.current-progress"
fi

# --- Parse task from args ---
ARGS_RAW=$(echo "$INPUT" | jq -r '.tool_input.args // empty')

# Pass-through for help flags — don't set up a session
if [[ "$ARGS_RAW" == "--help" || "$ARGS_RAW" == "-h" ]]; then
  exit 0
fi

# Word-split the args string respecting shell quoting
# (safe: deny rules apply to Claude's Bash tool calls, not hook script internals)
eval set -- $ARGS_RAW 2>/dev/null || true

TASK_PARTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations)     shift 2 ;;
    --completion-promise) shift 2 ;;
    *)                    TASK_PARTS+=("$1"); shift ;;
  esac
done
TASK_FROM_ARGS="${TASK_PARTS[*]}"

# Detect legacy mode: user passed "Continue per .claude/ralph/progress.md"
if [[ "$TASK_FROM_ARGS" == Continue\ per\ * ]]; then
  INLINE_MODE=false
  TASK_CONTENT=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;p;}' "$RALPH_DIR/progress.md" | sed '/^$/d')
  if [[ -z "$TASK_CONTENT" ]] || echo "$TASK_CONTENT" | grep -q '\[Describe your task here'; then
    jq -n --arg msg "$(printf "progress.md has no task defined.\n\nEdit .claude/ralph/progress.md and fill in the Task section, or\npass your task directly: /ralph-loop \"Your task here\"")" \
      '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $msg } }'
    exit 0
  fi
  TASK_LINE=$(echo "$TASK_CONTENT" | head -1)
else
  INLINE_MODE=true
  TASK_FROM_ARGS_TRIMMED=$(echo "$TASK_FROM_ARGS" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [[ -z "$TASK_FROM_ARGS_TRIMMED" ]]; then
    jq -n --arg msg "$(printf "No task provided.\n\nUsage: /ralph-loop \"Your task here\" --max-iterations 50 --completion-promise \"TASK COMPLETE\"")" \
      '{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $msg } }'
    exit 0
  fi
  TASK_CONTENT="$TASK_FROM_ARGS_TRIMMED"
  TASK_LINE=$(echo "$TASK_FROM_ARGS_TRIMMED" | head -1)
fi

# Check dirty working directory BEFORE creating session files
# (avoids data loss if branching is denied after files are written)
CURRENT_BRANCH=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null)

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  SLUG=$(echo "${TASK_LINE:-unnamed-task}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//' \
    | cut -c1-50)

  BRANCH="ralph/$SLUG"

  if ! git -C "$CLAUDE_PROJECT_DIR" diff --quiet 2>/dev/null || \
     ! git -C "$CLAUDE_PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    jq -n --arg msg "Cannot create branch '$BRANCH': working directory has uncommitted changes. Commit or stash changes first." \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $msg
        }
      }'
    exit 0
  fi
fi

# --- Session management (all pre-checks passed) ---
SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"
echo "$SESSION_ID" > "$ACTIVE_FILE"
echo "$RALPH_DIR/progress-${SESSION_ID}.md" > "$RALPH_DIR/.current-progress"

if [[ "$INLINE_MODE" == "true" ]]; then
  # Write session progress file pre-populated with the inline task
  cat > "$RALPH_DIR/progress-${SESSION_ID}.md" <<PROGRESS_EOF
## Task
${TASK_CONTENT}

## Plan
(to be generated by first iteration)

## Current
Step: 0
Status: not_started

## Completed
(none yet)

## Blockers
(none)

## Step Log
(pending)
PROGRESS_EOF
  # progress.md is untouched in inline mode
else
  # Legacy: copy progress.md → session file, reset progress.md from template
  cp "$RALPH_DIR/progress.md" "$RALPH_DIR/progress-${SESSION_ID}.md"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$RALPH_DIR/progress.md"
  else
    echo "Warning: .progress-template not found, progress.md not reset" >&2
  fi
fi

echo "Session started: $SESSION_ID" >&2

# --- Auto-create feature branch if on main/master ---
# (dirty dir already checked above)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  # Check if branch already exists
  if git -C "$CLAUDE_PROJECT_DIR" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git -C "$CLAUDE_PROJECT_DIR" checkout "$BRANCH" 2>&1 >&2
    echo "Switched to existing branch: $BRANCH" >&2
  else
    if ! git -C "$CLAUDE_PROJECT_DIR" checkout -b "$BRANCH" 2>&1 >&2; then
      jq -n --arg msg "Failed to create branch '$BRANCH'. Check git status and try again." \
        '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $msg
          }
        }'
      exit 0
    fi
    echo "Created branch: $BRANCH" >&2
  fi
fi

exit 0
TEMPLATE_EOF
}

emit_postsetup_hook() {
  cat <<'TEMPLATE_EOF'
#!/bin/bash
# Ralph postsetup hook — rewrites ralph-loop state file to use minimal session prompt.
# Fires on PostToolUse for Bash; only acts on setup-ralph-loop.sh invocations.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
CMD=$(echo "$INPUT"  | jq -r '.tool_input.command // empty')

# Only care about setup-ralph-loop.sh calls
if [[ "$TOOL" != "Bash" ]] || ! echo "$CMD" | grep -q 'setup-ralph-loop\.sh'; then
  exit 0
fi

STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/ralph-loop.local.md"
PROGRESS_PTR="$CLAUDE_PROJECT_DIR/.claude/ralph/.current-progress"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ralph-postsetup: state file not found, skipping" >&2
  exit 0
fi
if [[ ! -f "$PROGRESS_PTR" ]]; then
  echo "ralph-postsetup: .current-progress not found, skipping" >&2
  exit 0
fi

SESSION_PROGRESS_PATH=$(cat "$PROGRESS_PTR")

# Extract frontmatter (lines 1 through second "---" inclusive)
SECOND_DASH=$(grep -n '^---$' "$STATE_FILE" | awk -F: 'NR==2{print $1}')
if [[ -z "$SECOND_DASH" ]]; then
  echo "ralph-postsetup: cannot parse state file frontmatter, skipping" >&2
  exit 0
fi
FRONTMATTER=$(head -n "$SECOND_DASH" "$STATE_FILE")

# Rewrite state file: same frontmatter, minimal prompt
TEMP_FILE="${STATE_FILE}.tmp.$$"
printf '%s\n\nContinue per %s\n' "$FRONTMATTER" "$SESSION_PROGRESS_PATH" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

echo "ralph-postsetup: loop prompt → Continue per $SESSION_PROGRESS_PATH" >&2
exit 0
TEMPLATE_EOF
}

# Ask question with numbered options, returns the selected index (1-based)
ask() {
  local prompt="$1"
  shift
  local options=("$@")
  local default=1

  echo "" >&2
  echo -e "${BLUE}$prompt${NC}" >&2
  for i in "${!options[@]}"; do
    local label="${options[$i]}"
    if [[ "$label" == *"(Recommended)"* ]]; then
      default=$((i + 1))
    fi
    echo "  $((i+1))) $label" >&2
  done

  read -p "Choice [$default]: " choice < /dev/tty
  choice="${choice:-$default}"

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#options[@]} ]]; then
    echo "$default"
  else
    echo "$choice"
  fi
}

# Validate domain format: alphanumeric, hyphens, dots only. No wildcards.
validate_domain() {
  local domain="$1"
  if [[ "$domain" == *'*'* ]] || [[ "$domain" == *'?'* ]]; then
    warn "Wildcards not allowed in domains: '$domain' (skipped)"
    return 1
  fi
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    warn "Invalid domain format: '$domain' (skipped). Use format: example.com"
    return 1
  fi
  return 0
}

# ========================================
# Ecosystem detection
# ========================================
detect_ecosystems() {
  local dir="$1"
  DETECTED_ECOSYSTEMS=()
  DETECTED_DOMAINS=()

  # Always-included base domains
  DETECTED_DOMAINS+=("api.anthropic.com" "github.com" "api.github.com")

  # Node.js
  if [[ -f "$dir/package.json" ]] || [[ -f "$dir/yarn.lock" ]] || [[ -f "$dir/pnpm-lock.yaml" ]] || [[ -f "$dir/bun.lockb" ]]; then
    DETECTED_ECOSYSTEMS+=("Node.js")
    DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
  fi

  # TypeScript
  if [[ -f "$dir/tsconfig.json" ]]; then
    DETECTED_ECOSYSTEMS+=("TypeScript")
    # Same domains as Node.js, add if not already present
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " registry.npmjs.org " ]]; then
      DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
    fi
  fi

  # Deno
  if [[ -f "$dir/deno.json" ]] || [[ -f "$dir/deno.jsonc" ]]; then
    DETECTED_ECOSYSTEMS+=("Deno")
    DETECTED_DOMAINS+=("deno.land" "jsr.io")
  fi

  # Bun
  if [[ -f "$dir/bunfig.toml" ]]; then
    DETECTED_ECOSYSTEMS+=("Bun")
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " registry.npmjs.org " ]]; then
      DETECTED_DOMAINS+=("registry.npmjs.org" "registry.yarnpkg.com")
    fi
  fi

  # Python
  if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]] || [[ -f "$dir/Pipfile" ]] || [[ -f "$dir/poetry.lock" ]]; then
    DETECTED_ECOSYSTEMS+=("Python")
    DETECTED_DOMAINS+=("pypi.org" "files.pythonhosted.org")
  fi

  # Rust
  if [[ -f "$dir/Cargo.toml" ]]; then
    DETECTED_ECOSYSTEMS+=("Rust")
    DETECTED_DOMAINS+=("crates.io" "static.crates.io")
  fi

  # Go
  if [[ -f "$dir/go.mod" ]]; then
    DETECTED_ECOSYSTEMS+=("Go")
    DETECTED_DOMAINS+=("proxy.golang.org" "sum.golang.org")
  fi

  # Java/Kotlin
  if [[ -f "$dir/pom.xml" ]] || [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
    DETECTED_ECOSYSTEMS+=("Java/Kotlin")
    DETECTED_DOMAINS+=("repo.maven.apache.org" "plugins.gradle.org" "services.gradle.org")
  fi

  # Ruby
  if [[ -f "$dir/Gemfile" ]]; then
    DETECTED_ECOSYSTEMS+=("Ruby")
    DETECTED_DOMAINS+=("rubygems.org")
  fi

  # PHP
  if [[ -f "$dir/composer.json" ]]; then
    DETECTED_ECOSYSTEMS+=("PHP")
    DETECTED_DOMAINS+=("packagist.org" "repo.packagist.org")
  fi

  # Dart/Flutter
  if [[ -f "$dir/pubspec.yaml" ]]; then
    DETECTED_ECOSYSTEMS+=("Dart/Flutter")
    DETECTED_DOMAINS+=("pub.dev")
  fi

  # C#/.NET
  if compgen -G "$dir/*.csproj" > /dev/null 2>&1 || compgen -G "$dir/*.sln" > /dev/null 2>&1 || [[ -f "$dir/global.json" ]]; then
    DETECTED_ECOSYSTEMS+=("C#/.NET")
    DETECTED_DOMAINS+=("api.nuget.org")
  fi

  # C/C++
  if [[ -f "$dir/CMakeLists.txt" ]] || [[ -f "$dir/meson.build" ]] || [[ -f "$dir/conanfile.py" ]] || [[ -f "$dir/vcpkg.json" ]]; then
    DETECTED_ECOSYSTEMS+=("C/C++")
    DETECTED_DOMAINS+=("conan.io" "vcpkg.io")
  fi

  # Swift
  if [[ -f "$dir/Package.swift" ]] || compgen -G "$dir/*.xcodeproj" > /dev/null 2>&1; then
    DETECTED_ECOSYSTEMS+=("Swift")
  fi

  # R
  if [[ -f "$dir/DESCRIPTION" ]] || compgen -G "$dir/*.Rproj" > /dev/null 2>&1 || [[ -f "$dir/renv.lock" ]]; then
    DETECTED_ECOSYSTEMS+=("R")
    DETECTED_DOMAINS+=("cran.r-project.org" "cloud.r-project.org")
  fi

  # Scala
  if [[ -f "$dir/build.sbt" ]] || [[ -f "$dir/build.sc" ]]; then
    DETECTED_ECOSYSTEMS+=("Scala")
    if [[ ! " ${DETECTED_DOMAINS[*]} " =~ " repo.maven.apache.org " ]]; then
      DETECTED_DOMAINS+=("repo.maven.apache.org")
    fi
  fi

  # Lua
  if compgen -G "$dir/*.rockspec" > /dev/null 2>&1; then
    DETECTED_ECOSYSTEMS+=("Lua")
    DETECTED_DOMAINS+=("luarocks.org")
  fi
}

# ========================================
# Framework detection + quality gates
# ========================================
detect_frameworks() {
  local dir="$1"
  DETECTED_FRAMEWORKS=()
  QUALITY_GATES=()

  # Helper: check if a package.json dependency exists
  has_dep() {
    local pkg="$1"
    if [[ -f "$dir/package.json" ]]; then
      jq -e --arg p "$pkg" '(.dependencies[$p] // .devDependencies[$p] // .peerDependencies[$p]) != null' "$dir/package.json" > /dev/null 2>&1
    else
      return 1
    fi
  }

  has_dev_dep() {
    local pkg="$1"
    if [[ -f "$dir/package.json" ]]; then
      jq -e --arg p "$pkg" '.devDependencies[$p] != null' "$dir/package.json" > /dev/null 2>&1
    else
      return 1
    fi
  }

  # Helper: check if a string exists in a file
  file_contains() {
    local file="$1"
    local pattern="$2"
    [[ -f "$file" ]] && grep -q "$pattern" "$file" 2>/dev/null
  }

  # Helper: add quality gate if not already present
  add_gate() {
    local cmd="$1"
    if [[ ! " ${QUALITY_GATES[*]} " =~ " ${cmd} " ]]; then
      QUALITY_GATES+=("$cmd")
    fi
  }

  # --- Node.js / TypeScript frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Node.js " ]] || [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " TypeScript " ]] || [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Bun " ]]; then

    # Next.js
    if compgen -G "$dir/next.config."{js,mjs,ts} > /dev/null 2>&1 || has_dep "next"; then
      DETECTED_FRAMEWORKS+=("Next.js")
      add_gate "npx next build"
      add_gate "npx next lint"
    fi

    # Nuxt
    if compgen -G "$dir/nuxt.config."{js,ts} > /dev/null 2>&1 || has_dep "nuxt"; then
      DETECTED_FRAMEWORKS+=("Nuxt")
      add_gate "npx nuxi build"
    fi

    # SvelteKit
    if compgen -G "$dir/svelte.config."{js,ts} > /dev/null 2>&1 || has_dep "@sveltejs/kit"; then
      DETECTED_FRAMEWORKS+=("SvelteKit")
      add_gate "npm run build"
      add_gate "npm run check"
    fi

    # Angular
    if [[ -f "$dir/angular.json" ]] || has_dep "@angular/core"; then
      DETECTED_FRAMEWORKS+=("Angular")
      add_gate "npx ng build"
      add_gate "npx ng test"
    fi

    # Astro
    if compgen -G "$dir/astro.config."{mjs,js,ts} > /dev/null 2>&1 || has_dep "astro"; then
      DETECTED_FRAMEWORKS+=("Astro")
      add_gate "npx astro build"
    fi

    # Remix
    if compgen -G "$dir/remix.config."{js,ts} > /dev/null 2>&1 || has_dep "@remix-run/react"; then
      DETECTED_FRAMEWORKS+=("Remix")
      add_gate "npm run build"
    fi

    # Gatsby
    if compgen -G "$dir/gatsby-config."{js,ts} > /dev/null 2>&1 || has_dep "gatsby"; then
      DETECTED_FRAMEWORKS+=("Gatsby")
      add_gate "npx gatsby build"
    fi

    # SolidJS
    if has_dep "solid-js"; then
      DETECTED_FRAMEWORKS+=("SolidJS")
      add_gate "npm run build"
    fi

    # NestJS
    if [[ -f "$dir/nest-cli.json" ]] || has_dep "@nestjs/core"; then
      DETECTED_FRAMEWORKS+=("NestJS")
      add_gate "npm run build"
      add_gate "npm run test"
    fi

    # Express
    if has_dep "express"; then
      DETECTED_FRAMEWORKS+=("Express")
      add_gate "npm test"
    fi

    # Fastify
    if has_dep "fastify"; then
      DETECTED_FRAMEWORKS+=("Fastify")
      add_gate "npm test"
    fi

    # Hono
    if has_dep "hono"; then
      DETECTED_FRAMEWORKS+=("Hono")
      add_gate "npm test"
    fi

    # React Native
    if has_dep "react-native" && [[ -f "$dir/app.json" ]]; then
      DETECTED_FRAMEWORKS+=("React Native")
      add_gate "npx react-native doctor"
    fi

    # Expo
    if has_dep "expo" || [[ -f "$dir/eas.json" ]]; then
      DETECTED_FRAMEWORKS+=("Expo")
      add_gate "npx expo doctor"
    fi

    # Electron
    if has_dev_dep "electron"; then
      DETECTED_FRAMEWORKS+=("Electron")
      add_gate "npm run build"
    fi

    # Tauri
    if [[ -f "$dir/src-tauri/tauri.conf.json" ]]; then
      DETECTED_FRAMEWORKS+=("Tauri")
      add_gate "cargo test"
      add_gate "npm run build"
    fi

    # Build tools (only if no higher-level framework detected build gate)
    if compgen -G "$dir/vite.config."{js,ts,mjs} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Vite")
      add_gate "npx vite build"
    fi

    if compgen -G "$dir/webpack.config."{js,ts} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Webpack")
      add_gate "npx webpack build"
    fi

    # Test frameworks
    if compgen -G "$dir/vitest.config."{js,ts} > /dev/null 2>&1 || has_dev_dep "vitest"; then
      DETECTED_FRAMEWORKS+=("Vitest")
      add_gate "npx vitest run"
    fi

    if compgen -G "$dir/jest.config."{js,ts,cjs} > /dev/null 2>&1 || has_dev_dep "jest"; then
      DETECTED_FRAMEWORKS+=("Jest")
      add_gate "npx jest"
    fi

    if compgen -G "$dir/playwright.config."{js,ts} > /dev/null 2>&1; then
      DETECTED_FRAMEWORKS+=("Playwright")
      add_gate "npx playwright test"
    fi

    if compgen -G "$dir/.mocharc."{js,json,yaml} > /dev/null 2>&1 || has_dev_dep "mocha"; then
      DETECTED_FRAMEWORKS+=("Mocha")
      add_gate "npx mocha"
    fi

    if compgen -G "$dir/cypress.config."{js,ts} > /dev/null 2>&1 || has_dev_dep "cypress"; then
      DETECTED_FRAMEWORKS+=("Cypress")
      add_gate "npx cypress run"
    fi
  fi

  # --- Python frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Python " ]]; then
    local py_deps=""
    [[ -f "$dir/requirements.txt" ]] && py_deps+=$(cat "$dir/requirements.txt" 2>/dev/null)
    [[ -f "$dir/pyproject.toml" ]] && py_deps+=$(cat "$dir/pyproject.toml" 2>/dev/null)
    [[ -f "$dir/Pipfile" ]] && py_deps+=$(cat "$dir/Pipfile" 2>/dev/null)

    if [[ -f "$dir/manage.py" ]] || echo "$py_deps" | grep -qi "django"; then
      DETECTED_FRAMEWORKS+=("Django")
      add_gate "python manage.py test"
      add_gate "python manage.py check"
    fi

    if echo "$py_deps" | grep -qi "flask"; then
      DETECTED_FRAMEWORKS+=("Flask")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "fastapi"; then
      DETECTED_FRAMEWORKS+=("FastAPI")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "starlette"; then
      DETECTED_FRAMEWORKS+=("Starlette")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "torch"; then
      DETECTED_FRAMEWORKS+=("PyTorch")
      add_gate "python -m pytest"
    fi

    if echo "$py_deps" | grep -qi "tensorflow"; then
      DETECTED_FRAMEWORKS+=("TensorFlow")
      add_gate "python -m pytest"
    fi

    if [[ -f "$dir/pytest.ini" ]] || file_contains "$dir/pyproject.toml" "\[tool.pytest"; then
      DETECTED_FRAMEWORKS+=("pytest")
      add_gate "python -m pytest"
    fi

    if [[ -f "$dir/mypy.ini" ]] || file_contains "$dir/pyproject.toml" "\[tool.mypy"; then
      DETECTED_FRAMEWORKS+=("mypy")
      add_gate "mypy ."
    fi

    if file_contains "$dir/pyproject.toml" "\[tool.ruff"; then
      DETECTED_FRAMEWORKS+=("Ruff")
      add_gate "ruff check ."
    fi
  fi

  # --- Rust frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Rust " ]]; then
    if file_contains "$dir/Cargo.toml" "actix-web"; then
      DETECTED_FRAMEWORKS+=("Actix-web")
    fi
    if file_contains "$dir/Cargo.toml" "axum"; then
      DETECTED_FRAMEWORKS+=("Axum")
    fi
    if file_contains "$dir/Cargo.toml" "rocket"; then
      DETECTED_FRAMEWORKS+=("Rocket")
    fi
    if file_contains "$dir/Cargo.toml" "bevy"; then
      DETECTED_FRAMEWORKS+=("Bevy")
    fi
    if [[ -d "$dir/src-tauri" ]]; then
      DETECTED_FRAMEWORKS+=("Tauri")
    fi
    add_gate "cargo test"
    add_gate "cargo clippy"
  fi

  # --- Go frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Go " ]]; then
    if file_contains "$dir/go.mod" "github.com/gin-gonic/gin"; then
      DETECTED_FRAMEWORKS+=("Gin")
    fi
    if file_contains "$dir/go.mod" "github.com/labstack/echo"; then
      DETECTED_FRAMEWORKS+=("Echo")
    fi
    if file_contains "$dir/go.mod" "github.com/gofiber/fiber"; then
      DETECTED_FRAMEWORKS+=("Fiber")
    fi
    if file_contains "$dir/go.mod" "github.com/go-chi/chi"; then
      DETECTED_FRAMEWORKS+=("Chi")
    fi
    add_gate "go test ./..."
    add_gate "go vet ./..."
  fi

  # --- Java/Kotlin frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Java/Kotlin " ]]; then
    local jvm_deps=""
    [[ -f "$dir/pom.xml" ]] && jvm_deps+=$(cat "$dir/pom.xml" 2>/dev/null)
    [[ -f "$dir/build.gradle" ]] && jvm_deps+=$(cat "$dir/build.gradle" 2>/dev/null)
    [[ -f "$dir/build.gradle.kts" ]] && jvm_deps+=$(cat "$dir/build.gradle.kts" 2>/dev/null)

    local build_cmd="./gradlew test"
    [[ -f "$dir/pom.xml" ]] && [[ ! -f "$dir/build.gradle" ]] && [[ ! -f "$dir/build.gradle.kts" ]] && build_cmd="./mvnw test"

    if echo "$jvm_deps" | grep -q "spring-boot"; then
      DETECTED_FRAMEWORKS+=("Spring Boot")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "quarkus"; then
      DETECTED_FRAMEWORKS+=("Quarkus")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "micronaut"; then
      DETECTED_FRAMEWORKS+=("Micronaut")
      add_gate "$build_cmd"
    fi
    if echo "$jvm_deps" | grep -q "com.android.application"; then
      DETECTED_FRAMEWORKS+=("Android")
      add_gate "./gradlew build"
      add_gate "./gradlew lint"
    fi

    # Default JVM gate if no specific framework matched
    if [[ ${#DETECTED_FRAMEWORKS[@]} -eq 0 ]] || ! printf '%s\n' "${DETECTED_FRAMEWORKS[@]}" | grep -qE "Spring Boot|Quarkus|Micronaut|Android"; then
      add_gate "$build_cmd"
    fi
  fi

  # --- Ruby frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Ruby " ]]; then
    if file_contains "$dir/Gemfile" "rails" || [[ -f "$dir/bin/rails" ]]; then
      DETECTED_FRAMEWORKS+=("Rails")
      add_gate "bin/rails test"
      add_gate "bin/rails db:migrate:status"
    fi
    if file_contains "$dir/Gemfile" "sinatra"; then
      DETECTED_FRAMEWORKS+=("Sinatra")
      add_gate "bundle exec rspec"
    fi
    if file_contains "$dir/Gemfile" "hanami"; then
      DETECTED_FRAMEWORKS+=("Hanami")
      add_gate "bundle exec hanami server"
    fi
  fi

  # --- PHP frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " PHP " ]]; then
    if file_contains "$dir/composer.json" "laravel/framework"; then
      DETECTED_FRAMEWORKS+=("Laravel")
      add_gate "php artisan test"
    fi
    if file_contains "$dir/composer.json" '"symfony/'; then
      DETECTED_FRAMEWORKS+=("Symfony")
      add_gate "php bin/phpunit"
    fi
  fi

  # --- C#/.NET frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " C#/.NET " ]]; then
    local csproj_content=""
    for f in "$dir"/*.csproj; do
      [[ -f "$f" ]] && csproj_content+=$(cat "$f" 2>/dev/null)
    done

    if echo "$csproj_content" | grep -q "Microsoft.AspNetCore"; then
      DETECTED_FRAMEWORKS+=("ASP.NET")
    fi
    if echo "$csproj_content" | grep -q "<UseMaui>true</UseMaui>"; then
      DETECTED_FRAMEWORKS+=("MAUI")
    fi
    add_gate "dotnet build"
    add_gate "dotnet test"
  fi

  # --- C/C++ build systems ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " C/C++ " ]]; then
    if [[ -f "$dir/CMakeLists.txt" ]]; then
      DETECTED_FRAMEWORKS+=("CMake")
      add_gate "cmake -B build && cmake --build build && ctest --test-dir build"
    fi
    if [[ -f "$dir/meson.build" ]]; then
      DETECTED_FRAMEWORKS+=("Meson")
      add_gate "meson setup build && meson compile -C build && meson test -C build"
    fi
    if [[ -f "$dir/WORKSPACE" ]] || [[ -f "$dir/BUILD.bazel" ]]; then
      DETECTED_FRAMEWORKS+=("Bazel")
      add_gate "bazel build //..."
      add_gate "bazel test //..."
    fi
    if [[ -f "$dir/Makefile" ]]; then
      DETECTED_FRAMEWORKS+=("Make")
      add_gate "make"
      add_gate "make test"
    fi
  fi

  # --- Swift frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Swift " ]]; then
    if [[ -f "$dir/Package.swift" ]]; then
      DETECTED_FRAMEWORKS+=("SPM")
      add_gate "swift build"
      add_gate "swift test"
      if file_contains "$dir/Package.swift" "vapor"; then
        DETECTED_FRAMEWORKS+=("Vapor")
      fi
    fi
  fi

  # --- Scala frameworks ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Scala " ]]; then
    if [[ -f "$dir/build.sbt" ]]; then
      DETECTED_FRAMEWORKS+=("sbt")
      add_gate "sbt compile"
      add_gate "sbt test"
      if file_contains "$dir/build.sbt" "com.typesafe.play"; then
        DETECTED_FRAMEWORKS+=("Play")
      fi
    fi
    if [[ -f "$dir/build.sc" ]]; then
      DETECTED_FRAMEWORKS+=("Mill")
      add_gate "mill compile"
      add_gate "mill test"
    fi
  fi

  # --- R ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " R " ]]; then
    add_gate "R CMD check ."
  fi

  # --- Lua ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Lua " ]]; then
    add_gate "luacheck ."
  fi

  # --- Dart/Flutter ---
  if [[ " ${DETECTED_ECOSYSTEMS[*]} " =~ " Dart/Flutter " ]]; then
    if file_contains "$dir/pubspec.yaml" "flutter"; then
      DETECTED_FRAMEWORKS+=("Flutter")
      add_gate "flutter analyze"
      add_gate "flutter test"
    else
      add_gate "dart analyze"
      add_gate "dart test"
    fi
  fi
}

emit_start_script() {
  cat <<'TEMPLATE_EOF'
#!/bin/bash
# Start a Bovine University ralph-loop session.
# Generated by ralph-setup.sh — feel free to customise.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

PROGRESS=".claude/ralph/progress.md"

# Validate progress.md exists
if [[ ! -f "$PROGRESS" ]]; then
  echo -e "${RED}Error:${NC} $PROGRESS not found. Run ralph-setup.sh first."
  exit 1
fi

# Warn if ralph-wiggum plugin is missing
if command -v claude >/dev/null 2>&1; then
  if ! claude plugins list 2>/dev/null | grep -q 'ralph-wiggum'; then
    echo -e "${RED}Warning:${NC} ralph-wiggum plugin not found. Install: claude plugins add ralph-wiggum"
  fi
fi

echo ""

# If progress.md has a task, show legacy-mode command; otherwise show inline instructions
TASK_CONTENT=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;p;}' "$PROGRESS" | sed '/^$/d')
if [[ -n "$TASK_CONTENT" ]] && ! echo "$TASK_CONTENT" | grep -q '\[Describe your task here'; then
  echo -e "${GREEN}Task found in progress.md (legacy mode):${NC}"
  echo "$TASK_CONTENT" | head -3
  echo ""
  echo -e "Paste this command once Claude starts:"
  echo -e "  ${BOLD}/ralph-loop \"Continue per .claude/ralph/progress.md\" --max-iterations %%MAX_ITERATIONS%% --completion-promise \"%%COMPLETION_PHRASE%%\"${NC}"
else
  echo -e "Paste a command like this once Claude starts:"
  echo -e "  ${BOLD}/ralph-loop \"Your task description here\" --max-iterations %%MAX_ITERATIONS%% --completion-promise \"%%COMPLETION_PHRASE%%\"${NC}"
fi
echo ""

claude --dangerously-skip-permissions
TEMPLATE_EOF
}

# Process RALPH.md template to include only selected options
process_ralph_template() {
  local template="$1"
  local git_strategy="$2"
  local pr_strategy="$3"
  local pr_review="$4"

  local output="$template"

  # Remove all option definition blocks (JSON metadata)
  output=$(echo "$output" | sed '/<!--ralph-option:[a-z_]*$/,/^-->$/d')

  # Process git strategy
  case "$git_strategy" in
    never)
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_push-->/,/<!--\/ralph-option:pr_push-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
    once)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      ;;
    each)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_squash-->/,/<!--\/ralph-option:git_squash-->/d')
      ;;
    squash)
      output=$(echo "$output" | sed '/<!--ralph-option:git_never-->/,/<!--\/ralph-option:git_never-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_once-->/,/<!--\/ralph-option:git_once-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:git_each-->/,/<!--\/ralph-option:git_each-->/d')
      ;;
  esac

  # Process PR strategy
  case "$pr_strategy" in
    open)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
    merge)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_no-->/,/<!--\/ralph-option:pr_no-->/d')
      ;;
    no)
      output=$(echo "$output" | sed '/<!--ralph-option:pr_open-->/,/<!--\/ralph-option:pr_open-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_merge-->/,/<!--\/ralph-option:pr_merge-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_push-->/,/<!--\/ralph-option:pr_push-->/d')
      output=$(echo "$output" | sed '/<!--ralph-option:pr_automerge-->/,/<!--\/ralph-option:pr_automerge-->/d')
      ;;
  esac

  # Process PR review toolkit
  if [[ "$pr_review" == "yes" ]]; then
    output=$(echo "$output" | sed '/<!--ralph-option:pr_review_no-->/,/<!--\/ralph-option:pr_review_no-->/d')
  else
    output=$(echo "$output" | sed '/<!--ralph-option:pr_review_yes-->/,/<!--\/ralph-option:pr_review_yes-->/d')
  fi

  # Process quality gates
  if [[ ${#QUALITY_GATES[@]} -gt 0 ]]; then
    local gates_md=""
    for gate in "${QUALITY_GATES[@]}"; do
      gates_md+="- \`$gate\`\n"
    done
    output=$(echo "$output" | sed "s|<!--ralph-quality-gate-commands-->|$(echo -e "$gates_md")|")
  else
    # Replace quality gates content with guidance text when none detected
    output=$(echo "$output" | sed 's|<!--ralph-quality-gate-commands-->|No quality gates were auto-detected. Before committing, run the appropriate test, lint, and build commands for your project.|')
  fi

  # Substitute configurable placeholders
  output=$(echo "$output" | sed "s/%%MAX_ITERATIONS%%/$MAX_ITERATIONS/g")
  output=$(echo "$output" | sed "s/%%COMPLETION_PHRASE%%/$COMPLETION_PHRASE/g")

  # Remove remaining option markers
  output=$(echo "$output" | sed 's/<!--ralph-option:[^>]*-->//g')
  output=$(echo "$output" | sed 's/<!--\/ralph-option:[^>]*-->//g')

  # Clean up extra blank lines
  output=$(echo "$output" | cat -s)

  echo "$output"
}

# Update CLAUDE.md to reference RALPH.md
update_claude_md() {
  local project_dir="$1"
  local marker="<!-- Ralph Loop Detection -->"
  local rule='If `.claude/RALPH.md` exists, follow rules in `.claude/RALPH.md`.'

  if [[ -f "$project_dir/CLAUDE.md" ]]; then
    if ! grep -q "$marker" "$project_dir/CLAUDE.md"; then
      # Prepend so the rule doesn't sink below the fold
      local tmpfile
      tmpfile=$(mktemp)
      printf '%s\n%s\n\n' "$marker" "$rule" > "$tmpfile"
      cat "$project_dir/CLAUDE.md" >> "$tmpfile"
      mv "$tmpfile" "$project_dir/CLAUDE.md"
      info "Updated existing CLAUDE.md"
    else
      info "CLAUDE.md already configured (RALPH.md regenerated with current settings)"
    fi
  else
    echo -e "$marker\n$rule" > "$project_dir/CLAUDE.md"
    info "Created new CLAUDE.md"
  fi
}

# ========================================
# Uninstall
# ========================================
uninstall() {
  local project_dir
  project_dir=$(find_project_root)
  echo ""
  echo "Uninstalling Bovine University from: $project_dir"
  echo ""

  local removed=0

  # Remove Ralph files
  for f in ".claude/RALPH.md" ".claude/ralph" ".claude/hooks/ralph-preflight.sh" ".claude/hooks/ralph-postsetup.sh"; do
    local target="$project_dir/$f"
    if [[ -e "$target" ]]; then
      rm -rf "$target"
      success "Removed $f"
      removed=$((removed + 1))
    fi
  done

  # Remove empty hooks dir
  if [[ -d "$project_dir/.claude/hooks" ]] && [[ -z "$(ls -A "$project_dir/.claude/hooks")" ]]; then
    rmdir "$project_dir/.claude/hooks"
    success "Removed empty .claude/hooks/"
  fi

  # Settings — confirm before removing since user may have custom rules
  if [[ -f "$project_dir/.claude/settings.local.json" ]]; then
    read -p "  Remove .claude/settings.local.json? (may contain custom rules) [y/N]: " CONFIRM < /dev/tty
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
      rm -f "$project_dir/.claude/settings.local.json"
      success "Removed .claude/settings.local.json"
      removed=$((removed + 1))
    else
      # Remove hook registration that references the now-deleted preflight hook
      if jq -e '.hooks' "$project_dir/.claude/settings.local.json" >/dev/null 2>&1; then
        local CLEANED
        CLEANED=$(jq 'del(.hooks)' "$project_dir/.claude/settings.local.json")
        echo "$CLEANED" > "$project_dir/.claude/settings.local.json"
        success "Removed hook registration from settings.local.json"
      fi
      info "Kept .claude/settings.local.json (hooks removed)"
    fi
  fi

  # Clean CLAUDE.md — remove Ralph marker and rule
  if [[ -f "$project_dir/CLAUDE.md" ]]; then
    local marker="<!-- Ralph Loop Detection -->"
    if grep -q "$marker" "$project_dir/CLAUDE.md"; then
      # Use portable sed: try GNU sed first, fall back to BSD sed
      if sed --version >/dev/null 2>&1; then
        sed -i "/$marker/,+1d" "$project_dir/CLAUDE.md"
      else
        sed -i '' "/$marker/,+1d" "$project_dir/CLAUDE.md"
      fi
      # Remove trailing blank lines
      if sed --version >/dev/null 2>&1; then
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$project_dir/CLAUDE.md"
      else
        sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$project_dir/CLAUDE.md"
      fi
      success "Cleaned Ralph references from CLAUDE.md"
      removed=$((removed + 1))
    fi
  fi

  echo ""
  if [[ $removed -gt 0 ]]; then
    success "Uninstall complete."
  else
    info "Nothing to remove — Bovine University not installed in this project."
  fi
}

# ========================================
# Main setup flow
# ========================================
main() {
  case "${1:-}" in
    --uninstall)
      uninstall
      exit 0
      ;;
    --help|-h)
      echo "Usage: ralph-setup.sh [--uninstall | --help]"
      echo ""
      echo "  (no args)    Install Bovine University in the current project"
      echo "  --uninstall  Remove Bovine University files from the current project"
      echo "  --help       Show this help"
      exit 0
      ;;
  esac

  echo ""
  echo "========================================"
  echo "  Bovine University - Ralph Setup"
  echo "========================================"
  echo ""

  check_deps

  PROJECT_ROOT=$(find_project_root)
  info "Project root: $PROJECT_ROOT"

  # ========================================
  # Git repo check
  # ========================================
  if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
    echo ""
    warn "No .git directory found in $PROJECT_ROOT"
    echo "  Without a git repository, the following features will not work:"
    echo "    - Auto-branching from main/master"
    echo "    - Dirty working directory checks"
    echo "    - Git commit strategies (never/once/each/squash)"
    echo "    - PR creation"
    echo ""
    read -p "  Continue without git? [y/N]: " GIT_CONFIRM < /dev/tty
    [[ "$GIT_CONFIRM" != "y" && "$GIT_CONFIRM" != "Y" ]] && echo "Aborted." && exit 0
  fi

  # ========================================
  # Caveat emptor
  # ========================================
  echo ""
  echo -e "${YELLOW}${BOLD}  WARNING${NC}"
  echo ""
  echo "  Bovine University runs Claude Code with --dangerously-skip-permissions."
  echo "  This means Claude can execute ANY command that isn't explicitly denied."
  echo "  OS-level sandboxing restricts network and filesystem access, but Claude"
  echo "  has full control within your project directory."
  echo ""
  echo "  Recommendations:"
  echo "    - Use feature branches (the preflight hook creates them automatically)"
  echo "    - Enable GitHub branch protection on main"
  echo "    - For maximum safety, run in ephemeral/disposable environments"
  echo ""
  read -p "  Continue? [y/N]: " CONFIRM < /dev/tty
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted." && exit 0

  # ========================================
  # Ecosystem & framework detection
  # ========================================
  echo ""
  info "Detecting project ecosystem..."
  detect_ecosystems "$PROJECT_ROOT"
  detect_frameworks "$PROJECT_ROOT"

  if [[ ${#DETECTED_ECOSYSTEMS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  Detected ecosystem: ${GREEN}$(IFS=', '; echo "${DETECTED_ECOSYSTEMS[*]}")${NC}"

    if [[ ${#DETECTED_FRAMEWORKS[@]} -gt 0 ]]; then
      echo -e "  Detected frameworks: ${GREEN}$(IFS=', '; echo "${DETECTED_FRAMEWORKS[*]}")${NC}"
    fi

    echo ""
    echo "  Allowed network domains:"
    # Deduplicate domains
    local unique_domains=($(printf '%s\n' "${DETECTED_DOMAINS[@]}" | sort -u))
    DETECTED_DOMAINS=("${unique_domains[@]}")
    for domain in "${DETECTED_DOMAINS[@]}"; do
      echo "    - $domain"
    done

    if [[ ${#QUALITY_GATES[@]} -gt 0 ]]; then
      echo ""
      echo "  Quality gate commands:"
      for gate in "${QUALITY_GATES[@]}"; do
        echo "    - $gate"
      done
    fi

    echo ""
    read -p "  Is this correct? [Y/n]: " ECO_CONFIRM < /dev/tty
    if [[ "$ECO_CONFIRM" == "n" || "$ECO_CONFIRM" == "N" ]]; then
      # Offer domain removal
      echo ""
      echo "  Current domains:"
      for i in "${!DETECTED_DOMAINS[@]}"; do
        echo "    $((i+1))) ${DETECTED_DOMAINS[$i]}"
      done
      echo ""
      echo "  Enter numbers to remove (comma-separated, or press Enter to skip):"
      read -p "  Remove: " REMOVE_NUMS < /dev/tty
      if [[ -n "$REMOVE_NUMS" ]]; then
        IFS=',' read -ra NUMS <<< "$REMOVE_NUMS"
        # Collect indices to remove (convert to 0-based, sort descending to avoid shift issues)
        local to_remove=()
        for n in "${NUMS[@]}"; do
          n=$(echo "$n" | xargs)
          if [[ "$n" =~ ^[0-9]+$ ]] && [[ "$n" -ge 1 ]] && [[ "$n" -le ${#DETECTED_DOMAINS[@]} ]]; then
            to_remove+=($((n-1)))
          fi
        done
        # Sort descending and remove
        IFS=$'\n' to_remove=($(sort -rn <<< "${to_remove[*]}")); unset IFS
        for idx in "${to_remove[@]}"; do
          unset 'DETECTED_DOMAINS[$idx]'
        done
        # Re-index array
        DETECTED_DOMAINS=("${DETECTED_DOMAINS[@]}")
      fi

      # Offer additions (existing flow)
      echo ""
      echo "  Enter additional allowed domains (comma-separated, or press Enter to skip):"
      read -p "  Domains: " CUSTOM_DOMAINS < /dev/tty
      if [[ -n "$CUSTOM_DOMAINS" ]]; then
        IFS=',' read -ra EXTRA_DOMAINS <<< "$CUSTOM_DOMAINS"
        for d in "${EXTRA_DOMAINS[@]}"; do
          d=$(echo "$d" | xargs) # trim whitespace
          [[ -n "$d" ]] && validate_domain "$d" && DETECTED_DOMAINS+=("$d")
        done
      fi

      # Show final list for confirmation
      echo ""
      echo "  Final domain list:"
      for domain in "${DETECTED_DOMAINS[@]}"; do
        echo "    - $domain"
      done
    fi
  else
    echo ""
    warn "No ecosystem detected."
    echo "  Enter allowed network domains (comma-separated, or press Enter for base only):"
    read -p "  Domains: " CUSTOM_DOMAINS < /dev/tty
    if [[ -n "$CUSTOM_DOMAINS" ]]; then
      IFS=',' read -ra EXTRA_DOMAINS <<< "$CUSTOM_DOMAINS"
      for d in "${EXTRA_DOMAINS[@]}"; do
        d=$(echo "$d" | xargs)
        [[ -n "$d" ]] && validate_domain "$d" && DETECTED_DOMAINS+=("$d")
      done
    fi
  fi

  # ========================================
  # Question 1: Git Strategy
  # ========================================
  GIT=$(ask "How often should Ralph commit?" \
    "Never - I'll handle git myself" \
    "Once - Commit when task is complete" \
    "Each loop - Commit after every iteration" \
    "Squash - Commit each loop, squash when done (Recommended)")

  case "$GIT" in
    1) GIT_STRATEGY="never" ;;
    2) GIT_STRATEGY="once" ;;
    3) GIT_STRATEGY="each" ;;
    4) GIT_STRATEGY="squash" ;;
  esac

  # ========================================
  # Question 2: PR Strategy (if committing)
  # ========================================
  PR_STRATEGY="no"
  if [[ "$GIT_STRATEGY" != "never" ]]; then
    PR=$(ask "Auto-open a PR when task is complete?" \
      "Yes, open PR but don't merge (Recommended)" \
      "Yes, open PR and auto-merge if clean" \
      "No — keep the branch local")

    case "$PR" in
      1) PR_STRATEGY="open" ;;
      2) PR_STRATEGY="merge" ;;
      3) PR_STRATEGY="no" ;;
    esac
  fi

  # ========================================
  # Question 3: PR Review Toolkit
  # ========================================
  info "pr-review-toolkit is a separate plugin. Install with: claude plugins add pr-review-toolkit"
  REVIEW=$(ask "Use pr-review-toolkit for code review?" \
    "Yes - Run code review agents during review phase (Recommended)" \
    "No - Skip automated review")

  case "$REVIEW" in
    1) PR_REVIEW="yes" ;;
    2) PR_REVIEW="no" ;;
  esac

  # ========================================
  # Question 4: Max Iterations
  # ========================================
  echo ""
  read -p "  Max iterations per loop [50]: " MAX_ITERATIONS_INPUT < /dev/tty
  MAX_ITERATIONS="${MAX_ITERATIONS_INPUT:-50}"
  # Validate: must be a positive integer
  if ! [[ "$MAX_ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
    warn "Invalid iteration count '$MAX_ITERATIONS', using default: 50"
    MAX_ITERATIONS="50"
  fi

  # ========================================
  # Question 5: Completion Phrase
  # ========================================
  read -p "  Completion phrase [TASK COMPLETE]: " COMPLETION_PHRASE_INPUT < /dev/tty
  COMPLETION_PHRASE="${COMPLETION_PHRASE_INPUT:-TASK COMPLETE}"
  # Validate: non-empty, no double quotes (would break CLI argument)
  if [[ "$COMPLETION_PHRASE" == *'"'* ]]; then
    warn "Completion phrase cannot contain double quotes, using default: TASK COMPLETE"
    COMPLETION_PHRASE="TASK COMPLETE"
  fi

  echo ""
  info "Setting up Ralph with:"
  info "  Git: $GIT_STRATEGY"
  info "  PR: $PR_STRATEGY"
  info "  Review: $PR_REVIEW"
  info "  Max iterations: $MAX_ITERATIONS"
  info "  Completion phrase: $COMPLETION_PHRASE"
  info "  Ecosystems: $(IFS=', '; echo "${DETECTED_ECOSYSTEMS[*]:-none}")"
  echo ""

  # ========================================
  # Interrupt cleanup
  # ========================================
  WRITTEN_FILES=()
  CREATED_DIRS=()
  ORIGINAL_CLAUDE_MD=""
  if [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
    ORIGINAL_CLAUDE_MD=$(cat "$PROJECT_ROOT/CLAUDE.md")
  fi

  cleanup_on_interrupt() {
    echo "" >&2
    warn "Interrupted — cleaning up partial installation..."
    # Remove written files in reverse order
    for (( i=${#WRITTEN_FILES[@]}-1; i>=0; i-- )); do
      [[ -f "${WRITTEN_FILES[$i]}" ]] && rm -f "${WRITTEN_FILES[$i]}"
    done
    # Remove created directories if empty (reverse order)
    for (( i=${#CREATED_DIRS[@]}-1; i>=0; i-- )); do
      rmdir "${CREATED_DIRS[$i]}" 2>/dev/null || true
    done
    # Restore CLAUDE.md
    if [[ -n "$ORIGINAL_CLAUDE_MD" ]]; then
      echo "$ORIGINAL_CLAUDE_MD" > "$PROJECT_ROOT/CLAUDE.md"
    elif [[ -f "$PROJECT_ROOT/CLAUDE.md" ]]; then
      # CLAUDE.md was created by us (didn't exist before), remove it
      rm -f "$PROJECT_ROOT/CLAUDE.md"
    fi
    echo "Cleanup complete. No files were installed." >&2
    exit 1
  }
  trap cleanup_on_interrupt INT TERM

  # ========================================
  # Create directories
  # ========================================
  [[ ! -d "$PROJECT_ROOT/.claude/hooks" ]] && CREATED_DIRS+=("$PROJECT_ROOT/.claude/hooks")
  [[ ! -d "$PROJECT_ROOT/.claude/ralph" ]] && CREATED_DIRS+=("$PROJECT_ROOT/.claude/ralph")
  [[ ! -d "$PROJECT_ROOT/.claude" ]] && CREATED_DIRS+=("$PROJECT_ROOT/.claude")
  mkdir -p "$PROJECT_ROOT/.claude/ralph"
  mkdir -p "$PROJECT_ROOT/.claude/hooks"

  # ========================================
  # Generate and process templates
  # ========================================

  # Generate RALPH.md from inline template
  info "Generating RALPH.md..."
  RALPH_TEMPLATE=$(emit_ralph_md)

  # Process template with selected options
  RALPH_MD=$(process_ralph_template "$RALPH_TEMPLATE" "$GIT_STRATEGY" "$PR_STRATEGY" "$PR_REVIEW")
  echo "$RALPH_MD" > "$PROJECT_ROOT/.claude/RALPH.md"
  WRITTEN_FILES+=("$PROJECT_ROOT/.claude/RALPH.md")
  success "Created .claude/RALPH.md"

  # Generate progress.md from inline template (guard against overwriting real tasks)
  info "Generating progress.md..."
  local PROGRESS_FILE="$PROJECT_ROOT/.claude/ralph/progress.md"
  if [[ -f "$PROGRESS_FILE" ]]; then
    local EXISTING_TASK
    EXISTING_TASK=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;p;}' "$PROGRESS_FILE" | sed '/^$/d')
    if [[ -n "$EXISTING_TASK" ]] && ! echo "$EXISTING_TASK" | grep -q '\[Describe your task here'; then
      warn "progress.md already has a task defined:"
      echo "$EXISTING_TASK" | head -3
      echo ""
      read -p "  Overwrite progress.md? [y/N]: " OVERWRITE_PROGRESS < /dev/tty
      if [[ "$OVERWRITE_PROGRESS" != "y" && "$OVERWRITE_PROGRESS" != "Y" ]]; then
        info "Kept existing progress.md"
      else
        emit_progress_template > "$PROGRESS_FILE"
        WRITTEN_FILES+=("$PROGRESS_FILE")
        success "Overwrote .claude/ralph/progress.md"
      fi
    else
      emit_progress_template > "$PROGRESS_FILE"
      WRITTEN_FILES+=("$PROGRESS_FILE")
      success "Created .claude/ralph/progress.md"
    fi
  else
    emit_progress_template > "$PROGRESS_FILE"
    WRITTEN_FILES+=("$PROGRESS_FILE")
    success "Created .claude/ralph/progress.md"
  fi

  # Install progress template as reset source for session management
  emit_progress_template > "$PROJECT_ROOT/.claude/ralph/.progress-template"
  WRITTEN_FILES+=("$PROJECT_ROOT/.claude/ralph/.progress-template")
  success "Created .claude/ralph/.progress-template"

  # Fetch settings.local.json and inject domains
  local EXISTING_SETTINGS="$PROJECT_ROOT/.claude/settings.local.json"
  local SKIP_SETTINGS=""

  if [[ -f "$EXISTING_SETTINGS" ]]; then
    echo ""
    warn "Existing .claude/settings.local.json detected."
    echo "  Re-running setup will overwrite custom deny rules and domain configurations."
    echo ""
    read -p "  Overwrite? [y/N]: " OVERWRITE_CONFIRM < /dev/tty
    if [[ "$OVERWRITE_CONFIRM" != "y" && "$OVERWRITE_CONFIRM" != "Y" ]]; then
      read -p "  Update allowed network domains only? [y/N]: " DOMAIN_ONLY < /dev/tty
      if [[ "$DOMAIN_ONLY" == "y" || "$DOMAIN_ONLY" == "Y" ]]; then
        local unique_domains=($(printf '%s\n' "${DETECTED_DOMAINS[@]}" | sort -u))
        SETTINGS_JSON=$(jq --argjson domains "$(printf '%s\n' "${unique_domains[@]}" | jq -R . | jq -s .)" \
          '.sandbox.network.allowedDomains = $domains' "$EXISTING_SETTINGS")
        echo "$SETTINGS_JSON" > "$EXISTING_SETTINGS"
        WRITTEN_FILES+=("$EXISTING_SETTINGS")
        success "Updated network domains in existing settings.local.json"
      else
        info "Keeping existing settings.local.json unchanged."
      fi
      SKIP_SETTINGS=true
    fi
  fi

  if [[ "$SKIP_SETTINGS" != "true" ]]; then
    info "Generating settings.local.json..."
    SETTINGS_TEMPLATE=$(emit_settings_template)

    # Deduplicate domains
    local unique_domains=($(printf '%s\n' "${DETECTED_DOMAINS[@]}" | sort -u))

    # Inject domains and expand ~ to $HOME in denyRead paths
    SETTINGS_JSON=$(echo "$SETTINGS_TEMPLATE" | jq --argjson domains "$(printf '%s\n' "${unique_domains[@]}" | jq -R . | jq -s .)" \
      --arg home "$HOME" \
      '.sandbox.network.allowedDomains = $domains |
       .sandbox.filesystem.denyRead = [.sandbox.filesystem.denyRead[] | sub("^~"; $home)]')
    echo "$SETTINGS_JSON" > "$PROJECT_ROOT/.claude/settings.local.json"
    WRITTEN_FILES+=("$PROJECT_ROOT/.claude/settings.local.json")
    success "Created .claude/settings.local.json"
  fi

  # Generate preflight hook from inline template
  info "Generating preflight hook..."
  emit_preflight_hook > "$PROJECT_ROOT/.claude/hooks/ralph-preflight.sh"
  WRITTEN_FILES+=("$PROJECT_ROOT/.claude/hooks/ralph-preflight.sh")
  chmod +x "$PROJECT_ROOT/.claude/hooks/ralph-preflight.sh"
  success "Created .claude/hooks/ralph-preflight.sh"

  # Generate postsetup hook from inline template
  info "Generating postsetup hook..."
  emit_postsetup_hook > "$PROJECT_ROOT/.claude/hooks/ralph-postsetup.sh"
  WRITTEN_FILES+=("$PROJECT_ROOT/.claude/hooks/ralph-postsetup.sh")
  chmod +x "$PROJECT_ROOT/.claude/hooks/ralph-postsetup.sh"
  success "Created .claude/hooks/ralph-postsetup.sh"

  # Generate start helper script (substitute placeholders)
  emit_start_script | sed "s/%%MAX_ITERATIONS%%/$MAX_ITERATIONS/g; s/%%COMPLETION_PHRASE%%/$COMPLETION_PHRASE/g" \
    > "$PROJECT_ROOT/.claude/ralph/start-ralph.sh"
  WRITTEN_FILES+=("$PROJECT_ROOT/.claude/ralph/start-ralph.sh")
  chmod +x "$PROJECT_ROOT/.claude/ralph/start-ralph.sh"
  success "Created .claude/ralph/start-ralph.sh"

  # ========================================
  # Update CLAUDE.md
  # ========================================
  update_claude_md "$PROJECT_ROOT"

  # All files written successfully — disarm cleanup trap
  trap - INT TERM

  # ========================================
  # Done!
  # ========================================
  echo ""
  echo "========================================"
  success "Setup complete!"
  echo "========================================"
  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo ""
  echo "  1. Write your task:"
  echo ""
  echo -e "     ${BOLD}vim .claude/ralph/progress.md${NC}"
  echo ""
  echo "  2. Start the loop (using the helper script):"
  echo ""
  echo -e "     ${BOLD}.claude/ralph/start-ralph.sh${NC}"
  echo ""
  echo "     Or manually:"
  echo ""
  echo -e "     ${BOLD}claude --dangerously-skip-permissions${NC}"
  echo -e "     ${BOLD}/ralph-loop \"Continue per .claude/ralph/progress.md\" --max-iterations $MAX_ITERATIONS --completion-promise \"$COMPLETION_PHRASE\"${NC}"
  echo ""
  if [[ "$PR_REVIEW" == "yes" ]]; then
    echo -e "  ${YELLOW}Reminder:${NC} Install pr-review-toolkit if not already present:"
    echo -e "     ${BOLD}claude plugins add pr-review-toolkit${NC}"
    echo ""
  fi
  echo "  To uninstall:"
  echo -e "     ${BOLD}bash ralph-setup.sh --uninstall${NC}"
  echo ""
}

main "$@"
