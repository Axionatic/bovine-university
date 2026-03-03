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
