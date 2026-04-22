#!/bin/bash
# Ralph dry-run harness.
#
# Creates a throwaway sandbox under test/.sandbox/, copies ralph runtime
# files + a fixture prd.json, seeds a trivial target file, then runs
# ralph.sh. No git mutations. Sandbox is preserved for manual inspection.
#
# Usage:
#   ./test/dry-run.sh                    # fresh sandbox, fixture v1
#   ./test/dry-run.sh --fixture v2       # use v2 fixture
#   ./test/dry-run.sh --keep             # reuse most recent sandbox
#   ./test/dry-run.sh --tool amp         # pass through to ralph.sh (default: claude)
#   ./test/dry-run.sh --iterations 5     # max iterations (default: 3)

set -e

FIXTURE="v1"
KEEP=0
TOOL="claude"
ITERATIONS=3

while [[ $# -gt 0 ]]; do
  case $1 in
    --fixture) FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#*=}"; shift ;;
    --keep) KEEP=1; shift ;;
    --tool) TOOL="$2"; shift 2 ;;
    --tool=*) TOOL="${1#*=}"; shift ;;
    --iterations) ITERATIONS="$2"; shift 2 ;;
    --iterations=*) ITERATIONS="${1#*=}"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SANDBOX_ROOT="$HERE/.sandbox"

case "$FIXTURE" in
  v1) FIXTURE_FILE="$HERE/fixtures/prd.json" ;;
  v2) FIXTURE_FILE="$HERE/fixtures/prd-v2.json" ;;
  *) echo "Unknown fixture: $FIXTURE (expected v1 or v2)"; exit 1 ;;
esac

if [ ! -f "$FIXTURE_FILE" ]; then
  echo "Fixture not found: $FIXTURE_FILE"
  exit 1
fi

mkdir -p "$SANDBOX_ROOT"

if [ "$KEEP" -eq 1 ]; then
  SANDBOX=$(ls -1dt "$SANDBOX_ROOT"/run-* 2>/dev/null | head -n1)
  if [ -z "$SANDBOX" ]; then
    echo "No existing sandbox found to --keep. Creating a fresh one."
    SANDBOX="$SANDBOX_ROOT/run-$(date +%s)"
    mkdir -p "$SANDBOX"
  else
    echo "Reusing sandbox: $SANDBOX"
  fi
else
  SANDBOX="$SANDBOX_ROOT/run-$(date +%s)"
  mkdir -p "$SANDBOX"
fi

cp "$REPO_ROOT/ralph.sh"    "$SANDBOX/ralph.sh"
cp "$REPO_ROOT/prompt.md"   "$SANDBOX/prompt.md"
cp "$REPO_ROOT/CLAUDE.md"   "$SANDBOX/CLAUDE.md"
cp "$REPO_ROOT/AGENTS.md"   "$SANDBOX/AGENTS.md"
cp "$FIXTURE_FILE"          "$SANDBOX/prd.json"
chmod +x "$SANDBOX/ralph.sh"

if [ ! -f "$SANDBOX/TARGET.md" ]; then
  cat > "$SANDBOX/TARGET.md" <<'EOF'
# Target file for dry-run
<!-- MARKER-START -->
<!-- MARKER-END -->
EOF
fi

echo ""
echo "Sandbox: $SANDBOX"
echo "Fixture: $FIXTURE ($FIXTURE_FILE)"
echo "Tool:    $TOOL"
echo "Iters:   $ITERATIONS"
echo ""

cd "$SANDBOX"
./ralph.sh --tool "$TOOL" "$ITERATIONS" || true

echo ""
echo "=== Dry-run complete ==="
echo "Sandbox preserved at: $SANDBOX"
echo "See test/VERIFY.md for the manual check list."
