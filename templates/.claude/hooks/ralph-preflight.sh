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

# --- Auto-create feature branch if on main/master ---
CURRENT_BRANCH=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null)

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  PROGRESS="$CLAUDE_PROJECT_DIR/.claude/ralph/progress.md"
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
  git -C "$CLAUDE_PROJECT_DIR" checkout -b "$BRANCH" 2>&1 >&2
  echo "Created branch: $BRANCH" >&2
fi

exit 0
