---
name: deploy-package-build
description: 'Deterministic rebuild of deploy-package/ from live sources — byte-copies live agents (38), live opencode.json, live plugins/workflow-enforcement.ts and 4 root docs (ARCHITECTURE/AGENTS/MCP_SETUP/PLUGIN) into the package, SHA256-verifies every copy, regenerates HASHES.txt, and gates on counters (agents 38, distinct models 11, routing 26/10 across opencode.json + ARCHITECTURE.md + workflow-enforcement.ts) plus a literal-secrets scan of opencode.json. -Plan (default) reports SAME/CHANGED/NEW/STALE without writing; -Apply performs the build; -Archive additionally rebuilds deploy-package.7z via 7-Zip. Never deletes files, never runs git. Exit 0, exit 2 usage/environment, exit 3 gate/copy failure.'
---

# Deploy Package Build

Deterministic, LLM-free rebuild of `deploy-package/` from the live config and
root documentation: byte-copy + SHA256 verify + counter/secret gates +
HASHES.txt manifest + optional 7z archive. The package is the git-tracked
shipping artifact consumed by `deploy-package/scripts/install.ps1` on target
machines.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Packaging a release after config changes (agent-add, agent-model-migrate,
  plugin/doc edits) once the live state is known-good
- Refreshing deploy-package after `config-sync` confirmed live is the truth
- Producing HASHES.txt / deploy-package.7z for distribution
- Pre-release gate: counters + routing + secrets verified BEFORE shipping

## When NOT to use

- Syncing mirror CHAINS (root ↔ opencode-config ↔ deploy docs, 3-way plugin
  copies) — use `config-sync` (this skill copies live→deploy only)
- Backups/rollback — use `backup-snapshot`
- Full integrity audit (pair hashes, model keys) — use `integrity-check`
- Installing on a target machine — `deploy-package/scripts/install.ps1`

## Mapping (source → package)

| Source | Destination |
|--------|-------------|
| `~/.config/opencode/agents/*.md` (all, expected 38) | `deploy-package/agents/` |
| `~/.config/opencode/opencode.json` | `deploy-package/opencode.json` |
| `~/.config/opencode/plugins/workflow-enforcement.ts` | `deploy-package/plugins/workflow-enforcement.ts` |
| `<repo>/ARCHITECTURE.md`, `AGENTS.md`, `MCP_SETUP.md`, `PLUGIN.md` | `deploy-package/project-files/` |

Untouched (static): `scripts/`, `README.md`, `DEPLOYMENT_GUIDE.md`,
`plugins/package.json`, `plugins/node_modules/`. Out of scope: live
`plugins/package.json` / `plugins/node_modules` are NOT mirrored (documented
limitation — they change only on plugin dependency updates, handled manually).

## Gates (run in BOTH -Plan and -Apply; any BLOCK → exit 3, zero copies)

1. `GATE:JSON` — live opencode.json parses
2. `GATE:SECRETS` — literal-secret scan of live opencode.json:
   `"sk-..."`-style tokens (>=16 chars) and `"api_key|apikey|access_token|secret":
   "<literal>"` (value not starting with `$` / `YOUR_` / `{{`). Output NEVER
   prints secret values — pattern name + hit count only
3. `COUNT:agents_live` == `-ExpectedAgents` (default 38)
4. `COUNT:models_used` — distinct frontmatter models across live agents ==
    `-ExpectedModels` (default 10)
5. `COUNT:routing_orchestrator` — opencode.json task-allows == ARCHITECTURE.md
   header number == ARCHITECTURE.md table rows == plugin ROUTING_TABLES entries
   == `-ExpectedOrch` (default 26)
6. `COUNT:routing_plankestrator` — same, `-ExpectedPlan` (default 10)

## Workflow

### -Plan (default, zero writes)

1. Pre-check flags/paths (exit 2); run gates 1–6 (any BLOCK → exit 3)
2. Diff scan every mapped pair (SHA256 both sides):
   `SAME:<rel> sha=<8>` / `CHANGED:<rel> live=<8> deploy=<8>` / `NEW:<rel>` (dest missing)
3. STALE scan (deploy-only files in managed scopes — see Hard rules):
   `WARN:STALE:<rel>` (with `-Strict` → exit 3)
4. `PLAN:HASHES.txt files=<n>` (would-generate info)
5. `SUMMARY:mode=plan scanned=<n> same=<n> changed=<n> new=<n> stale=<n>` +
   `STATUS:PLAN_OK` exit 0

### -Apply

1. Pre-check + gates (as above; BLOCK → exit 3 before any copy)
2. Byte-copy CHANGED/NEW files only (SAME skipped — no churn); per file:
   `COPIED:<rel> sha=<8> bytes=<n>` + re-hash verify `VERIFY:<rel> identical`;
   copy error or hash mismatch → `ERROR:<rel>` + `STATUS:FAILED copied=<n>
   failed=<n>` exit 3 (copied files are KEPT — never deleted)
3. HASHES.txt regenerated over the package scope; content-equal → no rewrite
   (`SAME:HASHES.txt`), else `EDITED:HASHES.txt lines=<n>`; write failure → exit 3
4. STALE report; `SUMMARY:mode=apply scanned/same/changed/new/copied/stale/bytes`;
   `STATUS:SUCCESS`
5. `-Archive` (only after STATUS:SUCCESS): 7-Zip build (below)
6. `WARN:MANUAL` follow-ups: git commit via the `git-commit` agent
   (deploy-package changed); live-config changes take effect in a NEW opencode
   session; target install via `deploy-package/scripts/install.ps1`;
   recommended post-check: `integrity-check` + `deploy-package/scripts/verify.ps1`

### HASHES.txt

`<SHA256-UPPER>␣␣<rel/path>` — two spaces, forward slashes, sorted by rel,
LF endings, trailing LF (backup-snapshot-compatible format). Scope = ALL
package files EXCEPT `plugins/node_modules/**`, `deploy-package.7z`,
`*.tmp7z`, `HASHES.txt` itself.

### -Archive

7-Zip resolved via PATH, then `%ProgramFiles%\7-Zip\7z.exe`, then
`%ProgramFiles(x86)%\7-Zip\7z.exe` (none found → exit 2 in pre-check). The
POSIX mirror resolves `7z`/`7za` via PATH, then `/usr/bin/7z`. Build runs with
repo root pinned explicitly via `-w<repoRoot>`:

```
7z a -t7z -mx=5 -w<repoRoot> deploy-package\deploy-package.7z.tmp7z deploy-package\* -xr!*.tmp7z -xr!deploy-package.7z
```

(includes node_modules for install parity; excludes the old archive and the
tmp). 7z exit >= 2 → `ERROR:ARCHIVE` exit 3 (tmp KEPT — never deleted).
Success → tmp atomically replaces `deploy-package\deploy-package.7z` (build
artifact overwrite), then `ARCHIVED:deploy-package.7z sha=<8> bytes=<n>`.

## Usage

```powershell
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Plan
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply -Archive
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply -Strict
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Plan -ExpectedAgents 38
```

### POSIX mirror

```bash
python .opencode/skills/deploy-package-build/scripts/build.py --plan
python .opencode/skills/deploy-package-build/scripts/build.py --apply [--archive] [--strict] [--json]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Plan` | report-only, zero writes (default when neither -Plan nor -Apply given) |
| `-Apply` | perform the build (copy + verify + HASHES.txt) |
| `-Archive` | with -Apply: rebuild deploy-package.7z (requires 7-Zip) |
| `-Strict` | STALE findings → exit 3 |
| `-ExpectedAgents <n>` | gate default 38 |
| `-ExpectedModels <n>` | gate default 10 |
| `-ExpectedOrch <n>` / `-ExpectedPlan <n>` | gate defaults 26 / 10 |
| `-Json` | JSON report instead of token lines (exit codes unchanged) |

## Gates

| Gate | Effect |
|------|--------|
| `-Plan` + `-Apply` together | BLOCK (exit 2) |
| `-Archive` without `-Apply` | BLOCK (exit 2) |
| Live dir / repo root / `deploy-package/` / any mapped source missing or unreadable | BLOCK (exit 2, zero copies) |
| 7-Zip not found with `-Archive` | BLOCK (exit 2) |
| GATE:JSON / GATE:SECRETS / any COUNT mismatch | BLOCK (exit 3, zero copies) |
| Copy error / SHA256 verify mismatch / HASHES.txt write failure | exit 3 (copies kept) |
| STALE deploy-only files | WARN (exit unchanged); with `-Strict` → exit 3 |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | -Plan clean report, or -Apply success (archive ok if requested) |
| 2 | Usage/environment error |
| 3 | Gate BLOCK, copy/verify failure, HASHES write failure, -Strict with STALE |

## Hard rules

- NEVER deletes any file (STALE deploy-only files are reported, not removed;
  a failed archive tmp is kept); overwriting mapped deploy-package copies and
  replacing the .7z build artifact are the ONLY mutations
- Byte-level copy (`[System.IO.File]::Copy` / `shutil.copyfile`) — CRLF/BOM
  preserved by construction; SHA256 verify after every copy
- Gates run BEFORE any copy; a blocked build writes nothing (zero-copy guarantee)
- Secret values are NEVER printed — pattern name + hit count only
- Counter parsers are verbatim copies of integrity-check helpers
  (`Count-TaskAllow` / `Get-WhitelistCount` / `Count-RoutingPlugin`) — skills
  are self-contained, no cross-skill imports; update together if anchors change
- STALE scopes: `deploy-package/agents/*.md` absent from live, and
  `project-files/*.md` outside the 4-doc mapping; everything else static
- HASHES.txt: LF-forced, sorted, two-space format — stable for git diffs
- Never runs git (commit via the `git-commit` agent); never touches live files
  (one-way live→deploy only)
- Expected counters are parameters (38/11/26/10 defaults) — after a legitimate
  architecture change, update the defaults in BOTH scripts and this file together
- Never edit user-level skills
