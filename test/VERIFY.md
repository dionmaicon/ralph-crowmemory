# Ralph Dry-Run Verification Checklist

This document describes the manual checks to run after `test/dry-run.sh` to confirm that Crow Memory fully replaces git for ralph's persistence layer.

The dry-run harness never calls `git commit` or `git checkout`. It mutates a throwaway `TARGET.md` inside `test/.sandbox/run-*/` and stores per-story progress in the Crow Memory MCP server.

## Prerequisites

- Crow Memory MCP server reachable from your agent (`mcp__crow-memory__*` tools respond).
- Claude Code or Amp CLI installed and authenticated (Claude Code is the default target).

## 1. Fresh-Project Run (fixture v1)

```bash
./test/dry-run.sh --fixture v1
```

Expected:

| Check | How to verify |
|---|---|
| (a) 3 memories exist for the project | `mcp__crow-memory__recall_by_tag` with `tags=["project:test-crow-ralph"]`, `top_k=20` → 3 results, one per story |
| (b) Stories are linked | `mcp__crow-memory__get_related_memories` on the US-003 memory → shows `depends-on` → US-002 → US-001 |
| (c) All stories pass | `jq '.userStories[] | {id, passes}' test/.sandbox/run-*/prd.json` → all `true` |
| (d) Progress log updated | `test/.sandbox/run-*/progress.txt` contains 3 appended blocks with a `Memory: <vector_id>` line each |
| (e) No git mutations | Inside the sandbox: `test -d .git` returns non-zero (no repo created), and the parent repo's `git log` has no new commits from the run |
| (f) TARGET.md reflects all three stories | Marker block in `test/.sandbox/run-*/TARGET.md` contains `LINE-A`, `LINE-B`, and a valid `TIMESTAMP:` line |

## 2. Stale-Memory Archive (reset the same project)

Reset `passes` back to `false` in the sandbox `prd.json` to simulate a project restart, then run again:

```bash
# In the sandbox:
jq '.userStories[].passes = false' test/.sandbox/run-*/prd.json > /tmp/prd_reset.json
cp /tmp/prd_reset.json test/.sandbox/run-*/prd.json

# Re-run (keep sandbox)
./test/dry-run.sh --keep
```

Expected:

| Check | How to verify |
|---|---|
| (a) Old completed memories archived | `mcp__crow-memory__recall_by_tag tags=["project:test-crow-ralph"]` → prior run entries show `archived: true` |
| (b) New memories created for the fresh run | Same tag query → 3 new entries with later `created_at` timestamps |
| (c) No other project touched | `mcp__crow-memory__recall_by_tag tags=["project:test-crow-ralph-v2"]` (or any other project tag) → zero archived entries |

## 3. Restore Path

Pick one archived memory from step 2 (its `vector_id`) and call:

```
mcp__crow-memory__restore_memory vector_id=<uuid>
```

Expected: `archived: false` after the call. Confirms archive is reversible.

## 4. No-Git Sweep

From the repo root:

```bash
grep -rn "git " ralph.sh prompt.md CLAUDE.md AGENTS.md README.md skills/
```

Expected: zero hits, other than historical references (e.g. "replaces git", "no git commits"). No live `git commit` / `git checkout` / `git branch` invocations.

## Cleanup

Sandboxes accumulate under `test/.sandbox/`. Safe to delete entire folder when done:

```bash
rm -rf test/.sandbox
```

The archived Crow Memory entries remain in the MCP server. Use `mcp__crow-memory__forget` (permanent) only if you want to purge them; otherwise `restore_memory` keeps them available for future reference.
