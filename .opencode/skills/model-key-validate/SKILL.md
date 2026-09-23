---
name: model-key-validate
description: 'Fast LLM-free validation of every frontmatter model key across the live agent files (optionally deploy mirrors too) — format provider/model-key, existence in opencode.json provider models, Did-you-mean suggestions via Levenshtein for every invalid key, unused-model report (catalog keys referenced by zero agents). Runs in seconds, no network. Exit 0 all valid, exit 3 failures found.'
---

# Model Key Validate

Focused, deterministic, LLM-free validation of `model:` keys in agent
frontmatter against the live `opencode.json` provider catalog. Read-only —
never writes. Complements `integrity-check` (which validates keys among many
other checks) with repair-oriented output: Did-you-mean suggestions and the
unused-model report.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- After editing opencode.json provider models (renames/removals) — did any agent key break?
- After `agent-model-migrate` / `bifrost-config-apply` — quick key health check
- Before a migration — see the valid-key catalog and near-miss typos
- Diagnosing "model not found" runtime errors — locate the offending frontmatter
- Housekeeping: which configured models are referenced by zero agents (UNUSED)

## When NOT to use

- Full integrity audit (pairs, counters, routing) — use `integrity-check`
- Fixing an invalid key — use `agent-model-migrate` (this skill only REPORTS)
- Provider config schema audit (limits/modalities) — use `provider-config-audit`
- Discovering new models from the proxy — use `model-discovery`

## Checks performed

1. **Frontmatter extraction**: first `---` block, `^model:[ \t]*(.*)$` line;
   missing block or line -> FAIL `model=<missing>`
2. **Format**: `^[A-Za-z0-9._-]+/.+$` (non-empty provider, non-empty remainder,
   split on FIRST `/`; the model-key itself may contain slashes)
3. **Existence**: `provider.<provider>.models.<model-key>` resolves in live
   opencode.json
4. **Suggestions** (on FAIL only): top-N similar FULL keys `provider/model` from
   the catalog — case-insensitive Levenshtein, prefix bonus, threshold
   `max(3, len/3)`; unknown provider -> closest-provider suggestions
5. **Unused models**: every catalog key with ZERO referencing agents ->
   `UNUSED:` (WARN-status, does NOT affect exit code)
6. **Deploy mirrors** (`-Both`): the same checks for `deploy-package/agents/*.md`
   + `PAIR:` SHA256 live<->deploy per agent

## Usage

```powershell
& ".opencode\skills\model-key-validate\scripts\validate.ps1"
& ".opencode\skills\model-key-validate\scripts\validate.ps1" -Both
& ".opencode\skills\model-key-validate\scripts\validate.ps1" -Provider bifrost-litellm -Suggest 5
& ".opencode\skills\model-key-validate\scripts\validate.ps1" -Json
```

### POSIX mirror

```bash
python .opencode/skills/model-key-validate/scripts/validate.py [--both] [--provider P] [--suggest N] [--json]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Agents <dir>` | agents dir to validate (default: live `~/.config/opencode/agents`) |
| `-Both` | also validate deploy-package/agents + PAIR hashes |
| `-Config <path>` | opencode.json (default `%USERPROFILE%\.config\opencode\opencode.json`) |
| `-Provider <name>` | validate only keys of this provider (others -> SKIP, not FAIL) |
| `-Suggest <n>` | max suggestions per invalid key (default 3, min 1) |
| `-Json` | JSON report instead of token lines |

## Output format

```
STATUS:VALIDATE_START agents_dir=<path> catalog=<n providers>/<m models>
KEY:worker bifrost-litellm/stepfun/step-5-preview -> PASS
KEY:utility bifrost-litellm/glm-5.3 -> FAIL (not found)
SUGGEST:utility did_you_mean=bifrost-litellm/GLM-5.3 (res)
KEY:summarizer model=<missing> -> FAIL (frontmatter without model line)
SKIP:generate-image bifrost-litellm/mimo-v2.5 (provider filter)
UNUSED:bifrost-litellm/legacy-model agents=0
PAIR:worker -> OK
SUMMARY:agents=37 valid=36 invalid=1 unused=1 suggestions=1
STATUS:ALL_VALID   |   STATUS:FAILURES fail=<n>
```

(`-Json`: `{keys:[{agent,model,status,reason,suggestions}],unused:[...],pairs:[...],summary:{...}}`, exit code unchanged.)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | All keys valid (UNUSED/SKIP allowed; PAIRs ok with -Both) |
| 2 | Usage/environment error (agents dir / opencode.json FILE missing, bad flags) |
| 3 | One or more invalid keys (FAIL), PAIR drift (-Both), or opencode.json unparsable |

## Hard rules

- STRICTLY READ-ONLY: never writes, fixes or deletes anything
- No LLM, no network — deterministic local checks only (fast gate, seconds)
- PS and PY mirrors implement the SAME Levenshtein scoring (output parity —
  no difflib in PY)
- No hardcoded agent-count — the agents dir is scanned as-is (works mid-migration
  when the count is 37 or 38)
- UNUSED and SKIP never change the exit code; only FAIL / PAIR-drift does
- Never edit user-level skills
