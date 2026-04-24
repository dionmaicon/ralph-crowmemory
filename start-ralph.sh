#!/bin/bash
# start-ralph.sh — bootstrap Ralph (Crow Memory fork) into the current project.
#
# Global install (one-time):
#   mkdir -p ~/.local/bin
#   curl -fsSL https://raw.githubusercontent.com/dionmaicon/ralph-crowmemory/main/start-ralph.sh \
#     -o ~/.local/bin/start-ralph && chmod +x ~/.local/bin/start-ralph
#   # Ensure ~/.local/bin is on PATH (add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc).
#
# Run `start-ralph --help` for all flags and examples.

set -u
set -o pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

REPO="dionmaicon/ralph-crowmemory"
BRANCH="main"
TOOL="claude"
FORCE=0
AUTO=0
RUN=0
WITH_TEST=1
ITERATIONS=10

FETCH_ERRORS=()

# --- helpers ---------------------------------------------------------------

die() {
  echo "Error: $*" >&2
  exit 1
}

warn() {
  echo "Warning: $*" >&2
}

on_error() {
  local exit_code=$?
  echo "" >&2
  echo "=== $SCRIPT_NAME failed (exit $exit_code) ===" >&2
  echo "The project may be in a partially-downloaded state. Inspect the current" >&2
  echo "directory, delete any .tmp files, and re-run with --force to retry:" >&2
  echo "  $SCRIPT_NAME --force" >&2
}
trap on_error ERR

usage() {
  cat <<EOF
$SCRIPT_NAME — bootstrap Ralph (Crow Memory fork) into the current project.

Usage:
  $SCRIPT_NAME [options]

Options:
  --tool amp|claude      AI coding tool to target for --auto / --run (default: claude).
  --run                  After setup, launch ./ralph.sh immediately (requires prd.json).
  --auto                 Pipe the generated merge prompt through the selected tool
                         to merge Ralph into an existing CLAUDE.md automatically.
                         NOTE: --auto invokes the tool with its permissive mode
                         (--dangerously-skip-permissions / --dangerously-allow-all).
  --force                Overwrite existing ralph.sh, prompt.md, AGENTS.md, CLAUDE.md.
  --iterations N         Pass N to ralph.sh when --run is set (default: 10).
  --branch REF           Pull files from REF on the source repo (default: main).
  --repo OWNER/NAME      Pull files from a different fork (default: $REPO).
  --no-test              Skip downloading the test/ dry-run harness.
  -h, --help             Show this message.

Examples:
  # 1. Quickest start (existing project with its own CLAUDE.md):
  cd ~/code/my-app
  $SCRIPT_NAME
  #  → downloads ralph.sh, prompt.md, AGENTS.md, CLAUDE.ralph.md, test/
  #  → writes RALPH_SETUP_PROMPT.md
  #  Next: run that prompt through claude / amp, then create prd.json.

  # 2. One-shot bootstrap + auto-merge CLAUDE.md via claude:
  $SCRIPT_NAME --auto

  # 3. Fresh project, no existing CLAUDE.md — install and go:
  mkdir my-new-app && cd my-new-app
  $SCRIPT_NAME
  #  → installs Ralph CLAUDE.md directly (no merge prompt needed).

  # 4. Setup AND launch Ralph immediately (you already staged prd.json):
  $SCRIPT_NAME --tool claude --run --iterations 20

  # 5. Re-sync to latest from repo, overwriting your existing ralph runtime:
  $SCRIPT_NAME --force

  # 6. Pull from a fork / feature branch:
  $SCRIPT_NAME --repo you/ralph-crowmemory --branch experiment

  # 7. Slim install (no dry-run harness):
  $SCRIPT_NAME --no-test

  # 8. Use Amp instead of Claude:
  $SCRIPT_NAME --tool amp --auto
EOF
}

# --- arg parsing -----------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)          [[ $# -ge 2 ]] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --repo=*)        REPO="${1#*=}"; shift ;;
    --branch)        [[ $# -ge 2 ]] || die "--branch requires a value"; BRANCH="$2"; shift 2 ;;
    --branch=*)      BRANCH="${1#*=}"; shift ;;
    --tool)          [[ $# -ge 2 ]] || die "--tool requires a value"; TOOL="$2"; shift 2 ;;
    --tool=*)        TOOL="${1#*=}"; shift ;;
    --force)         FORCE=1; shift ;;
    --auto)          AUTO=1; shift ;;
    --run)           RUN=1; shift ;;
    --no-test)       WITH_TEST=0; shift ;;
    --iterations)    [[ $# -ge 2 ]] || die "--iterations requires a value"; ITERATIONS="$2"; shift 2 ;;
    --iterations=*)  ITERATIONS="${1#*=}"; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; break ;;
    -*)              echo "Unknown option: $1" >&2; echo "Run '$SCRIPT_NAME --help' for usage." >&2; exit 2 ;;
    *)               echo "Unexpected argument: $1" >&2; echo "Run '$SCRIPT_NAME --help' for usage." >&2; exit 2 ;;
  esac
done

# --- validation ------------------------------------------------------------

[[ -n "$REPO" ]]   || die "--repo cannot be empty."
[[ -n "$BRANCH" ]] || die "--branch cannot be empty."

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  die "--tool must be 'amp' or 'claude' (got '$TOOL')."
fi

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
  die "--iterations must be a positive integer (got '$ITERATIONS')."
fi

if ! command -v curl >/dev/null 2>&1; then
  die "curl is required but not found in PATH."
fi

# --- bootstrap -------------------------------------------------------------

RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TARGET_DIR="$(pwd)"

echo "Bootstrapping Ralph (Crow Memory fork)"
echo "  Repo:   $REPO @ $BRANCH"
echo "  Dir:    $TARGET_DIR"
echo "  Tool:   $TOOL"
echo ""

fetch() {
  # fetch <remote-rel-path> <local-rel-path>
  local rel="$1" dst="$2"
  local url="$RAW_BASE/$rel"

  # CLAUDE.md is handled via a staging filename (CLAUDE.ralph.md) so we never
  # overwrite an existing project CLAUDE.md implicitly.
  if [ -f "$dst" ] && [ "$FORCE" -eq 0 ] && [ "$dst" != "CLAUDE.ralph.md" ]; then
    echo "  skip  $dst (exists — use --force to overwrite)"
    return 0
  fi

  mkdir -p "$(dirname "$dst")" || { FETCH_ERRORS+=("mkdir $(dirname "$dst") failed"); return 1; }

  local http_code
  http_code=$(curl -sSL -o "$dst.tmp" -w "%{http_code}" "$url" || echo "000")
  if [[ "$http_code" == "200" ]]; then
    mv "$dst.tmp" "$dst"
    echo "  ok    $dst"
    return 0
  fi

  rm -f "$dst.tmp"
  case "$http_code" in
    000) FETCH_ERRORS+=("$dst ← $url (network error: could not connect)") ;;
    404) FETCH_ERRORS+=("$dst ← $url (404: ref '$BRANCH' or path not found — check --branch / --repo)") ;;
    401|403) FETCH_ERRORS+=("$dst ← $url (HTTP $http_code: auth required — is the repo private?)") ;;
    5*)  FETCH_ERRORS+=("$dst ← $url (HTTP $http_code: GitHub raw server error — retry in a moment)") ;;
    *)   FETCH_ERRORS+=("$dst ← $url (HTTP $http_code)") ;;
  esac
  echo "  FAIL  $dst  (HTTP $http_code)"
  return 1
}

echo "Downloading runtime files..."
fetch ralph.sh    ralph.sh    || true
fetch prompt.md   prompt.md   || true
fetch AGENTS.md   AGENTS.md   || true

# CLAUDE.md: pull Ralph's version to a staging name first so we can detect
# whether the project already has its own CLAUDE.md.
RALPH_CLAUDE="CLAUDE.ralph.md"
fetch CLAUDE.md "$RALPH_CLAUDE" || true

if [ "$WITH_TEST" -eq 1 ]; then
  echo ""
  echo "Downloading dry-run harness..."
  fetch test/dry-run.sh              test/dry-run.sh              || true
  fetch test/VERIFY.md               test/VERIFY.md               || true
  fetch test/fixtures/prd.json       test/fixtures/prd.json       || true
  fetch test/fixtures/prd-v2.json    test/fixtures/prd-v2.json    || true
  [ -f test/dry-run.sh ] && chmod +x test/dry-run.sh
fi

# Abort if any core file failed; test/ failures are fatal only if those files
# are the only ones that failed AND --no-test was not set (we still want to
# surface them).
if [ "${#FETCH_ERRORS[@]}" -gt 0 ]; then
  echo "" >&2
  echo "=== Download errors ($(( ${#FETCH_ERRORS[@]} ))) ===" >&2
  for e in "${FETCH_ERRORS[@]}"; do echo "  - $e" >&2; done
  echo "" >&2
  echo "Nothing was installed. Common fixes:" >&2
  echo "  - Check your internet connection." >&2
  echo "  - Verify --repo ($REPO) and --branch ($BRANCH) are correct." >&2
  echo "  - For private forks, pre-authenticate curl or clone instead." >&2
  exit 3
fi

[ -f ralph.sh ] && chmod +x ralph.sh

echo ""
echo "Deciding CLAUDE.md strategy..."
PROMPT_FILE="RALPH_SETUP_PROMPT.md"
if [ -f "CLAUDE.md" ] && [ "$FORCE" -eq 0 ]; then
  echo "  Existing CLAUDE.md found — will NOT overwrite."
  echo "  Ralph template kept at: $RALPH_CLAUDE"

  if ! cat > "$PROMPT_FILE" <<EOF
# Ralph Setup Merge Prompt

You are configuring this project to run under **Ralph (Crow Memory fork)** — an autonomous AI agent loop that replaces git-based persistence with the Crow Memory MCP server.

## Your task

1. Read the project's current \`CLAUDE.md\`. Preserve every section that is project-specific (domain knowledge, code conventions, stack notes, commands, gotchas).
2. Read the Ralph agent instructions at \`$RALPH_CLAUDE\`.
3. Merge the Ralph instructions into the existing \`CLAUDE.md\`:
   - Append Ralph's agent-task sections under a new \`## Ralph Agent Instructions\` top-level heading so they do not collide with existing headings.
   - Keep the full \`## Your Task\` numbered list verbatim — the ralph loop depends on those exact steps and the stale-memory archive semantics.
   - Keep the \`## Per-Story Memory Content Template\`, \`## Progress Report Format (progress.txt)\`, \`## Quality Requirements\`, \`## Stop Condition\`, and \`## Important\` sections verbatim.
   - Drop any duplicate or obsolete guidance that contradicts Ralph (e.g. existing "run git commit" instructions).
4. Do NOT delete or reword existing project-specific context unless it directly contradicts Ralph's rules. When in doubt, keep both and add a short note.
5. After merging, delete \`$RALPH_CLAUDE\` so only the merged \`CLAUDE.md\` remains.
6. Summarise the merge in 3-5 bullets: what you added, what you preserved, anything you intentionally dropped.

## Constraints

- Do NOT run \`git commit\`, \`git checkout\`, or any git mutation.
- Do NOT modify \`ralph.sh\`, \`prompt.md\`, \`AGENTS.md\`, or files under \`test/\`.
- Do NOT create \`prd.json\` — that is the next manual step (see below).

## After you finish

Tell the user to:
1. Generate a PRD via the \`/prd\` skill (or paste their own PRD).
2. Run the \`/ralph\` skill to convert it into \`prd.json\` with the \`project:<branchName>\` tag.
3. Launch the loop: \`./ralph.sh --tool $TOOL $ITERATIONS\` (or \`--auto-resume\` for long runs).
EOF
  then
    die "Failed to write $PROMPT_FILE (disk full or permission denied?)."
  fi

  echo "  Wrote merge prompt: $PROMPT_FILE"
else
  if [ -f "CLAUDE.md" ] && [ "$FORCE" -eq 1 ]; then
    echo "  --force set: replacing existing CLAUDE.md with Ralph template."
  else
    echo "  No existing CLAUDE.md — installing Ralph template as CLAUDE.md."
  fi
  mv "$RALPH_CLAUDE" CLAUDE.md || die "Could not move $RALPH_CLAUDE → CLAUDE.md."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Files in place:"
echo "  ralph.sh         (executable)"
echo "  prompt.md        (amp prompt template)"
echo "  CLAUDE.md        (agent instructions)"
echo "  AGENTS.md        (ralph overview)"
[ "$WITH_TEST" -eq 1 ]    && echo "  test/            (dry-run harness)"
[ -f "$PROMPT_FILE" ]     && echo "  $PROMPT_FILE  (merge prompt — feed to your AI tool)"
[ -f "$RALPH_CLAUDE" ]    && echo "  $RALPH_CLAUDE    (Ralph CLAUDE.md template, merge pending)"

echo ""
echo "Next steps:"
step=1
if [ -f "$PROMPT_FILE" ]; then
  if [ "$AUTO" -eq 1 ]; then
    if command -v "$TOOL" >/dev/null 2>&1; then
      echo "  [auto] Running $TOOL with merge prompt ($TOOL's permissive mode will be enabled)..."
      if [ "$TOOL" = "claude" ]; then
        claude --dangerously-skip-permissions --print < "$PROMPT_FILE" || warn "$TOOL exited non-zero — inspect CLAUDE.md manually."
      else
        amp --dangerously-allow-all < "$PROMPT_FILE" || warn "$TOOL exited non-zero — inspect CLAUDE.md manually."
      fi
    else
      warn "$TOOL not in PATH — skipping --auto merge. Run it manually:"
      echo "       $TOOL < $PROMPT_FILE"
    fi
  else
    echo "  $step. Merge CLAUDE.md:"
    echo "       claude --print < $PROMPT_FILE"
    echo "     or"
    echo "       amp < $PROMPT_FILE"
    echo "     (or re-run: $SCRIPT_NAME --auto)"
    step=$((step + 1))
  fi
fi
echo "  $step. Create prd.json via the /prd and /ralph skills."
step=$((step + 1))
echo "  $step. Launch: ./ralph.sh --tool $TOOL $ITERATIONS"
echo "     Long runs: add --auto-resume to survive Claude rate-limit windows."
echo ""

if [ "$RUN" -eq 1 ]; then
  if [ ! -f "prd.json" ]; then
    die "Cannot --run: no prd.json in $TARGET_DIR. Create one first (/prd → /ralph)."
  fi
  echo "Launching ralph.sh..."
  ./ralph.sh --tool "$TOOL" "$ITERATIONS"
fi
