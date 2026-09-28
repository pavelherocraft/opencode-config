---
name: agent-add
description: 'Add a NEW subagent end-to-end (live-first) — creates the LIVE agent .md (frontmatter from readonly/standard preset or -PermTemplate), inserts live opencode.json agent section + primary task allow, appends to ROUTING_TABLES (live plugin) and OPENCODE_ROUTING_TABLE (live primary prompt), updates whitelist tables and derived counters in ARCHITECTURE.md (single canonical copy), adds Subagent Models + Model Roles rows, prints the "run config-sync --save before commit" reminder, optional conventional commit + push.'
---

# Agent Add

Add ONE new subagent to the dual-primary-agent system. Edits are made in LIVE
(the runtime source of truth) in one all-or-nothing operation: the agent .md,
live opencode.json (agent section + primary task permission), routing tables
(live plugin ROUTING_TABLES + live primary prompt OPENCODE_ROUTING_TABLE) and
the canonical doc — ARCHITECTURE.md, single root copy (whitelist tables,
derived counters, Subagent Models, Model Roles). The repo mirror is refreshed
afterwards via `config-sync --save`, NOT by this skill.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User asks to add/create/introduce a NEW subagent to the orchestrator or
  plankestrator whitelist
- A planned feature needs a new pipeline participant (e.g. a new reviewer type)
- Always AFTER `backup-snapshot` (recommended first step)

## When NOT to use

- Changing the model of an EXISTING agent (use `agent-model-migrate`)
- Adding provider models to opencode.json (use `bifrost-config-apply`)
- Renaming or deleting agents (manual operation — this skill never deletes)
- Adding a PRIMARY agent (orchestrator/plankestrator are manual doc operations — BLOCKED)

## Workflow

1. **Validate inputs**: name format `^[a-z][a-z0-9-]*$`; name is NOT
   orchestrator/plankestrator; agent does not exist anywhere yet (live file,
   opencode.json agent section, routing tables); model key format +
   existence in live opencode.json; provider is `bifrost-litellm`
2. **Counter cross-check**: parse the current whitelist count from ALL live
   sources (plugin array, OPENCODE_ROUTING_TABLE, json task allows, ARCH
   header + table rows + agent-count summary) and the global counters
   (Grand Total, Note, Kontrol summy, Model Roles intro). ALL values in a
   group must agree; any disagreement -> BLOCK with DIFF: lines
3. **Plan** (default / `-PlanOnly`): compute ALL edits in memory, print `PLAN:`
   lines per target, write nothing
4. **Apply** (`-Apply`): two-phase all-or-nothing write (see Update targets);
   any failed anchor -> ZERO writes
5. **Verify**: live opencode.json still parses; re-parse every counter == old+1;
   routing arrays contain the new name exactly once
6. **Remind** (always printed WARN): session restart required; manual
   follow-ups (CHANGELOG entry; `config-sync --save` to refresh the repo
   mirror before commit; SEVERITY_AGENTS/CONTEXT_FILE_AGENTS only when the
   new agent is a reviewer)
7. **Commit** (optional `-Commit`, push `-Push`): conventional commit of the
   repo files (live files are outside git; run `config-sync --save` first —
   a WARN lists unrefreshed mirrors):
   `feat(agents): add <name> (<model>, <primary> whitelist)`

## Usage

### Plan only (dry-run, default)

```powershell
& ".opencode\skills\agent-add\scripts\add.ps1" -Agent "code-search" -Model "bifrost-litellm/MiniMax-M3" -Description "Fast code search across the repository" -Primary orchestrator -Permissions standard -PlanOnly
```

Output: `PLAN:/WARN:/DIFF:` lines, exit 0

### Apply (preset permissions)

```powershell
& ".opencode\skills\agent-add\scripts\add.ps1" -Agent "code-search" -Model "bifrost-litellm/MiniMax-M3" -Description "Fast code search across the repository" -Primary orchestrator -Permissions standard -Apply
```

### Apply (copy permissions from an existing agent + prompt body from file)

```powershell
& ".opencode\skills\agent-add\scripts\add.ps1" -Agent "note-taker" -Model "bifrost-litellm/Kimi K3" -Description "Session notes writer" -Primary plankestrator -PermTemplate mcp-read -TaskAllow "view-image" -BodyFile ".\prompts\note-taker.md" -Role "summarize-big" -Apply
```

### Apply + commit + push

```powershell
& ".opencode\skills\agent-add\scripts\add.ps1" -Agent "code-search" -Model "bifrost-litellm/MiniMax-M3" -Description "Fast code search" -Primary orchestrator -Permissions readonly -Apply -Commit -Push
```

### POSIX mirror

```bash
python .opencode/skills/agent-add/scripts/add.py --agent code-search --model bifrost-litellm/MiniMax-M3 --description "Fast code search" --primary orchestrator --permissions standard --plan-only
python .opencode/skills/agent-add/scripts/add.py --agent code-search --model bifrost-litellm/MiniMax-M3 --description "Fast code search" --primary orchestrator --permissions readonly --apply [--role R --tier T] [--commit] [--push]
```

### Tests (regenerate the two historically broken generators)

```powershell
# PowerShell: ROUTING_TABLES insertion lands in the CORRECT array + frontmatter
# lines stay separate (no "permission block merged into one line")
powershell -File ".opencode\skills\agent-add\scripts\test-add-ps1.ps1"
```

```bash
# Python: same checks + generated frontmatter must parse as YAML (PyYAML when
# available; mixed task-block indentation is asserted structurally too)
python .opencode/skills/agent-add/scripts/test-add-py.py
```

Both suites drive the real functions extracted from the sibling script against
a synthetic `ROUTING_TABLES` fixture with a non-zero prefix AND the live plugin
(read-only regression, T6). Exit 0 = all pass, 1 = failures. No live config is
written.

## Parameters

| Param | Meaning |
|-------|---------|
| `-Agent <name>` | new agent name (file stem), `^[a-z][a-z0-9-]*$` (REQUIRED) |
| `-Model <provider/key>` | full model key, validated against opencode.json (REQUIRED) |
| `-Description <text>` | one-line description -> frontmatter + Role cells (REQUIRED) |
| `-Primary <orchestrator\|plankestrator>` | whitelist to join (REQUIRED) |
| `-Permissions <readonly\|standard>` | permission preset (mutually exclusive with -PermTemplate) |
| `-PermTemplate <agent>` | copy permission blocks from an existing agent |
| `-TaskAllow <a,b>` | extra `task` allowlist entries for the NEW agent (default per preset) |
| `-Role <name>` | Model Roles row (required when the model maps to 0 or >1 role rows) |
| `-Tier <top\|mid\|low>` | with -Role: create a NEW role row |
| `-BodyFile <path>` | prompt body after frontmatter (default: minimal stub + WARN) |
| `-Temperature <d>` | default 0.1 |
| `-PlanOnly` / `-Apply` | dry-run (default) / write |
| `-Commit` / `-Push` | conventional commit / push (push requires commit) |

### Permission presets

| Preset | Modelled after | Permissions | task defaults |
|--------|----------------|-------------|---------------|
| `readonly` | advisor | edit/write/bash/webfetch/patch/todowrite/question deny; read/grep/glob allow; serena read-only (find_symbol, find_referencing_symbols, get_symbols_overview, search_for_pattern); NO unity-mcp | `"*": deny` |
| `standard` | mcp-read | edit/write deny; read allow; bash deny; `unity-mcp.*` allow; serena full (7 tools) | `"*": deny`, `view-image: allow` |

## Update targets (live-first: 4 live targets + repo ARCHITECTURE.md)

| # | Target | What changes |
|---|--------|--------------|
| 1 | `~/.config/opencode/agents/<name>.md` (NEW, LIVE) | generated frontmatter + body |
| 2 | `~/.config/opencode/opencode.json` (LIVE) | new `agent.<name>` section (inserted as FIRST entry after `"agent": {`) + `"<name>": "allow"` in `<primary>` task block |
| 3 | live `plugins/workflow-enforcement.ts` | append `"<name>"` to `ROUTING_TABLES.<primary>` |
| 4 | live `agents/<primary>.md` | append `"<name>"` to the `OPENCODE_ROUTING_TABLE = [...]` line |
| 5 | `ARCHITECTURE.md` (repo root — single canonical copy) | whitelist header + numbered row; Agent Count Summary row + Grand Total; Note counters; Subagent Models row; Model Roles agent add (+ intro counter); Kontrol summy counters |

Repo mirror (agents/, opencode.json, plugins/) — NOT touched here: refresh
with `config-sync --save` (printed reminder).

## Gates

| Gate | Effect |
|------|--------|
| Missing required param / unknown flags / `-Permissions` + `-PermTemplate` together / `-Push` without `-Commit` / bad `-Tier` | BLOCK (exit 2) |
| Name malformed (not `^[a-z][a-z0-9-]*$`) or is a primary agent | BLOCK (exit 2) |
| Agent already exists (live file, opencode.json key, any routing table) | BLOCK (exit 3) |
| Model key malformed (no `/`, empty parts) | BLOCK (exit 2) |
| Provider is not `bifrost-litellm` / key not in provider models | BLOCK (exit 3) |
| Live opencode.json invalid JSON | BLOCK (exit 3) |
| Counter cross-check disagreement between sources | BLOCK (exit 3) with DIFF: lines |
| New model has no Model Roles row and `-Role`/`-Tier` not given | BLOCK (exit 3) |
| New model has >1 Model Roles rows and `-Role` not given | BLOCK (exit 3) |
| Any text anchor not found / not unique | BLOCK (exit 3, zero writes) |
| `-Description` contains `": "` (YAML trap) | auto-wrap in single quotes + WARN (not a block) |
| Counter/JSON re-parse failure after apply | BLOCK (exit 3) |
| git identity missing / commit / push failure | BLOCK (exit 3) |

Non-blocking WARNs: stub body (no -BodyFile); restart required; CHANGELOG
manual entry; `config-sync --save` reminder (repo mirror not refreshed by
this skill); SEVERITY_AGENTS / CONTEXT_FILE_AGENTS manual (only when the new
agent is a reviewer).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, plan-only, or no changes |
| 2 | Usage/environment error (missing args, malformed name/key, repo/live not found) |
| 3 | Gate block (see Gates; includes any anchor/verify/git failure — no partial writes) |

## Hard rules

- Two-phase all-or-nothing: ANY failed anchor/gate -> ZERO files written
- Never create primary agents; never rename/delete anything
- Counter increments are PARSED from anchors (+1), never hardcoded
- Counter cross-check is fail-closed: sources disagree -> BLOCK, never guess
- Never rewrite whole tables — only computed cells/rows (byte-preserving elsewhere)
- Regex-escape all names/models (models contain `( )`, `.`, `/`, spaces)
- Token-exact agent matching everywhere (never substring)
- Preserve encoding (UTF-8, BOM-state) and line endings (CRLF/LF) byte-for-byte;
  NEW agent .md files are written LF, UTF-8 without BOM
- opencode.json edits are TEXT-anchor based (byte-preserving), JSON parse used
  for validation only — never re-serialize the whole file
- Never commit without explicit `-Commit`; never push without explicit `-Push`
- Never edit the repo agents/ mirror directly — live is edited, the mirror is
  refreshed by `config-sync --save`
- Never edit user-level skills or files outside the Update targets
- CHANGELOG.md, `config-sync --save` and restart are MANUAL follow-ups (WARN)
