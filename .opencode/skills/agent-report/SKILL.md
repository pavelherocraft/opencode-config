---
name: agent-report
description: 'Fast LLM-free fleet report — per-agent table (frontmatter model, Model Roles role/tier, mode, flattened permissions, routing membership orch/plan/both/none) plus model-distribution and role-distribution summaries. Sources: live (default) or deploy agent files, root ARCHITECTURE.md (Model Roles + whitelists), live opencode.json (routing cross-check, WARN on mismatch). Formats: aligned table (default), markdown, JSON. Strictly read-only, runs in seconds. Exit 0 report generated, exit 2 usage/environment error.'
---

# Agent Report

Deterministic, LLM-free state report of the agent fleet: every agent with its
model, Model Roles role/tier, mode, flattened frontmatter permissions and
routing-whitelist membership, plus model- and role-distribution summaries.
Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- "What does the fleet look like NOW" overview before/after migrations
- Model load review: how many agents run on each model (cost/tier balance)
- Role and tier audit input (which agents are top/mid/low)
- Routing overview: which subagents each primary agent may call
- Embeddable report for plans/PRs/docs (-Format markdown / -Format json)

## When NOT to use

- Gated validation (pair hashes, counters vs expected) — use `integrity-check`
- Model key validity/suggestions — use `model-key-validate`
- Changing a model — use `agent-model-migrate`
- Pipeline structure diagrams — use `pipeline-visualize`
- Packaging deploy-package — use `deploy-package-build`

## Data sources

| Field | Source (authority order) |
|-------|--------------------------|
| model, mode, permissions | agent frontmatter — live `~/.config/opencode/agents/*.md` (default) or `deploy-package/agents` (`-Source deploy`) |
| role, tier | root `ARCHITECTURE.md` → `## Model Roles` table |
| routing | root `ARCHITECTURE.md` → `### orchestrator Whitelist` / `### plankestrator Whitelist` table rows |
| routing cross-check | `opencode.json` (`-Config`, default live) → `agent.<primary>.permission.task` allow-keys (mismatch → WARN, never fatal) |

Authority rule: the displayed `model` is ALWAYS the frontmatter value
(Permission Authority — opencode.json carries no model field). The Model Roles
`model` column is only COMPARED against frontmatter (`WARN:ROLE_MODEL_DRIFT`),
never displayed as truth. Skills read the ROOT ARCHITECTURE.md (known
pre-existing drift: the live copy under ~/.config/opencode may differ).

## Report columns

`agent | model | role | tier | mode | routing | permissions`

- routing: `orch` / `plan` / `both` / `-` (in neither whitelist, e.g. scout)
- permissions: frontmatter `permission:` block flattened to dot-path pairs in
  document order: `edit=allow; bash.*=allow; bash.git commit*=deny;
  bash.git push*=deny; task.*=deny; task.scout=allow`. Table format truncates to 6 pairs + `+N`;
  markdown shows all; JSON keeps them as an object.

## Summaries

- `MODEL_DIST` — per distinct frontmatter model (sorted by count desc, then
  model asc): count + agent names
- `ROLE_DIST` — per Model Roles role (table order): tier, count + agent names
- `SUMMARY` — agents, shown, distinct models, roles, routing counts
  (orch/plan/both/none), unmapped agents, warnings

## Workflow

1. Resolve flags/paths; invalid flags or combinations → exit 2
2. Read ARCHITECTURE.md; require anchors `## Model Roles` and BOTH whitelist
   headers (missing → exit 2)
3. Scan agents dir (`*.md`); parse each frontmatter (model, mode, permission
   flat); missing/empty dir → exit 2; frontmatter without `model:` →
   `WARN:FM_NO_MODEL` (row still reported with `model=<missing>`)
4. Join: role map (agent → role/tier; absent → `WARN:ROLE_UNMAPPED`,
   role=`<unmapped>`, tier=`?`); Model Roles model vs frontmatter model
   (byte-compare, mismatch → `WARN:ROLE_MODEL_DRIFT`); whitelist membership;
   opencode.json task-allow cross-check (mismatch → `WARN:ROUTING_MISMATCH`;
   file missing/unparsable → `WARN:CROSSCHECK_SKIPPED`)
5. Apply filters (`-Agent` exact — not found → exit 2; `-Role` exact;
   `-Model` case-insensitive substring)
6. Compute distributions on the FULL fleet; render body per `-Format`;
   emit tokens; exit 0

## Usage

```powershell
& ".opencode\skills\agent-report\scripts\report.ps1"
& ".opencode\skills\agent-report\scripts\report.ps1" -Format markdown
& ".opencode\skills\agent-report\scripts\report.ps1" -Format json
& ".opencode\skills\agent-report\scripts\report.ps1" -Source deploy
& ".opencode\skills\agent-report\scripts\report.ps1" -Role executor-cheap
& ".opencode\skills\agent-report\scripts\report.ps1" -Model "GLM-5.3"
& ".opencode\skills\agent-report\scripts\report.ps1" -Agent worker
```

### POSIX mirror

```bash
python .opencode/skills/agent-report/scripts/report.py [--source live|deploy] [--format table|markdown|json] [--agent NAME] [--role ROLE] [--model SUBSTR]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Source live\|deploy` | agents dir: live (default) or `deploy-package/agents` |
| `-Format table\|markdown\|json` | report body format (default `table`) |
| `-Agent <name>` | single-agent report (exact, token-equal; not found → exit 2) |
| `-Role <role>` | filter by Model Roles role (exact) |
| `-Model <substr>` | filter by model substring (case-insensitive) |
| `-AgentsDir <dir>` | explicit agents dir (overrides `-Source`; relative → repo root) |
| `-Arch <path>` | ARCHITECTURE.md (default: repo root) |
| `-Config <path>` | opencode.json for routing cross-check (default: live; missing → WARN skip) |

## Gates

| Gate | Effect |
|------|--------|
| `-Agent` combined with `-Role`/`-Model` | BLOCK (exit 2) |
| `-Source deploy` combined with `-AgentsDir` | BLOCK (exit 2) |
| Agents dir / ARCHITECTURE.md missing, agents dir empty | BLOCK (exit 2) |
| Anchors `## Model Roles` / whitelist headers not found | BLOCK (exit 2) |
| `-Agent <name>` not found among scanned agents | BLOCK (exit 2) |
| Role/model/routing drift, unmapped agents, cross-check skip | WARN (exit code unchanged) |

## Output format

table/markdown modes emit token lines + the rendered body:

```
STATUS:REPORT_START source=live agents=37 arch=ARCHITECTURE.md
WARN:ROLE_UNMAPPED agent=<name> (not in Model Roles table)
WARN:ROLE_MODEL_DRIFT agent=plan-bug arch=<model> frontmatter=<model>
WARN:ROUTING_MISMATCH primary=orchestrator arch_only=[...] json_only=[...]
WARN:CROSSCHECK_SKIPPED reason=<opencode.json missing/unparsable>
<report body: aligned table or markdown sections>
MODEL_DIST:bifrost-litellm/MiniMax-M3 count=10 agents=execute-bug,git-commit,...
ROLE_DIST:executor-cheap tier=low count=10 agents=execute-bug,...
SUMMARY:agents=37 shown=37 models=10 roles=18 orch=24 plan=9 both=1 none=3 unmapped=0 warn=2
STATUS:SUCCESS
```

json mode emits ONLY the JSON document (no token lines):
`{generated_utc, source, agents_dir, agents:[{name,model,role,tier,mode,routing,permissions:{...}}], model_dist:[{model,count,agents}], role_dist:[{role,tier,count,agents}], routing:{orchestrator:[],plankestrator:[],both:[],none:[]}, warnings:[], summary:{...}}`

Routing counts in SUMMARY are exclusive memberships (orch = in the orchestrator
whitelist only, etc.) so orch+plan+both+none == agents.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Report generated (WARNs allowed — a report never fails on drift) |
| 2 | Usage/environment error (bad flags/combination, missing dirs/files, anchors absent, `-Agent` not found, empty agents dir) |

This skill has NO exit 3: it reports state, it does not gate. Gating checks
live in `integrity-check` / `deploy-package-build`.

## Hard rules

- STRICTLY READ-ONLY: never writes, fixes or deletes anything
- No LLM, no network — deterministic local parsing only (seconds)
- Frontmatter `model:` is the ONLY model authority; ARCHITECTURE.md model
  column is compared, never displayed as truth
- Model/agent names are byte-exact (spaces and parentheses: `GLM-5.3 (res)`,
  `Kimi K3`); always `[regex]::Escape()` / `re.escape()` before pattern use
- Token-exact agent-name matching for `-Agent` and whitelist joins (no fuzzy)
- No hardcoded agent count — the agents dir is scanned as-is (works
  mid-migration when the count is 37 or 38)
- Distributions are computed on the FULL fleet; filters affect the body only
  (`shown=` vs `agents=` in SUMMARY)
- WARN never changes the exit code
- PS and PY mirrors produce identical tokens/columns (output parity)
- Never edit user-level skills
