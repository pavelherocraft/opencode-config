---
name: agent-model-migrate
description: 'Migrate ONE agent to a new model (full key, e.g. bifrost-litellm/MiniMax-M3) — updates live+deploy frontmatter, ARCHITECTURE.md x3 (Subagent Models + Model Roles), MCP_SETUP.md x2 (Models Distribution + Subagents Full Table + Summary row), validates the key against opencode.json provider models, SHA256-verifies all mirrors, optional conventional commit + push.'
---

# Agent Model Migrate

Migrate a single agent to a new model. Updates ALL 7 synchronized places in one
all-or-nothing operation (ARCHITECTURE.md §Model Roles rule 2: "Смена модели =
4 синхронных места" — frontmatter, Subagent Models, Model Roles, MCP_SETUP
Distribution — plus the Full Table and Summary mirrors).

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User asks to change/switch/migrate the model of ONE agent
- User says "переведи <agent> на <model>", "migrate <agent> to <model>"
- Prewalk re-balancing of a single planner/executor pair member

## When NOT to use

- Bulk/role-wide migration of many agents (manual operation per ARCHITECTURE §Model Roles)
- Adding/updating provider models in opencode.json (use `bifrost-config-apply`)
- Auditing provider config (use `provider-config-audit`); discovering models (use `model-discovery`)
- Migrating `orchestrator` / `plankestrator` (primary agents — BLOCKED; their model is
  documented in §Identity Lock Mechanism item 5 and §Model Roles `primary` row — manual edit)
- Mirrors are out of sync (run `config-sync -Plan` first; this skill BLOCKs on drifted mirrors)

## Workflow

1. **Validate inputs**: agent file exists (live + deploy); model key format `provider/model-key`;
   provider is `bifrost-litellm` (others BLOCK); model key exists in live
   `opencode.json` → `provider.<provider>.models.<model-key>`
2. **Pre-gate mirrors**: live FM == deploy FM (SHA256); ARCHITECTURE.md x3 identical;
   MCP_SETUP.md x2 identical. Any drift → BLOCK (run `config-sync` first)
3. **Plan** (default / `-PlanOnly`): compute ALL edits in memory, print `PLAN:` lines
   for the 7 targets (old → new per file), write nothing
4. **Apply** (`-Apply`): two-phase all-or-nothing write:
   - frontmatter `model:` line — live + deploy (2 files)
   - ARCHITECTURE.md x3: Subagent Models row + Model Roles (remove agent from old
     role row, append to the role row with the new model; `-Role` required when the
     new model maps to 0 or >1 role rows; `-Role`+`-Tier` create a new role row)
   - MCP_SETUP.md x2: Models Distribution (old row count-1 / remove agent, new row
     +1 or created; count 0 → row deleted) + Subagents Full Table Model cell +
     Summary `| Models | N | bifrost-litellm (...) |` row regenerated from Distribution
5. **Verify**: opencode.json still parses; SHA256 — live FM == deploy FM,
   ARCHITECTURE x3 identical, MCP_SETUP x2 identical
6. **Commit** (optional `-Commit`, push `-Push`): conventional commit of the 6 repo
   files (live files are outside git): `refactor(models): <agent> <old> -> <new>`
7. **Remind** (always printed): CHANGELOG.md `[Unreleased]` entry is a MANUAL LLM
   task; the new model takes effect only in a NEW opencode session

## Usage

### Plan only (dry-run, default)

```powershell
& ".opencode\skills\agent-model-migrate\scripts\migrate.ps1" -Agent "utility" -Model "bifrost-litellm/qwen3.8-max" -PlanOnly
```

Output: `PLAN:/WARN:/ERROR:` lines, exit 0

### Apply

```powershell
& ".opencode\skills\agent-model-migrate\scripts\migrate.ps1" -Agent "utility" -Model "bifrost-litellm/qwen3.8-max" -Apply
```

### Apply + role disambiguation / new role

```powershell
# new model appears in MULTIPLE Model Roles rows -> pick one:
& ".opencode\skills\agent-model-migrate\scripts\migrate.ps1" -Agent "bugfix" -Model "bifrost-litellm/QWEN3.7-plus" -Apply -Role "review-lite"
# new model has NO role row -> create it:
& ".opencode\skills\agent-model-migrate\scripts\migrate.ps1" -Agent "summarizer" -Model "bifrost-litellm/Kimi K3-256K" -Apply -Role "summarize-big" -Tier "mid"
```

### Apply + commit + push

```powershell
& ".opencode\skills\agent-model-migrate\scripts\migrate.ps1" -Agent "utility" -Model "bifrost-litellm/qwen3.8-max" -Apply -Commit -Push
```

### POSIX mirror

```bash
python .opencode/skills/agent-model-migrate/scripts/migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --plan-only
python .opencode/skills/agent-model-migrate/scripts/migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --apply [--role R --tier T] [--commit] [--push]
```

## Update targets (7 places)

| # | Target | What changes |
|---|--------|--------------|
| 1 | `~/.config/opencode/agents/<agent>.md` | frontmatter `model:` line |
| 2 | `deploy-package/agents/<agent>.md` | frontmatter `model:` line |
| 3-5 | `ARCHITECTURE.md` (root, opencode-config, deploy project-files) | Subagent Models row + Model Roles agent move |
| 6-7 | `MCP_SETUP.md` (root, deploy project-files) | Distribution row(s) + Full Table Model cell + Summary Models row |

## Gates

| Gate | Effect |
|------|--------|
| Agent file missing (live or deploy) / unknown flags | BLOCK (exit 2) |
| Model key malformed (no `/`, empty parts) | BLOCK (exit 2) |
| Agent is `orchestrator` or `plankestrator` (primary) | BLOCK (exit 3) |
| Provider is not `bifrost-litellm` | BLOCK (exit 3) |
| Model key not found in live opencode.json provider models | BLOCK (exit 3) |
| Live opencode.json invalid JSON | BLOCK (exit 3) |
| Mirrors drifted (FM pair, ARCHITECTURE x3, MCP_SETUP x2) | BLOCK (exit 3; WARN in PlanOnly) |
| New model has no Model Roles row and `-Role`/`-Tier` not given | BLOCK (exit 3) |
| New model has >1 Model Roles rows and `-Role` not given | BLOCK (exit 3) |
| Any text anchor not found / not unique (table drift) | BLOCK (exit 3, zero writes) |
| New model == current model | NO_CHANGES (exit 0) |
| SHA256 mismatch after apply | BLOCK (exit 3) |
| git identity missing / commit / push failure (with -Commit/-Push) | BLOCK (exit 3) |

Non-blocking warnings: prewalk tier inversion (planner tier < executor tier for the
pairs plan-bug→execute-bug, dev-planner→dev-professor, docs-planner→docs-writer),
role row left with zero agents, restart required, CHANGELOG manual entry.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, plan-only, or no changes |
| 2 | Usage/environment error (missing args, agent files, malformed key, repo/live not found) |
| 3 | Gate block (see Gates; includes any anchor/verify/git failure — no partial writes) |

## Hard rules

- Two-phase all-or-nothing: ANY failed anchor/gate → ZERO files written
- Never touch opencode.json content (read-only validation only)
- Never migrate primary agents (orchestrator/plankestrator) — manual doc operation
- Never edit user-level skills or live doc copies outside the 7 targets
- Never rewrite whole tables — only the computed cells/rows (byte-preserving elsewhere)
- Never commit without explicit `-Commit`; never push without explicit `-Push`
- Never force a git identity — use the configured `user.name`/`user.email`
- Regex-escape all model/agent names (models contain `( )`, `.`, `/`, spaces)
- Agent-name matching is token-exact (never substring: `orchestrator` ⊂ `orchestrator-identity-probe`)
- Preserve encoding (UTF-8, BOM-state) and line endings (CRLF/LF) byte-for-byte
- CHANGELOG.md entry and session restart are MANUAL follow-ups (printed as WARN)
