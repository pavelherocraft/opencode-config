---
name: config-sync
description: 'SHA256 compare and sync live (~/.config/opencode) vs deploy-package vs project mirrors — 37 agent pairs, opencode.json, workflow-enforcement.ts x3, ARCHITECTURE.md x3, MCP_SETUP.md x2, AGENTS.md x4, PLUGIN.md x3. -Plan reports drift (no changes); -Apply publishes live/root (source of truth) to deploy; -Apply -Reverse restores deploy to live.'
---

# Config Sync

Compare and synchronize the live config (`~/.config/opencode/`), the project
repo and `deploy-package/` mirrors. Pure SHA256 comparison + file copy — no
content parsing, no LLM.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- After editing live agent files / opencode.json / plugin — publish changes to deploy (`-Apply`)
- After a fresh clone / on a new machine — restore live from the repo (`-Apply -Reverse`)
- Any time you need a drift report across all mirrors (`-Plan`, default)
- Before `agent-model-migrate` (it BLOCKs on drifted mirrors)

## When NOT to use

- Syncing single-file edits you have not made yet (edit first, then sync)
- Live doc copies `~/.config/opencode/{ARCHITECTURE,MCP_SETUP,PLUGIN}.md` and
  `REVIEW_CONTEXT.md` — OUT OF SCOPE (known pre-existing drift, separate ticket;
  the script prints an informational WARN only)
- Deleting stale files (this skill NEVER deletes — copy-only)

## Direction semantics (unambiguous)

| Mode | Source of truth | Copy direction |
|------|-----------------|----------------|
| `-Plan` (default) | — | none (report only) |
| `-Apply` | live (config groups) / repo root (doc groups) | live/root → deploy-package (+ project plugin, + live AGENTS.md) |
| `-Apply -Reverse` | deploy-package | deploy → live (+ deploy → project plugin, deploy → root/opencode-config docs) |

## Groups

| # | Group | Members (chain order) | Apply source |
|---|-------|-----------------------|--------------|
| agents | `~/.config/opencode/agents/*.md` ↔ `deploy-package/agents/*.md` (37 pairs) | live |
| config | `~/.config/opencode/opencode.json` ↔ `deploy-package/opencode.json` | live |
| plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` ↔ `plugins/workflow-enforcement.ts` ↔ `deploy-package/plugins/workflow-enforcement.ts` | live |
| architecture | `ARCHITECTURE.md` ↔ `opencode-config/ARCHITECTURE.md` ↔ `deploy-package/project-files/ARCHITECTURE.md` | root |
| mcp-setup | `MCP_SETUP.md` ↔ `deploy-package/project-files/MCP_SETUP.md` | root |
| agents-md | `AGENTS.md` ↔ `opencode-config/AGENTS.md` ↔ `deploy-package/project-files/AGENTS.md` ↔ `~/.config/opencode/AGENTS.md` | root |
| plugin-md | `PLUGIN.md` ↔ `opencode-config/PLUGIN.md` ↔ `deploy-package/project-files/PLUGIN.md` | root |

## Workflow

1. **Scan**: enumerate group members; SHA256 every file; classify each member vs
   source of truth: `OK:` / `DRIFT:` / `MISSING:` (target absent) / `EXTRA:` (source-side
   file absent from the counterpart — agents group only, by name-set diff)
2. **Report** (`-Plan`, default): per-group `GROUP:<name> total=<n> ok=<n> drift=<n> missing=<n>`
   + one line per finding; final `STATUS:PLAN_ONLY drift=<n>` — exit 0 (report, not failure)
3. **Apply** (`-Apply [-Reverse]`): for every DRIFT/MISSING member: copy source → target,
   then re-hash: `SYNCED:<path> direction=<src>-><dst> sha=<8>` + `VERIFY:` identical.
   Optional `-Backup`: before any write, copy each to-be-changed target into
   `backup\<yyyyMMdd_HHmmss>_config_sync\<group>\`
4. **Never delete**: EXTRA files are reported, not removed
5. **Final**: `STATUS:SUCCESS synced=<n> failed=<n>` (failed>0 → exit 3)

## Usage

```powershell
# drift report (default)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan
# publish live/root -> deploy (with backup)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Apply -Backup
# restore deploy -> live
& ".opencode\skills\config-sync\scripts\sync.ps1" -Apply -Reverse
# single group / single agent
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan -Group agents -Agent worker
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan -Group config
# machine-readable
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan -Json
```

### POSIX mirror

```bash
python .opencode/skills/config-sync/scripts/sync.py --plan [--group agents] [--agent worker] [--json]
python .opencode/skills/config-sync/scripts/sync.py --apply [--reverse] [--backup]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Plan` | report only (default when neither -Plan nor -Apply given) |
| `-Apply` | perform sync (direction per table above) |
| `-Reverse` | with -Apply: deploy-package is the source (restore) |
| `-Backup` | with -Apply: snapshot changed targets to `backup\<ts>_config_sync\` first |
| `-Group <name>` | limit to one group: agents, config, plugin, architecture, mcp-setup, agents-md, plugin-md |
| `-Agent <name>` | with agents group: single agent pair |
| `-Json` | JSON report instead of token lines |

## Gates

| Gate | Effect |
|------|--------|
| `-Plan` and `-Apply` together / `-Reverse` without `-Apply` / unknown `-Group` | BLOCK (exit 2) |
| Repo root or live config dir not found | BLOCK (exit 2) |
| `-Apply` when source of truth file missing (nothing to copy from) | per-file ERROR, skip file, counted in failed (exit 3 if any) |
| Backup dir creation failure | BLOCK (exit 3, zero writes) |
| SHA256 verify mismatch after copy | BLOCK (exit 3) |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Plan scan completed (even with drift — findings are in the report); Apply with 0 failures |
| 2 | Usage/environment error |
| 3 | Apply failures (copy/verify/backup errors) |

## Hard rules

- NEVER delete files (copy-only; EXTRA reported, never removed)
- NEVER parse or modify file CONTENT — byte-level copy + SHA256 only
- NEVER touch out-of-scope live docs (ARCHITECTURE/MCP_SETUP/PLUGIN/REVIEW_CONTEXT live copies)
- `-Apply -Reverse` overwrites LIVE config — always run `-Plan` first; recommend `-Backup`
- Preserve timestamps semantics of the copy operation (content equality is what matters — verified by SHA256)
- Never edit user-level skills
