#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude] [--auto-resume] [max_iterations]
#
# Persistence between iterations is handled by the Crow Memory MCP server
# (mcp__crow-memory__*). The agent stores per-story entries, loads prior
# context via recall_by_tag, and archives stale same-project memories.
# ralph.sh itself no longer manages branches or archives.
#
# --auto-resume (claude only): if the tool reports a rate-limit / quota
# wall, parse the reset time and schedule a one-shot resume via `at`
# (fallback: nohup sleep; final fallback: print the command).

set -e

TOOL="amp"
MAX_ITERATIONS=10
AUTO_RESUME=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --auto-resume)
      AUTO_RESUME=1
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
LOG_DIR="$SCRIPT_DIR/.ralph-logs"

# ---------------------------------------------------------------------------
# Rate-limit detection tables (extend here as new tools / banners appear)
# ---------------------------------------------------------------------------
declare -A RATE_LIMIT_PATTERNS=(
  [claude]='out of extra usage|usage limit reached|5-hour limit reached|quota exceeded|rate limit exceeded'
  # [amp]=''   # unknown banners — leave empty to skip auto-resume
)
declare -A RESET_EXTRACTORS=(
  [claude]='resets[[:space:]]+(at[[:space:]]+)?[0-9]{1,2}(:[0-9]{2})?[[:space:]]*([ap]m|[AP]M)?[[:space:]]*(\([^)]+\))?'
)

detect_rate_limit() {
  local output="$1" tool="$2"
  local pattern="${RATE_LIMIT_PATTERNS[$tool]:-}"
  [ -z "$pattern" ] && return 1
  echo "$output" | grep -qiE "$pattern"
}

extract_reset_hint() {
  local output="$1" tool="$2"
  local extractor="${RESET_EXTRACTORS[$tool]:-}"
  [ -z "$extractor" ] && return 1
  echo "$output" | grep -oiE "$extractor" | head -n1
}

# Parse "resets 2am (America/Sao_Paulo)" / "resets at 2:45am" into an epoch.
# Prints the epoch to stdout, or nothing on failure.
parse_reset_epoch() {
  local hint="$1"
  local tz time now_epoch target_epoch
  # Only use a named tz if we parsed one from parens (e.g. "America/Sao_Paulo").
  # Leaving tz empty means date(1) uses the system local zone — which is the
  # correct default. Do NOT fall back to $(date +%Z), because that returns a
  # numeric offset like "-03" that POSIX interprets with inverted sign.
  tz=$(echo "$hint" | grep -oE '\([^)]+\)' | tr -d '()' | head -n1)
  # Defense-in-depth: only accept tz chars that appear in IANA zone names.
  [[ "$tz" =~ ^[A-Za-z0-9_/+-]+$ ]] || tz=""
  time=$(echo "$hint" | grep -oiE '[0-9]{1,2}(:[0-9]{2})?[[:space:]]*([ap]m)?' \
    | head -n1 | tr -d ' ' | tr 'APM' 'apm')
  [ -z "$time" ] && return 1

  now_epoch=$(date +%s)
  if [ -n "$tz" ]; then
    target_epoch=$(TZ="$tz" date -d "today $time" +%s 2>/dev/null || echo "")
  else
    target_epoch=$(date -d "today $time" +%s 2>/dev/null || echo "")
  fi
  if [ -z "$target_epoch" ] || [ "$target_epoch" -le "$now_epoch" ]; then
    if [ -n "$tz" ]; then
      target_epoch=$(TZ="$tz" date -d "tomorrow $time" +%s 2>/dev/null || echo "")
    else
      target_epoch=$(date -d "tomorrow $time" +%s 2>/dev/null || echo "")
    fi
  fi
  [ -n "$target_epoch" ] && echo "$target_epoch"
}

# Schedule a resume of this script at the given epoch.
# Chain: at -> nohup sleep -> print. Prints status to stderr/stdout.
schedule_resume() {
  local epoch="$1"
  local buffer_epoch=$((epoch + 300))  # 5-min buffer past reset
  local resume_args=""
  [ "$TOOL" != "amp" ] && resume_args="--tool $TOOL "
  [ "$AUTO_RESUME" -eq 1 ] && resume_args="${resume_args}--auto-resume "
  resume_args="${resume_args}${MAX_ITERATIONS}"
  # %q-quote SCRIPT_DIR so odd chars (", $, backtick, spaces) can't break
  # out of the bash -c / at stdin contexts below.
  local script_dir_q
  printf -v script_dir_q '%q' "$SCRIPT_DIR"
  local resume_cmd="cd $script_dir_q && ./ralph.sh $resume_args"

  mkdir -p "$LOG_DIR"

  # Attempt 1: at
  if command -v at >/dev/null 2>&1 && systemctl is-active atd >/dev/null 2>&1; then
    local at_time at_err
    at_time=$(date -d "@$buffer_epoch" +%Y%m%d%H%M)
    at_err=$(mktemp "$LOG_DIR/at-err.XXXXXX") || at_err="$LOG_DIR/at-err.$$"
    if echo "$resume_cmd" | at -t "$at_time" 2>"$at_err"; then
      echo "Resume scheduled via 'at' for $(date -d @$buffer_epoch)"
      echo "Inspect pending jobs with: atq"
      return 0
    else
      echo "'at' invocation failed (see $at_err). Falling back."
    fi
  fi

  # Attempt 2: nohup sleep
  if command -v nohup >/dev/null 2>&1; then
    local delta=$((buffer_epoch - $(date +%s)))
    [ "$delta" -lt 1 ] && delta=1
    local log
    log=$(mktemp "$LOG_DIR/resume.XXXXXX.log") || log="$LOG_DIR/resume.$$.log"
    echo "at/atd not available — using nohup+sleep fallback."
    echo "For reboot-safe scheduling, install at:"
    echo "  sudo apt install at && sudo systemctl enable --now atd"
    nohup bash -c "sleep $delta && $resume_cmd" >"$log" 2>&1 &
    echo "Resume scheduled via nohup (pid $!, log $log)"
    return 0
  fi

  # Attempt 3: print only
  echo "No scheduler available. Run this at $(date -d @$buffer_epoch):"
  echo "  $resume_cmd"
  return 1
}

# ---------------------------------------------------------------------------
# Initialize progress file
# ---------------------------------------------------------------------------
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS - Auto-resume: $AUTO_RESUME"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(amp --dangerously-allow-all < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr) || true
  else
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
  fi

  # Rate-limit / quota detection — short-circuit the loop so we don't burn iterations
  if detect_rate_limit "$OUTPUT" "$TOOL"; then
    hint=$(extract_reset_hint "$OUTPUT" "$TOOL" || true)
    echo ""
    echo "=== Rate limit detected ($TOOL) ==="
    [ -n "$hint" ] && echo "Reset hint: $hint"

    if [ "$AUTO_RESUME" -eq 1 ] && [ -n "${RATE_LIMIT_PATTERNS[$TOOL]:-}" ]; then
      epoch=$(parse_reset_epoch "$hint" || true)
      if [ -n "$epoch" ]; then
        schedule_resume "$epoch"
      else
        echo "Could not parse reset time from hint. Re-run ./ralph.sh manually after the quota resets."
      fi
    elif [ -z "${RATE_LIMIT_PATTERNS[$TOOL]:-}" ]; then
      echo "No rate-limit pattern configured for tool '$TOOL'. Auto-resume skipped."
    else
      echo "Auto-resume not enabled. Re-run with --auto-resume to schedule automatically."
    fi
    exit 2
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
