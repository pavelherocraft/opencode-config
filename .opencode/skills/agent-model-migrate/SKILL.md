---
name: agent-model-migrate
description: 'Migrate ONE agent to a new model (full key, e.g. bifrost-litellm/MiniMax-M3) — edits LIVE frontmatter + ARCHITECTURE.md (Subagent Models + Model Roles), validates the key against live opencode.json provider models, prints the "run config-sync --save before commit" reminder, optional conventional commit + push.'
---

# Agent Model Migrate

Migrate a single agent to a new model. Edits are made in LIVE (the single place
where runtime config changes): the agent's frontmatter `model:` line plus the
canonical doc — ARCHITECTURE.md, single root copy (§Model Roles rule 2: смена
модели = правка таблицы ролей + frontmatter, 2 синхронных места). The repo
mirror is refreshed afterwards via `config-sync --save`, NOT by this skill.

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

## Workflow

1. **Validate inputs**: agent file exists in LIVE; model key format
   `provider/model-key`; provider is `bifrost-litellm` (others BLOCK); model key
   exists in live `opencode.json` → `provider.<provider>.models.<model-key>`
2. **Plan** (default / `-PlanOnly`): compute ALL edits in memory, print `PLAN:`
   lines for the 2 targets (old → new per file), write nothing
3. **Apply** (`-Apply`): two-phase all-or-nothing write:
   - LIVE frontmatter `model:` line (`~/.config/opencode/agents/<agent>.md`)
   - `ARCHITECTURE.md` (repo root, single canonical copy): Subagent Models row +
     Model Roles (remove agent from old role row, append to the role row with
     the new model; `-Role` required when the new model maps to 0 or >1 role
     rows; `-Role`+`-Tier` create a new role row)
4. **Verify**: opencode.json still parses; anchors re-parsed and contain the new
   model for the agent
5. **Remind** (always printed): run `config-sync --save` before the next commit
   (refreshes the repo agents/ mirror); CHANGELOG.md `[Unreleased]` entry is a
   MANUAL LLM task; the new model takes effect only in a NEW opencode session
6. **Commit** (optional `-Commit`, push `-Push`): conventional commit of the
   repo files (live files are outside git; commit AFTER `config-sync --save`):
   `refactor(models): <agent> <old> -> <new>`

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

### POSIX mirror

```bash
python .opencode/skills/agent-model-migrate/scripts/migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --plan-only
python .opencode/skills/agent-model-migrate/scripts/migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --apply [--role R --tier T] [--commit] [--push]
```

## Update targets (2 places + mirror via config-sync)

| # | Target | What changes |
|---|--------|--------------|
| 1 | `~/.config/opencode/agents/<agent>.md` (LIVE) | frontmatter `model:` line |
| 2 | `ARCHITECTURE.md` (repo root — single canonical copy) | Subagent Models row + Model Roles agent move |
| — | `agents/<agent>.md` (repo mirror) | NOT touched here — refresh with `config-sync --save` (printed reminder) |

## Gates

| Gate | Effect |
|------|--------|
| Agent file missing in live / unknown flags | BLOCK (exit 2) |
| Model key malformed (no `/`, empty parts) | BLOCK (exit 2) |
| Agent is `orchestrator` or `plankestrator` (primary) | BLOCK (exit 3) |
| Provider is not `bifrost-litellm` | BLOCK (exit 3) |
| Model key not found in live opencode.json provider models | BLOCK (exit 3) |
| Live opencode.json invalid JSON | BLOCK (exit 3) |
| New model has no Model Roles row and `-Role`/`-Tier` not given | BLOCK (exit 3) |
| New model has >1 Model Roles rows and `-Role` not given | BLOCK (exit 3) |
| Any text anchor not found / not unique (table drift) | BLOCK (exit 3, zero writes) |
| New model == current model | NO_CHANGES (exit 0) |
| Verify failure after apply (anchor/JSON re-parse) | BLOCK (exit 3) |
| git identity missing / commit / push failure (with -Commit/-Push) | BLOCK (exit 3) |

Non-blocking warnings: prewalk tier inversion (planner tier < executor tier for the
pairs plan-bug→execute-bug, dev-planner→dev-professor, docs-planner→docs-writer),
role row left with zero agents, restart required, `config-sync --save` reminder,
CHANGELOG manual entry.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, plan-only, or no changes |
| 2 | Usage/environment error (missing args, agent file, malformed key, repo/live not found) |
| 3 | Gate block (see Gates; includes any anchor/verify/git failure — no partial writes) |

## Hard rules

- Two-phase all-or-nothing: ANY failed anchor/gate → ZERO files written
- Never touch opencode.json content (read-only validation only)
- Never migrate primary agents (orchestrator/plankestrator) — manual doc operation
- Never edit the repo agents/ mirror directly — live is edited, the mirror is
  refreshed by `config-sync --save`
- Never edit user-level skills
- Never rewrite whole tables — only the computed cells/rows (byte-preserving elsewhere)
- Never commit without explicit `-Commit`; never push without explicit `-Push`
- Never force a git identity — use the configured `user.name`/`user.email`
- Regex-escape all model/agent names (models contain `( )`, `.`, `/`, spaces)
- Agent-name matching is token-exact (never substring: `orchestrator` ⊂ `orchestrator-identity-probe`)
- Preserve encoding (UTF-8, BOM-state) and line endings (CRLF/LF) byte-for-byte
- CHANGELOG.md entry, `config-sync --save` and session restart are MANUAL follow-ups (printed as WARN)
