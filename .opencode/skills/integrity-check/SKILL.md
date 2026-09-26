---
name: integrity-check
description: 'Fast LLM-free integrity check — SHA256 for all 38 agent pairs (live vs deploy), counters (38 agents, 10 models in use, routing 26/10 across opencode.json + ARCHITECTURE.md + workflow-enforcement.ts), every frontmatter model: key validated for format (provider/key) and existence in opencode.json provider models. PASS/FAIL report, exit 0 all pass, exit 3 failures.'
---

# Integrity Check

Fast, deterministic, LLM-free integrity check of the whole agent orchestration
config. Pure scripting: hashes, counters, key lookups. Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Quick health check before/after any config operation (model migration, sync, plugin update)
- CI-like gate: exit 0 = healthy, exit 3 = integrity failures
- Verifying that every agent's `model:` actually exists in the provider config

## When NOT to use

- Deep semantic consistency (routing tables vs pipelines vs docs prose) — use the
  `consistency-checker` agent (11 checks, LLM-based)
- Provider config schema audit (limits/modalities/variants) — use `provider-config-audit`
- Fixing drift — use `config-sync` (this skill only REPORTS)

## Checks performed

1. **Counts**: live `agents/*.md` == 38, deploy `agents/*.md` == 38, name sets equal
2. **Pairs**: SHA256 identical for all 38 live↔deploy agent pairs
3. **Model key format**: every frontmatter `model:` matches `provider/model-key`
   (non-empty provider segment, non-empty remainder; split on FIRST `/`)
4. **Model existence**: every `model:` resolves in live opencode.json
   `provider.<provider>.models.<model-key>`
5. **Models-in-use counter**: number of DISTINCT `model:` values across the 38 live
   frontmatters == 10; cross-checks: MCP_SETUP.md (root) Models Distribution data-row
   count == 10 AND Summary row `| Models | 10 |` == 10
6. **Routing counters** (expected 26 orchestrator / 10 plankestrator), from 3 sources each:
   - live opencode.json `agent.<primary>.permission.task` — count of `"allow"` values (excl. `"*"`)
   - ARCHITECTURE.md (root) — `### orchestrator Whitelist (26 agents)` / `### plankestrator
     Whitelist (10 agents)` header numbers AND actual table row counts under each header
   - live workflow-enforcement.ts — quoted entries in `ROUTING_TABLES.orchestrator` /
     `.plankestrator` arrays (WARN-only if the anchor cannot be parsed)
7. **opencode.json validity**: parses as JSON (failure → FAIL finding, not env error);
   live↔deploy opencode.json SHA256 equality reported as part of pairs (FAIL on drift)

## Usage

```powershell
& ".opencode\skills\integrity-check\scripts\check.ps1"
& ".opencode\skills\integrity-check\scripts\check.ps1" -Json
    & ".opencode\skills\integrity-check\scripts\check.ps1" -ExpectedAgents 38 -ExpectedModels 10 -ExpectedOrch 26 -ExpectedPlan 10
```

### POSIX mirror

```bash
python .opencode/skills/integrity-check/scripts/check.py [--json]
```

## Output format

```
STATUS:CHECK_START
COUNT:agents_live=38 agents_deploy=38 expected=38 -> PASS
PAIR:worker -> OK
PAIR:utility live=<sha8> deploy=<sha8> -> FAIL
FORMAT:worker model=bifrost-litellm/stepfun/step-5-preview -> PASS
EXISTS:worker bifrost-litellm/stepfun/step-5-preview -> PASS
COUNT:models_used=10 expected=10 -> PASS
COUNT:routing_orchestrator json=26 arch_header=26 arch_rows=26 plugin=26 expected=26 -> PASS
COUNT:routing_plankestrator json=10 arch_header=10 arch_rows=10 plugin=10 expected=10 -> PASS
WARN:routing plugin anchor not parsed (skipped plugin source)
SUMMARY:checks=<n> pass=<n> fail=<n> warn=<n>
STATUS:ALL_PASS   |   STATUS:FAILURES fail=<n>
```

(`-Json`: `{checks:[{id,target,status,detail}],summary:{total,pass,fail,warn}}`, exit code unchanged.)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | All checks PASS (WARNs allowed) |
| 2 | Usage/environment error (live config dir, repo root or opencode.json FILE missing, unreadable agents dir) |
| 3 | One or more FAIL findings |

## Hard rules

- STRICTLY READ-ONLY: never writes, copies, fixes or deletes anything
- No LLM, no network — deterministic local checks only (fast gate)
- Never edit user-level skills
- Expected counters are parameters (defaults 38/11/26/10) — after a legitimate
  architecture change, update the defaults in BOTH scripts and this file together
- WARN (e.g. unparsable plugin anchor) never changes the exit code; only FAIL does
