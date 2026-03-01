#!/bin/bash
# Ralph preflight hook — validates environment and auto-creates feature branch.
# Fires on PreToolUse for the Skill tool; ignores everything except ralph-loop.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')

# Only care about ralph-loop invocations
[[ "$TOOL" != "Skill" || "$SKILL" != *"ralph-loop"* ]] && exit 0

# --- Validate environment ---
MODE=$(echo "$INPUT" | jq -r '.permission_mode')
SETTINGS="$CLAUDE_PROJECT_DIR/.claude/settings.local.json"
SANDBOX=$(jq -r '.sandbox.enabled // false' "$SETTINGS" 2>/dev/null)

ERRORS=""
[[ "$MODE" != "bypassPermissions" ]] && ERRORS+="• --dangerously-skip-permissions is not active\n"
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

# --- Session management ---
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
fi

# Start new session
SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"
cp "$RALPH_DIR/progress.md" "$RALPH_DIR/progress-${SESSION_ID}.md"

# Validate progress.md has real task content
TASK_CONTENT=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;p;}' "$RALPH_DIR/progress-${SESSION_ID}.md" | sed '/^$/d')
if [[ -z "$TASK_CONTENT" ]] || echo "$TASK_CONTENT" | grep -q '\[Describe your task here'; then
  rm -f "$RALPH_DIR/progress-${SESSION_ID}.md"
  jq -n --arg msg "$(printf "progress.md has no task defined.\n\nEdit .claude/ralph/progress.md and fill in the Task section before starting the loop.\nExample:\n\n## Task\nBuild a REST API with CRUD operations for a todo app.")" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $msg
      }
    }'
  exit 0
fi

echo "$SESSION_ID" > "$ACTIVE_FILE"

# Reset progress.md for next task
if [[ -f "$TEMPLATE_FILE" ]]; then
  cp "$TEMPLATE_FILE" "$RALPH_DIR/progress.md"
else
  echo "Warning: .progress-template not found, progress.md not reset" >&2
fi

echo "Session started: $SESSION_ID" >&2

# --- Auto-create feature branch if on main/master ---
CURRENT_BRANCH=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null)

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  PROGRESS="$RALPH_DIR/progress-${SESSION_ID}.md"
  TASK_LINE=""
  if [[ -f "$PROGRESS" ]]; then
    TASK_LINE=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;/^$/d;p;}' "$PROGRESS" | head -1)
  fi

  SLUG=$(echo "${TASK_LINE:-unnamed-task}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//' \
    | sed 's/-$//' \
    | cut -c1-50)

  BRANCH="ralph/$SLUG"

  # Check for dirty working directory
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
