---
name: backup-snapshot
description: 'Pre-change snapshot of the live config — copies all live agent .md files (-Agents) or agents + live opencode.json + live plugin + live and root documentation, ~50 files (-Full), into backup/YYYY-MM-DD_HHMMSS[_label]/ with HASHES.txt (SHA256) and MANIFEST.json, byte-verifies every copy. -Compare <dir> re-hashes the current state against a snapshot (SAME/CHANGED/MISSING_NOW/NEW report; -Strict turns differences into exit 3). Never deletes, never modifies sources.'
---

# Backup Snapshot

Deterministic point-in-time snapshot of the files that live OUTSIDE git
(live agents, live opencode.json, live plugin, live docs) plus the root
documentation — so any change (agent-add, agent-model-migrate, config-sync
-Apply -Reverse, manual plugin edits) can be rolled back. Copy + SHA256 only —
no content parsing, no LLM.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- BEFORE any mutating skill/operation (agent-add, agent-model-migrate,
  config-sync -Apply -Reverse, plugin upgrades) — recommended first step
- Before risky manual edits of the live config
- AFTER a change — `-Compare <snapshot>` shows exactly what the change touched
- Auditing: prove the live config did not drift since a known point

## When NOT to use

- Backing up git-recoverable files (deploy-package, repo scripts) — `-Full`
  includes root docs only for snapshot self-sufficiency
- Restoring files (copy back manually from the snapshot dir, or use
  `config-sync -Apply -Reverse` for live<->deploy restoration)
- Syncing mirrors (use `config-sync`); integrity audit (use `integrity-check`)

## Modes

| Mode | Scope | Files |
|------|-------|-------|
| `-Agents` (default) | live `agents/*.md` | ~38 |
| `-Full` | live agents + live opencode.json + live plugins/workflow-enforcement.ts + live docs (AGENTS/ARCHITECTURE/MCP_SETUP/PLUGIN/REVIEW_CONTEXT .md) + repo root docs (ARCHITECTURE/AGENTS/PLUGIN/MCP_SETUP/REVIEW_CONTEXT/CHANGELOG .md) | ~50 |
| `-Compare <dir>` | re-hash current state vs snapshot `<dir>` | — |

## Snapshot layout

```
backup/<yyyy-MM-dd_HHmmss>[_<label>]/
├── live/
│   ├── agents/*.md                       # both modes
│   ├── opencode.json                     # Full only
│   ├── plugins/workflow-enforcement.ts   # Full only
│   └── docs/*.md                         # Full only (live doc copies)
├── repo/docs/*.md                        # Full only (root documentation)
├── HASHES.txt                            # <SHA256-UPPER>␣␣<rel/path> per copied file, sorted
└── MANIFEST.json                         # mode, label, created_utc, status, per-file {src,rel,sha256,bytes}
```

## Workflow

1. **Pre-check**: every source file exists and is readable; dest dir does NOT
   exist yet; scope is non-empty. Any problem -> BLOCK before any copy
2. **Copy**: each source -> dest (byte copy), then re-hash source and copy:
   `COPIED:<rel> sha=<8> bytes=<n>`; hash mismatch or copy error ->
   `ERROR:` + `STATUS:FAILED copied=<n> failed=<n>` exit 3 (copied files are
   KEPT — the skill never deletes; HASHES/MANIFEST written with status=FAILED;
   re-run with a fresh dest)
3. **Manifest**: write HASHES.txt (sorted by rel path) + MANIFEST.json; write
   failure -> exit 3
4. **Report**: `SUMMARY:mode=<m> files=<n> bytes=<n> dest=<rel>` +
   `STATUS:SUCCESS`; WARN if the live agents count != `-ExpectedAgents`
   (default 38 — informational, snapshot is still taken)

### Compare

1. `<dir>/MANIFEST.json` + `HASHES.txt` must exist and parse (else exit 3;
   dir itself missing -> exit 2)
2. Per manifest entry: hash the CURRENT source -> `SAME:<rel>` /
   `CHANGED:<rel> backup=<sha8> current=<sha8>` / `MISSING_NOW:<rel>`
   (source gone)
3. Backup self-integrity: re-hash each backup copy vs MANIFEST sha ->
   `CORRUPT:<rel> backup=<sha8> disk=<sha8>` on mismatch
4. Scope scan: current live `agents/*.md` absent from the manifest ->
   `NEW:live/agents/<name>.md` (e.g. an agent added after the snapshot)
5. `SUMMARY:same=<n> changed=<n> missing=<n> new=<n> corrupt=<n>` +
   `STATUS:IDENTICAL` / `STATUS:DIFFERENCES`; exit 0 (report) — with `-Strict`
   and changed+missing+new+corrupt > 0 -> exit 3

## Usage

```powershell
# agents-only snapshot (default), auto timestamp dir
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Agents
# full snapshot with a topic label (repo convention: backup/<date>_<topic>/)
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Full -Label "before_agent_add"
# explicit destination
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Full -Dest "backup\2026-09-23_manual"
# compare current state with a snapshot
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Compare "backup\2026-09-23_120000_before_agent_add"
# compare as a gate (differences -> exit 3)
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Compare "<dir>" -Strict
```

### POSIX mirror

```bash
python .opencode/skills/backup-snapshot/scripts/snapshot.py --agents
python .opencode/skills/backup-snapshot/scripts/snapshot.py --full --label before_agent_add
python .opencode/skills/backup-snapshot/scripts/snapshot.py --compare backup/2026-09-23_120000_before_agent_add [--strict] [--json]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Agents` | snapshot live agent .md files only (default mode) |
| `-Full` | agents + live config/plugin/docs + root docs (~50 files) |
| `-Label <topic>` | suffix for the auto dest dir name |
| `-Dest <dir>` | explicit snapshot dir (must not exist; relative -> repo root) |
| `-Compare <dir>` | compare mode: current state vs an existing snapshot |
| `-Strict` | with -Compare: differences (changed/missing/new/corrupt) -> exit 3 |
| `-ExpectedAgents <n>` | informational WARN threshold (default 38) |
| `-Json` | JSON report instead of token lines |

## Gates

| Gate | Effect |
|------|--------|
| `-Agents` + `-Full` together / `-Compare` with a mode flag / `-Strict` without `-Compare` | BLOCK (exit 2) |
| Repo root or live config dir not found | BLOCK (exit 2) |
| Empty scope / any source file missing or unreadable (pre-check) | BLOCK (exit 2, zero copies) |
| Dest dir already exists | BLOCK (exit 2, zero copies) |
| Dest creation failure | BLOCK (exit 3, zero copies) |
| Copy hash mismatch / HASHES.txt or MANIFEST.json write failure | exit 3 (copies kept, never deleted) |
| -Compare: dir missing | exit 2 |
| -Compare: MANIFEST/HASHES missing or corrupt | exit 3 |
| -Compare -Strict: changed+missing+new+corrupt > 0 | exit 3 |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Snapshot created and verified; compare report (without -Strict) |
| 2 | Usage/environment error |
| 3 | Copy/verify/manifest failure; compare inputs invalid; -Strict differences |

## Hard rules

- NEVER delete or modify any source file; NEVER delete anything (partial
  snapshots are kept, MANIFEST status=FAILED)
- Byte-level copy + SHA256 verify only — no content parsing
- HASHES.txt format: `<SHA256-UPPER>␣␣<rel/path>` (two spaces, forward slashes,
  sorted, LF) — stable for diffing between snapshots
- Snapshots live in repo `backup/`; the skill never runs git
- Live doc copies (~/.config/opencode/*.md) are included in -Full despite known
  pre-existing drift — a snapshot must capture reality as-is
- -Compare never re-creates or repairs anything — report only
- NEW detection covers the agents scope only (documented limitation)
- Never edit user-level skills
