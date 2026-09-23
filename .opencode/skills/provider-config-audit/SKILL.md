---
name: provider-config-audit
description: 'Read-only validation of bifrost-litellm provider config — duplicate keys, invalid limits, malformed modalities/options/variants, severity-tagged findings (nit/concern/blocker).'
---

# Provider Config Audit

Read-only validation of the bifrost-litellm provider config in opencode.json.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User asks to validate/audit the provider config
- User asks "are there any issues with my config?"
- User asks to check for duplicate keys, invalid limits, etc.

## When NOT to use

- User asks to apply a new config (use `bifrost-config-apply`)
- User asks to discover new models (use `model-discovery`)

## Workflow

1. Run `scripts/audit.ps1 [-Config <path>] [-Provider bifrost-litellm] [-Json]`
2. Returns findings list with severity tags
3. No edits — pure observation

## Usage

```powershell
& ".opencode\skills\provider-config-audit\scripts\audit.ps1"
& ".opencode\skills\provider-config-audit\scripts\audit.ps1" -Config "C:\path\to\opencode.json"
& ".opencode\skills\provider-config-audit\scripts\audit.ps1" -Json
```

### POSIX mirror

```bash
python .opencode/skills/provider-config-audit/scripts/audit.py --json
```

## Severity mapping

- `blocker`: invalid JSON, missing required keys (limit)
- `concern`: duplicate keys, invalid limit values, malformed modalities
- `nit`: legacy `options.thinking` (migration candidate), non-conventional limit values (e.g. context=0 except placeholder)

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | No findings, or nit-only findings |
| 2 | Usage/environment error (config not found, provider not found) |
| 3 | Findings at concern/blocker severity (including invalid JSON) |

## Checks performed

- No duplicate keys across all providers (raw-text scan before parsing)
- `limit.context >= 0`, `limit.output >= 0`
- `limit.context == 0` → **nit** unless the model name contains `placeholder`
- `modalities.input/output` arrays of valid strings (`text|image|audio|video`)
- `options.reasoningEffort` ∈ `low|medium|high|max` (если есть)
- `options.thinking` legacy → **nit** (мы мигрируем на reasoningEffort+variants)
- `variants.*.reasoningEffort` defined если есть variants
- `attachment` — boolean