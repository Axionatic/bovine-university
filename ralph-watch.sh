#!/bin/bash
# ralph-watch.sh — Real-time loop observer for Bovine University / ralph-wiggum
# Run in a second terminal while claude --dangerously-skip-permissions runs in another.
#
# Usage:
#   bash ralph-watch.sh                        # watch $PWD
#   bash ralph-watch.sh /path/to/your-project  # watch a specific project

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_GREEN_BOLD='\033[1;32m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_DIM='\033[2m'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"  # canonicalize

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not found in PATH." >&2
  exit 1
fi

# Derive JSONL dir: replace leading / then all remaining / with -
JSONL_HASH=$(echo "$PROJECT_DIR" | sed 's|/|-|g')
JSONL_DIR="$HOME/.claude/projects/$JSONL_HASH"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
PREV_SESSION=""
PREV_PROGRESS=""
PREV_STEP=""
PREV_LOOP_EXISTS=""
PREV_LOOP_PROMPT=""
JSONL_FILE=""
JSONL_LINE=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
ts() {
  date '+%H:%M:%S'
}

log() {
  local color="$1"
  local label="$2"
  local msg="$3"
  printf "${C_DIM}[%s]${C_RESET} ${color}%-9s${C_RESET} %s\n" "$(ts)" "$label" "$msg"
}

truncate60() {
  local s="$1"
  if [[ ${#s} -gt 60 ]]; then
    echo "${s:0:60}…"
  else
    echo "$s"
  fi
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# Exit handler
# ---------------------------------------------------------------------------
on_exit() {
  echo ""
  log "$C_DIM" "WATCH" "Stopped."
  echo ""
  echo "To review the full session transcript:"
  echo "  uvx claude-code-log \"$JSONL_DIR\" --open-browser"
  echo ""
}
trap on_exit INT TERM EXIT

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo "══════════════════════════════════════════"
echo "  ralph-watch — real-time loop observer"
echo "══════════════════════════════════════════"
echo "Project : $PROJECT_DIR"
echo "JSONL   : $JSONL_DIR"
echo "──────────────────────────────────────────"
echo "Waiting for loop to start..."
echo ""

# ---------------------------------------------------------------------------
# JSONL parser
# ---------------------------------------------------------------------------
parse_jsonl_line() {
  local line="$1"

  # Skip lines that aren't valid JSON
  echo "$line" | jq -e . &>/dev/null || return 0

  local ltype
  ltype=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || return 0

  # --- Tool errors ---
  if [[ "$ltype" == "user" ]]; then
    # Check for tool_result with is_error=true
    local err_content
    err_content=$(echo "$line" | jq -r '
      .message.content[]? |
      select(.type=="tool_result" and .is_error==true) |
      (.content // []) | if type=="array" then .[0].text // "" else . end
    ' 2>/dev/null) || return 0
    while IFS= read -r econtent; do
      [[ -z "$econtent" ]] && continue
      log "$C_RED" "ERROR" "\"$(truncate60 "$econtent")\""
    done <<< "$err_content"
    return 0
  fi

  # --- Stop hook summary errors ---
  if [[ "$ltype" == "system" ]]; then
    local subtype
    subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null) || return 0
    if [[ "$subtype" == "stop_hook_summary" ]]; then
      local hook_err
      hook_err=$(echo "$line" | jq -r '.hookErrors[0].message // empty' 2>/dev/null) || return 0
      if [[ -n "$hook_err" ]]; then
        log "$C_YELLOW" "HOOK ⚠" "$(truncate60 "$hook_err")"
      fi
    fi
    return 0
  fi

  # --- Assistant tool calls ---
  if [[ "$ltype" == "assistant" ]]; then
    local tool_items
    tool_items=$(echo "$line" | jq -r '
      .message.content[]? |
      select(.type=="tool_use") |
      [.name, (.input | @json)] | @tsv
    ' 2>/dev/null) || return 0

    while IFS=$'\t' read -r name input; do
      [[ -z "$name" ]] && continue

      case "$name" in
        Skill)
          local skill_name skill_args
          skill_name=$(echo "$input" | jq -r '.skill // empty' 2>/dev/null) || continue
          skill_args=$(echo "$input" | jq -r '.args // empty' 2>/dev/null) || continue
          if [[ "$skill_name" == *"ralph-loop"* ]]; then
            log "$C_BLUE" "LOOP" "/ralph-loop invoked (args: \"$(truncate60 "$skill_args")\")"
          fi
          ;;
        Task)
          local prompt
          prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null) || continue
          log "$C_BLUE" "SUBAGENT" "Spawning: \"$(truncate60 "$prompt")\""
          ;;
        Bash)
          local cmd
          cmd=$(echo "$input" | jq -r '.command // empty' 2>/dev/null) || continue
          log "$C_YELLOW" "TOOL" "Bash: \"$(truncate60 "$cmd")\""
          ;;
        Write)
          local fpath
          fpath=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null) || continue
          log "$C_YELLOW" "TOOL" "Write: $fpath"
          ;;
        Edit|MultiEdit)
          local fpath
          fpath=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null) || continue
          log "$C_YELLOW" "TOOL" "Edit: $fpath"
          ;;
        Read|Glob|Grep)
          # Silent — too noisy
          ;;
      esac
    done <<< "$tool_items"
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Main polling loop
# ---------------------------------------------------------------------------
RALPH_DIR="$PROJECT_DIR/.claude/ralph"
ACTIVE_FILE="$RALPH_DIR/.active"
PROGRESS_PTR="$RALPH_DIR/.current-progress"
LOOP_MARKER="$PROJECT_DIR/.claude/ralph-loop.local.md"

while true; do
  sleep 2

  # ---- 3a: Filesystem checks ----

  # Session lifecycle — .active
  CURR_SESSION=""
  if [[ -f "$ACTIVE_FILE" ]]; then
    CURR_SESSION=$(cat "$ACTIVE_FILE" 2>/dev/null || true)
  fi

  if [[ "$CURR_SESSION" != "$PREV_SESSION" ]]; then
    if [[ -n "$CURR_SESSION" && -z "$PREV_SESSION" ]]; then
      log "$C_GREEN" "SESSION" "Started: $CURR_SESSION"

      # Progress file pointer
      CURR_PROGRESS=""
      if [[ -f "$PROGRESS_PTR" ]]; then
        CURR_PROGRESS=$(cat "$PROGRESS_PTR" 2>/dev/null || true)
      fi
      if [[ -n "$CURR_PROGRESS" && "$CURR_PROGRESS" != "$PREV_PROGRESS" ]]; then
        log "$C_GREEN" "SESSION" "Progress: $CURR_PROGRESS"
        PREV_PROGRESS="$CURR_PROGRESS"
      fi

      # Task content — first non-blank line of ## Task section
      if [[ -n "$CURR_PROGRESS" && -f "$CURR_PROGRESS" ]]; then
        TASK_LINE=$(sed -n '/^## Task/,/^## /{/^## Task/d;/^## /d;p;}' "$CURR_PROGRESS" 2>/dev/null \
          | sed '/^$/d' | head -1 || true)
        if [[ -n "$TASK_LINE" ]]; then
          log "$C_CYAN" "TASK" "\"$(truncate60 "$TASK_LINE")\""
        fi
      fi

    elif [[ -z "$CURR_SESSION" && -n "$PREV_SESSION" ]]; then
      log "$C_GREEN" "SESSION" "Ended"
    elif [[ -n "$CURR_SESSION" && -n "$PREV_SESSION" ]]; then
      # Session changed (shouldn't normally happen, but handle it)
      log "$C_GREEN" "SESSION" "Changed: $CURR_SESSION"
    fi
    PREV_SESSION="$CURR_SESSION"
  fi

  # Progress file pointer change (mid-session)
  CURR_PROGRESS=""
  if [[ -f "$PROGRESS_PTR" ]]; then
    CURR_PROGRESS=$(cat "$PROGRESS_PTR" 2>/dev/null || true)
  fi
  if [[ -n "$CURR_PROGRESS" && "$CURR_PROGRESS" != "$PREV_PROGRESS" ]]; then
    # Only log outside session start (already logged above on session start)
    log "$C_GREEN" "SESSION" "Progress: $CURR_PROGRESS"
    PREV_PROGRESS="$CURR_PROGRESS"
  elif [[ -n "$CURR_PROGRESS" && -z "$PREV_PROGRESS" ]]; then
    PREV_PROGRESS="$CURR_PROGRESS"
  fi

  # Current step — ## Current section
  if [[ -n "$CURR_PROGRESS" && -f "$CURR_PROGRESS" ]]; then
    CURR_STEP=$(sed -n '/^## Current/,/^## /{/^## Current/d;/^## /d;p;}' "$CURR_PROGRESS" 2>/dev/null \
      | grep -E '^(Step:|Status:)' | head -2 | tr '\n' ' ' | sed 's/ $//' || true)
    if [[ -n "$CURR_STEP" && "$CURR_STEP" != "$PREV_STEP" ]]; then
      STEP_NUM=$(echo "$CURR_STEP" | sed -n 's/.*Step: \([^ ]*\).*/\1/p' || true)
      STEP_STATUS=$(echo "$CURR_STEP" | sed -n 's/.*Status: \([^ ]*\).*/\1/p' || true)
      log "$C_GREEN_BOLD" "PROGRESS" "Step: $STEP_NUM → Status: $STEP_STATUS"
      PREV_STEP="$CURR_STEP"
    fi
  fi

  # Loop state file — ralph-loop.local.md
  CURR_LOOP_EXISTS=""
  if [[ -f "$LOOP_MARKER" ]]; then
    CURR_LOOP_EXISTS="yes"
  fi

  if [[ "$CURR_LOOP_EXISTS" != "$PREV_LOOP_EXISTS" ]]; then
    if [[ "$CURR_LOOP_EXISTS" == "yes" ]]; then
      log "$C_BLUE" "LOOP" "Started"
    else
      log "$C_BLUE" "LOOP" "Ended"
      PREV_LOOP_PROMPT=""
    fi
    PREV_LOOP_EXISTS="$CURR_LOOP_EXISTS"
  fi

  # Postsetup detection — first non-`---` body line of loop state file
  if [[ -f "$LOOP_MARKER" ]]; then
    SECOND_DASH=$(grep -n '^---$' "$LOOP_MARKER" 2>/dev/null | awk -F: 'NR==2{print $1}' || true)
    if [[ -n "$SECOND_DASH" ]]; then
      CURR_LOOP_PROMPT=$(tail -n "+$((SECOND_DASH + 1))" "$LOOP_MARKER" 2>/dev/null \
        | sed '/^$/d' | head -1 || true)
      if [[ "$CURR_LOOP_PROMPT" != "$PREV_LOOP_PROMPT" && -n "$CURR_LOOP_PROMPT" ]]; then
        if echo "$CURR_LOOP_PROMPT" | grep -q '^Continue per '; then
          SESSION_FILE=$(echo "$CURR_LOOP_PROMPT" | sed 's/^Continue per //')
          log "$C_GREEN_BOLD" "POSTSETUP" "✓ Prompt rewritten → Continue per $(basename "$SESSION_FILE")"
        fi
        PREV_LOOP_PROMPT="$CURR_LOOP_PROMPT"
      fi
    fi
  fi

  # JSONL detection — merged (first-set uses 120s freshness guard; switch uses none)
  if [[ -d "$JSONL_DIR" ]]; then
    NEWEST=$(ls -t "$JSONL_DIR"/*.jsonl 2>/dev/null | head -1 || true)
    if [[ -n "$NEWEST" && "$NEWEST" != "$JSONL_FILE" ]]; then
      if [[ -z "$JSONL_FILE" ]]; then
        # First detection: require file modified in last 120s to avoid stale sessions
        if [[ $(( $(date +%s) - $(file_mtime "$NEWEST") )) -lt 120 ]]; then
          JSONL_FILE="$NEWEST"
          JSONL_LINE=0
          log "$C_DIM" "JSONL" "Watching: $(basename "$JSONL_FILE")"
        fi
      else
        # New session started: switch unconditionally
        JSONL_FILE="$NEWEST"
        JSONL_LINE=0
        log "$C_DIM" "JSONL" "Watching: $(basename "$JSONL_FILE")"
      fi
    fi
  fi

  # ---- 3b: JSONL new-line processing ----
  if [[ -n "$JSONL_FILE" && -f "$JSONL_FILE" ]]; then
    # NOTE: wc -l undercounts when the last line lacks a trailing newline.
    # In that narrow window, the unterminated line may be re-logged once when
    # the next line is appended. Claude Code's JSONL writer always terminates
    # lines, so this is cosmetic-only in practice.
    NEW_LINES=$(wc -l < "$JSONL_FILE" 2>/dev/null || echo 0)

    # Handle file replacement (line count decreased)
    if [[ "$NEW_LINES" -lt "$JSONL_LINE" ]]; then
      JSONL_LINE=0
    fi

    if [[ "$NEW_LINES" -gt "$JSONL_LINE" ]]; then
      while IFS= read -r jsonl_line; do
        parse_jsonl_line "$jsonl_line"
      done < <(tail -n "+$((JSONL_LINE + 1))" "$JSONL_FILE" 2>/dev/null || true)
      JSONL_LINE="$NEW_LINES"
    fi
  fi

done
