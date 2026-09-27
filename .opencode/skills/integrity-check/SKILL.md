---
name: integrity-check
description: 'Fast LLM-free integrity check of the live↔repo orchestration config — 5 sync pairs SHA256 (drift report with config-sync --save hint), JSON validity (live + repo opencode.json), agent counts (derived: live == repo == opencode.json entries), routing counts (derived cross-check: plugin ROUTING_TABLES vs task-allowlists vs ARCHITECTURE whitelists), every frontmatter model: validated for format and existence in provider models. PASS/FAIL report, exit 0 all pass, exit 3 failures.'
---

# Integrity Check

Fast, deterministic, LLM-free integrity check of the agent orchestration
config. Pure scripting: hashes, counters, key lookups. Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Quick health check before/after any config operation (model migration, sync, plugin update)
- CI-like gate: exit 0 = healthy, exit 3 = integrity failures
- Verifying that every agent's `model:` actually exists in the provider config

## When NOT to use

- Deep semantic consistency (routing vs pipelines vs docs prose) — use the
  `consistency-checker` agent (follows ARCHITECTURE.md)
- Provider config schema audit (limits/modalities/variants) — use `provider-config-audit`
- Fixing drift — use `config-sync --save` (this skill only REPORTS)

## Checks performed (no hardcoded expectations — counters are derived)

1. **Sync-pair drift (5 pairs)**: SHA256 identical for every member of the 5
   live↔repo pairs — `agents/*.md`, `opencode.json`,
   `plugins/workflow-enforcement.ts`, `skills/git-commit/*`,
   `AGENTS.md ↔ AGENTS.global.md`. Drift → `DRIFT:` lines with the hint
   `config-sync --save`
2. **JSON validity**: live opencode.json AND repo opencode.json parse (C5)
3. **Agent counts (derived)**: live `agents/*.md` count == repo `agents/*.md`
   count == opencode.json `agent` entries count; name sets equal (C2)
4. **Routing counts (derived cross-check)**: for each primary —
   live workflow-enforcement.ts `ROUTING_TABLES.<primary>` entry count ==
   live opencode.json `agent.<primary>.permission.task` allow-count ==
   ARCHITECTURE.md whitelist header number == whitelist table rows (C1; WARN-only
   if an anchor cannot be parsed)
5. **Model key format + existence**: every frontmatter `model:` matches
   `provider/model-key` (split on FIRST `/`) and resolves in live opencode.json
   `provider.<provider>.models.<model-key>` (C4)

## Usage

```powershell
& ".opencode\skills\integrity-check\scripts\check.ps1"
& ".opencode\skills\integrity-check\scripts\check.ps1" -Json
```

### POSIX mirror

```bash
python .opencode/skills/integrity-check/scripts/check.py [--json]
```

## Output format

```
STATUS:CHECK_START
JSON:opencode.json live parse ok -> PASS
PAIR:agents/worker.md -> OK
DRIFT:agents/utility.md live=2610999D repo=DBFBD96F (use: config-sync --save) -> FAIL
COUNT:agents_live=40 agents_repo=40 opencode_json=40 (derived, no hardcoded expectation) -> PASS
COUNT:routing_orchestrator json=28 plugin=28 arch_header=28 arch_rows=28 (derived cross-check) -> PASS
FORMAT:worker model=bifrost-litellm/stepfun/step-5-preview -> PASS
EXISTS:worker bifrost-litellm/stepfun/step-5-preview -> PASS
SUMMARY:checks=<n> pass=<n> fail=<n> warn=<n>
STATUS:ALL_PASS   |   STATUS:FAILURES fail=<n>
```

(`-Json`: `{checks:[{id,target,status,detail}],summary:{total,pass,fail,warn}}`, exit code unchanged.)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | All checks PASS (WARNs allowed) |
| 2 | Usage/environment error (live config dir, repo root or live opencode.json missing, unreadable agents dir) |
| 3 | One or more FAIL findings (sync-pair drift included) |

## Hard rules

- STRICTLY READ-ONLY: never writes, copies, fixes or deletes anything
- No LLM, no network — deterministic local checks only (fast gate)
- Never edit user-level skills
- Expected counters are NOT hardcoded — counts and routing sizes are derived
  from the scanned facts and cross-checked against each other (works
  mid-migration at any fleet size)
- WARN (e.g. unparsable plugin/whitelist anchor) never changes the exit code; only FAIL does
