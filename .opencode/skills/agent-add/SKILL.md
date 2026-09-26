---
name: agent-add
description: 'Add a NEW subagent end-to-end — creates live+deploy agent .md (frontmatter from readonly/standard preset or -PermTemplate), inserts opencode.json agent section + primary task allow, appends to ROUTING_TABLES (plugin x3) and OPENCODE_ROUTING_TABLE (primary prompt x2), updates whitelist tables and counters in ARCHITECTURE.md x3 / AGENTS.md x3 / PLUGIN.md x3 / MCP_SETUP.md x2 (whitelist 26->27 or 10->11, subagents 36->37, total 38->39), adds Subagent Models + Model Roles + Distribution + Full Table rows, SHA256-verifies all mirrors, optional conventional commit + push.'
---

# Agent Add

Add ONE new subagent to the dual-primary-agent system. Updates ALL synchronized
places in one all-or-nothing operation: agent files (live + deploy),
opencode.json (agent section + primary task permission), routing tables
(plugin x3, primary prompt x2), whitelist tables and every derived counter
(ARCHITECTURE.md x3, AGENTS.md x3, PLUGIN.md x3, MCP_SETUP.md x2), model
tables (Subagent Models, Model Roles, Models Distribution, Full Table).

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User asks to add/create/introduce a NEW subagent to the orchestrator or
  plankestrator whitelist
- A planned feature needs a new pipeline participant (e.g. a new reviewer type)
- Always AFTER `backup-snapshot` (recommended) and `config-sync -Plan` (mirrors clean)

## When NOT to use

- Changing the model of an EXISTING agent (use `agent-model-migrate`)
- Adding provider models to opencode.json (use `bifrost-config-apply`)
- Renaming or deleting agents (manual operation — this skill never deletes)
- Adding a PRIMARY agent (orchestrator/plankestrator are manual doc operations — BLOCKED)
- Mirrors are out of sync (run `config-sync -Apply` first; this skill BLOCKs on drift)

## Workflow

1. **Validate inputs**: name format `^[a-z][a-z0-9-]*$`; name is NOT
   orchestrator/plankestrator; agent does not exist anywhere yet (live/deploy
   files, opencode.json agent section, routing tables); model key format +
   existence in live opencode.json; provider is `bifrost-litellm`
2. **Pre-gate mirrors**: plugin .ts x3 identical; opencode.json live == deploy;
   ARCHITECTURE.md x3 identical; MCP_SETUP.md x2 identical; AGENTS.md x3
   identical; `<primary>.md` live == deploy. PLUGIN.md x3 are NOT required
   identical (historical drift) — anchors are applied per-copy. Any drift in
   gated groups -> BLOCK (run `config-sync` first)
3. **Counter cross-check**: parse the current whitelist count from ALL 10
   sources (plugin array, OPENCODE_ROUTING_TABLE, json task allows, ARCH/AGENTS/
   PLUGIN/MCP headers + table rows, MCP Summary) and the global counters
   (Grand Total, Note, Kontrol summy, Agent Count, Agent Files lists). ALL
   values in a group must agree; any disagreement -> BLOCK with DIFF: lines
4. **Plan** (default / `-PlanOnly`): compute ALL edits in memory, print `PLAN:`
   lines per target group, write nothing
5. **Apply** (`-Apply`): two-phase all-or-nothing write of ~19 files (see
   Update targets); any failed anchor -> ZERO writes
6. **Verify**: opencode.json (live+deploy) still parses; SHA256 — new agent
   pair identical, plugin x3 identical, ARCH x3, MCP x2, AGENTS x3, primary
   pair identical; re-parse every counter == old+1; routing arrays contain the
   new name exactly once
7. **Commit** (optional `-Commit`, push `-Push`): conventional commit of the
   repo files (live files are outside git):
   `feat(agents): add <name> (<model>, <primary> whitelist)`
8. **Remind** (always printed WARN): session restart required; manual
   follow-ups (CHANGELOG entry, consistency-checker.md counts, verify.ps1
   requiredAgents, deploy README/DEPLOYMENT_GUIDE counts, integrity-check
   defaults, live AGENTS.md via config-sync)

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

## Update targets (10 groups, ~19 files)

| # | Target | What changes |
|---|--------|--------------|
| 1 | `~/.config/opencode/agents/<name>.md` (NEW) | generated frontmatter + body |
| 2 | `deploy-package/agents/<name>.md` (NEW) | byte-identical copy of #1 |
| 3 | `~/.config/opencode/opencode.json` | new `agent.<name>` section (inserted as FIRST entry after `"agent": {`) + `"<name>": "allow"` in `<primary>` task block |
| 4 | `deploy-package/opencode.json` | same edits as #3 (byte-identical result) |
| 5 | plugin `workflow-enforcement.ts` (live + project `plugins/` + `deploy-package/plugins/`, x3) | append `"<name>"` to `ROUTING_TABLES.<primary>` |
| 6 | `agents/<primary>.md` (live + deploy, x2) | append `"<name>"` to the `OPENCODE_ROUTING_TABLE = [...]` line |
| 7 | `ARCHITECTURE.md` (root, opencode-config, deploy project-files, x3) | whitelist header + numbered row; Agent Count Summary row + Grand Total; Note counters; Subagent Models row; Model Roles agent add (+ intro counter); Kontrol summy counters |
| 8 | `AGENTS.md` (root, opencode-config, deploy project-files, x3) | whitelist header + row (unnumbered); Model Roles prose counter |
| 9 | `PLUGIN.md` (root, opencode-config, deploy project-files, x3) | whitelist header + row (unnumbered); `Routing Table Implementation` TS code block array |
| 10 | `MCP_SETUP.md` (root, deploy project-files, x2) | Agent Count (Subagents/Total); `vse N subagents` prose; Task Whitelist header + comma list (of -Primary); §6 whitelist header + row; Routing Tables in Plugin code block; Models Distribution row; Subagents Full Table row; Agent Files (N total) + Subagents (N) + alphabetical list; Agent Files List (N files) + tree; Summary (Subagents, Routing tables) |

Live files (outside git): #1, #3, live plugin, live `<primary>.md`. Live
`AGENTS.md` is NOT touched — run `config-sync -Apply -Group agents-md` afterwards.

## Gates

| Gate | Effect |
|------|--------|
| Missing required param / unknown flags / `-Permissions` + `-PermTemplate` together / `-Push` without `-Commit` / bad `-Tier` | BLOCK (exit 2) |
| Name malformed (not `^[a-z][a-z0-9-]*$`) or is a primary agent | BLOCK (exit 2) |
| Agent already exists (live/deploy file, opencode.json key, any routing table) | BLOCK (exit 3) |
| Model key malformed (no `/`, empty parts) | BLOCK (exit 2) |
| Provider is not `bifrost-litellm` / key not in provider models | BLOCK (exit 3) |
| Live opencode.json invalid JSON | BLOCK (exit 3) |
| Mirrors drifted (plugin x3, json pair, ARCH x3, MCP x2, AGENTS x3, primary pair) | BLOCK (exit 3; WARN in PlanOnly) |
| Counter cross-check disagreement between sources | BLOCK (exit 3) with DIFF: lines |
| New model has no Model Roles row and `-Role`/`-Tier` not given | BLOCK (exit 3) |
| New model has >1 Model Roles rows and `-Role` not given | BLOCK (exit 3) |
| Any text anchor not found / not unique in ANY copy | BLOCK (exit 3, zero writes) |
| `-Description` contains `": "` (YAML trap) | auto-wrap in single quotes + WARN (not a block) |
| SHA256 mismatch or JSON parse failure after apply | BLOCK (exit 3) |
| git identity missing / commit / push failure | BLOCK (exit 3) |

Non-blocking WARNs: stub body (no -BodyFile); live AGENTS.md needs config-sync;
restart required; CHANGELOG manual entry; consistency-checker.md counts manual;
verify.ps1 requiredAgents manual; deploy README/DEPLOYMENT_GUIDE counts manual;
integrity-check defaults (38/26/10) manual; SEVERITY_AGENTS / CONTEXT_FILE_AGENTS
manual (only when the new agent is a reviewer); MCP_SETUP unity-note prose manual;
tree list pre-existing drift (docs-planner missing) — informational.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, plan-only, or no changes |
| 2 | Usage/environment error (missing args, malformed name/key, repo/live not found) |
| 3 | Gate block (see Gates; includes any anchor/verify/git failure — no partial writes) |

## Hard rules

- Two-phase all-or-nothing: ANY failed anchor/gate -> ZERO files written
- Never create primary agents; never rename/delete anything
- Counter increments are PARSED from anchors (+1), never hardcoded (38->39 today,
  38->39 tomorrow)
- Counter cross-check is fail-closed: sources disagree -> BLOCK, never guess
- Never rewrite whole tables — only computed cells/rows (byte-preserving elsewhere)
- Regex-escape all names/models (models contain `( )`, `.`, `/`, spaces)
- Token-exact agent matching everywhere (never substring)
- Preserve encoding (UTF-8, BOM-state) and line endings (CRLF/LF) byte-for-byte;
  NEW agent .md files are written LF, UTF-8 without BOM, identical bytes live+deploy
- opencode.json edits are TEXT-anchor based (byte-preserving), JSON parse used
  for validation only — never re-serialize the whole file
- Never commit without explicit `-Commit`; never push without explicit `-Push`
- Never edit user-level skills or files outside the Update targets
- CHANGELOG.md, consistency-checker.md and restart are MANUAL follow-ups (WARN)
