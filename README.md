# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via the **Crow Memory MCP** server, `progress.txt`, and `prd.json`.

> **This fork replaces git with Crow Memory MCP.** Per-story commits, branch management, and `git log`-as-memory are replaced by Crow Memory entries tagged `project:<branchName>` and linked with `depends-on` across stories. The agent never runs `git commit` or `git checkout`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- **Crow Memory MCP server** configured and reachable by the agent (provides the `mcp__crow-memory__*` tool family that replaces git-based persistence)

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/

# Copy the prompt template for your AI tool of choice:
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md    # For Amp
# OR
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md    # For Claude Code

chmod +x scripts/ralph/ralph.sh
```

### Option 2: Install skills globally (Amp)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph (Crow Memory fork) marketplace to Claude Code from a local checkout:

```bash
/plugin marketplace add /path/to/ralph-crowmemory
```

Then install the skills:

```bash
/plugin install ralph-crowmemory-skills@ralph-crowmemory-marketplace
```

Available skills after installation:
- `/prd` - Generate Product Requirements Documents
- `/ralph` - Convert PRDs to prd.json format (writes the `project:<branchName>` tag used by Crow Memory)

**What the plugin installs:**
- `skills/prd/` — PRD generation skill
- `skills/ralph/` — PRD → `prd.json` conversion skill (updated w/ Crow Memory archive semantics)

**What it does NOT install:**
- `ralph.sh` — the runner loop
- `prompt.md` / `CLAUDE.md` — prompt templates
- `test/` — dry-run harness

Those are per-project files — copy them into whichever project you want to run ralph against (see Option 1 above). The plugin is just the skills bundle.

Skills are automatically invoked when you ask Claude to:
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

### Option 4: Global `start-ralph` bootstrap (recommended for new projects)

One command pulls the latest Ralph runtime (ralph.sh, prompt.md, CLAUDE.md, test harness) into any project directory and stages a CLAUDE.md merge prompt so you do not clobber existing project instructions.

**Install the global command (one-time):**

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/dionmaicon/ralph-crowmemory/main/start-ralph.sh \
  -o ~/.local/bin/start-ralph && chmod +x ~/.local/bin/start-ralph
# Ensure ~/.local/bin is on your PATH.
```

**Command-line examples** (run `start-ralph --help` for the full list):

```bash
# 1. Quickest start (existing project with its own CLAUDE.md):
cd ~/code/my-app
start-ralph
#  → downloads ralph.sh, prompt.md, AGENTS.md, CLAUDE.ralph.md, test/
#  → writes RALPH_SETUP_PROMPT.md
#  Next: pipe that prompt through claude / amp, then create prd.json.

# 2. One-shot bootstrap + auto-merge CLAUDE.md via claude:
start-ralph --auto

# 3. Fresh project, no existing CLAUDE.md — install and go:
mkdir my-new-app && cd my-new-app
start-ralph
#  → installs Ralph CLAUDE.md directly (no merge prompt needed).

# 4. Setup AND launch Ralph immediately (you already staged prd.json):
start-ralph --tool claude --run --iterations 20

# 5. Re-sync to latest from the repo, overwriting your existing ralph runtime:
start-ralph --force

# 6. Pull from a fork / feature branch:
start-ralph --repo you/ralph-crowmemory --branch experiment

# 7. Slim install (no dry-run harness):
start-ralph --no-test

# 8. Use Amp instead of Claude:
start-ralph --tool amp --auto
```

**Flags:**

| Flag | Purpose |
|---|---|
| `--tool amp\|claude` | Tool used by `--auto` / `--run` (default `claude`). |
| `--auto` | Pipe the generated merge prompt into the selected tool (uses its permissive flag). |
| `--run` | After setup, launch `./ralph.sh` immediately. Requires `prd.json`. |
| `--iterations N` | Iterations passed to `ralph.sh` on `--run` (default 10). |
| `--force` | Overwrite existing `ralph.sh`, `prompt.md`, `AGENTS.md`, `CLAUDE.md`. |
| `--branch REF` | Pull from a non-main ref (default `main`). |
| `--repo OWNER/NAME` | Pull from a different fork (default `dionmaicon/ralph-crowmemory`). |
| `--no-test` | Skip the `test/` dry-run harness. |
| `-h`, `--help` | Show usage with examples. |

**What `start-ralph` does:**

1. Downloads `ralph.sh`, `prompt.md`, `AGENTS.md`, and `test/` from this repo into the current directory.
2. If the project already has a `CLAUDE.md`, saves the Ralph template as `CLAUDE.ralph.md` and emits `RALPH_SETUP_PROMPT.md` — a ready-to-paste prompt that tells an AI tool to merge Ralph instructions into your existing `CLAUDE.md` without losing project context.
3. Otherwise, installs the Ralph `CLAUDE.md` directly.
4. With `--auto`, pipes the merge prompt through `claude` (or `amp`) to perform the merge automatically.
5. With `--run`, launches `./ralph.sh` after setup (requires `prd.json` already in place).

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | Bad input (invalid `--tool`, non-numeric `--iterations`, missing `curl`, missing `prd.json` on `--run`). |
| 2 | Unknown flag / unexpected positional argument. |
| 3 | Download failed (see per-file HTTP codes printed above the error block). |

After bootstrap, create `prd.json` via the `/prd` and `/ralph` skills, then run `./ralph.sh --tool claude` (add `--auto-resume` for long runs).

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Workflow

### 1. Create a PRD

Use the PRD skill to generate a detailed requirements document:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the Ralph skill to convert the markdown PRD to JSON:

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
# Using Amp (default)
./scripts/ralph/ralph.sh [max_iterations]

# Using Claude Code
./scripts/ralph/ralph.sh --tool claude [max_iterations]

# Using Claude Code with auto-resume on rate-limit hits
./scripts/ralph/ralph.sh --tool claude --auto-resume [max_iterations]
```

Default is 10 iterations. Use `--tool amp` or `--tool claude` to select your AI coding tool.

### Auto-Resume on Rate-Limit (Claude only)

Long PRDs often hit Claude's usage window mid-run. Pass `--auto-resume` and ralph will:

1. Detect a rate-limit banner in the tool output (e.g. `You're out of extra usage · resets 2am (America/Sao_Paulo)`, `usage limit reached`, `5-hour limit reached`).
2. Parse the reset time — including the timezone if the banner provides one in parentheses.
3. Stop the loop immediately (no more wasted iterations on the quota wall).
4. Schedule a single-shot resume of `./ralph.sh --tool claude --auto-resume <max_iterations>` 5 minutes past the reset time.

Scheduling chain (first working option wins):

| Option | When it runs | Notes |
|---|---|---|
| `at` | `atd` active and `at` installed | Preferred. One-shot, auto-removes after execution. Inspect with `atq`. |
| `nohup sleep` | `at` unavailable | Background process survives shell exit but not reboots/suspends. Log written under `.ralph-logs/resume.*.log` (next to `ralph.sh`). |
| Print only | Neither available | Exits with the command for you to run manually. |

**Retry chain.** The scheduled run receives `--auto-resume` again, so if it hits another quota wall it reschedules itself. Runs continue across reset windows until all stories pass or `max_iterations` is reached.

**Install `at` for reboot-safe scheduling** (Debian/Ubuntu):

```bash
sudo apt install at
sudo systemctl enable --now atd
```

This does not conflict with an existing `cron` service — `at` uses its own daemon (`atd`) and queue.

**Amp and other tools** currently skip auto-resume (the pattern table for their banners is not populated). Extend `RATE_LIMIT_PATTERNS` / `RESET_EXTRACTORS` in `ralph.sh` if you want to add them.

Ralph will:
1. Load prior context from Crow Memory via `recall_by_tag tags=["project:<branchName>"]`
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Store a Crow Memory entry for the story (files/lines/decisions/pending) and link it `depends-on` the previous story
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh AI instances (supports `--tool amp` or `--tool claude`) |
| `prompt.md` | Prompt template for Amp |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd/` | Skill for generating PRDs (works with Amp and Claude Code) |
| `skills/ralph/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Amp or Claude Code) with clean context. The only memory between iterations is:
- **Crow Memory MCP** entries tagged `project:<branchName>` (one per completed story, linked `depends-on` to the previous story — queryable via `recall_by_tag`, `hybrid_recall`, `get_related_memories`)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# List Crow Memory entries for the current project (via Claude Code or any MCP client)
# mcp__crow-memory__recall_by_tag tags=["project:<branchName>"] top_k=20
#
# Get details for a specific memory
# mcp__crow-memory__get_memory vector_id=<uuid>
#
# Walk the story graph
# mcp__crow-memory__get_related_memories vector_id=<uuid>
```

## Customizing the Prompt

After copying `prompt.md` (for Amp) or `CLAUDE.md` (for Claude Code) to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

When a new iteration detects that `prd.json` has a different `branchName` than the most-recent Crow Memory entries, the agent:

1. Calls `mcp__crow-memory__archive_memory` on every memory tagged with the previous `project:*` (reversible — use `restore_memory` to undo).
2. Copies the old `prd.json` + `progress.txt` to `archive/YYYY-MM-DD-<previous-branchName>/` for human inspection.
3. Resets `progress.txt` with a fresh header.

This replaces the git-based archive flow in the upstream ralph.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
