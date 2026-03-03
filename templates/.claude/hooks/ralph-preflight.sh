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
