---
name: config-sync
description: 'Sync the 5 live↔repo pairs declared in ARCHITECTURE.md (agents/*.md, opencode.json, plugins/workflow-enforcement.ts, skills/git-commit/, AGENTS.md→AGENTS.global.md). --save (default) snapshots live→repo before a commit; --restore rolls repo→live back (explicit emergency flag, prints a warning); --plan reports drift only (exit 3 on drift). SHA256 compare + byte copy, never deletes.'
---

# Config Sync

Compare and synchronize the LIVE config (`~/.config/opencode/`) with its REPO
snapshot. Exactly 5 sync pairs (ARCHITECTURE.md §File Locations). Pure SHA256
comparison + file copy — no content parsing, no LLM.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Before a commit, after editing live config — snapshot it (`--save`)
- Any time you need a drift report across the 5 pairs (`--plan`)
- Emergency rollback of the live config from the last committed repo state
  (`--restore` — explicit flag only, never automatic)

## When NOT to use

- Syncing single-file edits you have not made yet (edit live first, then sync)
- Deleting stale files (this skill NEVER deletes — copy-only; EXTRA reported)
- Validating counters/model keys (use `integrity-check`)

## Direction semantics (unambiguous)

| Mode | Source of truth | Copy direction |
|------|-----------------|----------------|
| `--save` (default) | live | live → repo |
| `--restore` | repo | repo → live (explicit emergency rollback; warning printed) |
| `--plan` | — | none (report only) |

`save` is the NORMAL direction: edits happen in live, the repo is a
committable snapshot. `restore` overwrites the LIVE config — run
`backup-snapshot` first and only do it deliberately.

## Sync pairs (5)

| # | Live | Repo |
|---|------|------|
| 1 | `~/.config/opencode/agents/*.md` | `agents/*.md` |
| 2 | `~/.config/opencode/opencode.json` | `opencode.json` |
| 3 | `~/.config/opencode/plugins/workflow-enforcement.ts` | `plugins/workflow-enforcement.ts` |
| 4 | `~/.config/opencode/skills/git-commit/*` | `skills/git-commit/*` |
| 5 | `~/.config/opencode/AGENTS.md` | `AGENTS.global.md` (renamed mirror) |

## Workflow

1. **Scan**: enumerate pair members; SHA256 every file; classify each vs the
   mode's source side: `OK` / `DRIFT` (both exist, hashes differ) /
   `MISSING` (absent on the destination side) / `EXTRA` (destination-side-only
   file — reported, never deleted)
2. **Report**: per-pair `PAIR:<name> ok=<n> drift=<n> missing=<n> extra=<n>`
   + one line per finding; drift/missing lines carry the hint `(use --save)`
3. **Save/Restore**: for every DRIFT/MISSING member: copy source → destination,
   then re-hash and verify: `SYNCED:<path> direction=<src>-><dst> sha=<8>`
4. **Never delete**: EXTRA files are reported, not removed
5. **Final**: `SUMMARY:mode=<m> synced=<n> failed=<n> extra_reported=<n>` +
   `STATUS:SUCCESS` / `STATUS:NO_CHANGES` / `STATUS:FAILED`

## Usage

```powershell
# snapshot live -> repo (default mode)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Save
# drift report only (exit 3 when drift found)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan
# emergency rollback repo -> live (warns, overwrites live)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Restore
# single pair / machine-readable
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan -Pair agents
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan -Json
```

### POSIX mirror

```bash
python .opencode/skills/config-sync/scripts/sync.py --save
python .opencode/skills/config-sync/scripts/sync.py --plan [--pair agents] [--json]
python .opencode/skills/config-sync/scripts/sync.py --restore
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Save` / `--save` | live → repo (default when no mode flag is given) |
| `-Restore` / `--restore` | repo → live; explicit emergency rollback, prints a warning |
| `-Plan` / `--plan` | report only; exit 3 when drift detected |
| `-Pair <name>` / `--pair <name>` | limit to one pair: `agents`, `opencode.json`, `plugin`, `skills/git-commit`, `AGENTS.md` |
| `-Json` / `--json` | JSON report instead of token lines |

## Gates

| Gate | Effect |
|------|--------|
| Two mode flags together / unknown `-Pair` | BLOCK (exit 2) |
| Live config dir or repo root (`.opencode/`) not found | BLOCK (exit 2) |
| Source-side file missing (nothing to copy from) | `ERROR:` finding, counted in failed (exit 3 if any) |
| SHA256 verify mismatch after copy | `ERROR:` finding, counted in failed (exit 3) |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | `--plan` without drift; `--save`/`--restore` without failures |
| 2 | Usage/environment error |
| 3 | Drift detected (`--plan`); copy/verify failures (`--save`/`--restore`) |

## Hard rules

- NEVER delete files (copy-only; EXTRA reported, never removed)
- NEVER parse or modify file CONTENT — byte-level copy + SHA256 only
- NEVER restore (repo → live) implicitly — restore requires the explicit flag
  and prints a warning; run `backup-snapshot` before restoring
- Preserve timestamps semantics of the copy operation (content equality is
  what matters — verified by SHA256)
- Never edit user-level skills
