---
name: model-discovery
description: 'Query bifrost-litellm /v1/models endpoint, compare with config — report models in API but not in config (add candidates), in config but 404 in API (decommissioned), and context/output limit mismatches.'
---

# Model Discovery

Query the bifrost-litellm `/v1/models` endpoint and compare with configured models.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User asks "what models are available in the API?"
- User asks "are there any models I'm missing?"
- User asks "are there any decommissioned models in my config?"

## When NOT to use

- User asks to apply a new config (use `bifrost-config-apply`)
- User asks to audit config schema (use `provider-config-audit`)

## Workflow

1. Run `scripts/discover.ps1 [-ApiBaseUrl <default>] [-Config <opencode.json>]`
2. Reads `LITELLM_API_KEY` from env
3. GET `{base}/models` with Bearer auth
4. Compare with `provider.bifrost-litellm.models`
5. Output:
   - `IN_API_NOT_CONFIG: <key>` (add candidates)
   - `IN_CONFIG_NOT_API: <key>` (decommissioned candidates)
   - `LIMIT_MISMATCH: <key> <limit> (config=<X> api=<Y>)` (only when the API exposes limits)

## Usage

```powershell
& ".opencode\skills\model-discovery\scripts\discover.ps1"
& ".opencode\skills\model-discovery\scripts\discover.ps1" -ApiBaseUrl "https://hcbifrost.herocraft.com/litellm/v1"
& ".opencode\skills\model-discovery\scripts\discover.ps1" -Json
```

### POSIX mirror

```bash
python .opencode/skills/model-discovery/scripts/discover.py --json
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | No findings (config matches API) |
| 2 | Usage/environment error (missing `LITELLM_API_KEY`, config not found, API request failed) |
| 3 | Findings present (models missing/decommissioned, limit mismatch) |

## Requirements

- `LITELLM_API_KEY` env var must be set
- Network access to bifrost-litellm API