---
name: bifrost-config-apply
description: 'Apply user-pasted bifrost-litellm provider config (JSON) — diff vs current, per-model merge into opencode.json with JSON validation, sync to deploy-package/, SHA256 verify, conventional commit + push.'
---

# Bifrost Config Apply

Apply a user-pasted bifrost-litellm provider config (JSON) to the opencode configuration.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- User pastes a JSON config with `provider.bifrost-litellm.models` and asks to apply/sync/update
- User says "добавь или обнови настройки для провайдера" with a JSON paste
- User says "apply this config" with a JSON paste

## When NOT to use

- User asks to audit/validate config (use `provider-config-audit`)
- User asks to discover new models (use `model-discovery`)
- User asks to rollback a commit (manual git operations)

## Workflow

1. **Receive paste**: User provides JSON in task description
2. **Diff**: Run `scripts/diff.js -PasteJson <path> -Current <opencode.json>` → JSON diff `{added[], removed[], modified[]}`
3. **Plan**: Display the diff to the user and await explicit approval (there is no plan tool)
4. **Apply** (on approval): Run `scripts/apply.ps1 -PasteJson <path> -Apply [-Push]`:
   - Per-model merge via `scripts/diff.js -Merge` — only
     `provider.bifrost-litellm.models` is rewritten; `agent`, `plugin`, `mcp`,
     `permission` and every other section are preserved
   - Write `~/.config/opencode/opencode.json` (merged JSON validated before replace)
   - `Copy-Item` → `deploy-package/opencode.json`
   - SHA256 verify identical
   - Generate conventional commit message from diff
   - `git add deploy-package/opencode.json`
   - `git commit -F <message>` (NOT push unless `-Push`)
5. **Report**: model count, files changed, commit hash, push status

## Usage

### Plan only (dry-run)

```powershell
& ".opencode\skills\bifrost-config-apply\scripts\apply.ps1" -PasteJson "C:\path\to\paste.json" -PlanOnly
```

Output: `STATUS:/DIFF:/ERROR:` lines, exit 0

### Apply (edit + commit)

```powershell
& ".opencode\skills\bifrost-config-apply\scripts\apply.ps1" -PasteJson "C:\path\to\paste.json" -Apply
```

Output: `STATUS:/DIFF:/EDITED:/SYNCED:/SHA256:/COMMITTED:/ERROR:` lines, exit 0

### Apply + push

```powershell
& ".opencode\skills\bifrost-config-apply\scripts\apply.ps1" -PasteJson "C:\path\to\paste.json" -Apply -Push
```

Output: `STATUS:/DIFF:/EDITED:/SYNCED:/SHA256:/COMMITTED:/PUSHED:/ERROR:` lines, exit 0

### POSIX mirror

```bash
python .opencode/skills/bifrost-config-apply/scripts/apply.py --paste-json /path/to/paste.json --apply
```

## Gates

| Gate | Effect |
|------|--------|
| Invalid JSON paste | BLOCK |
| Paste missing `provider.bifrost-litellm.models` | BLOCK |
| Secret pattern in paste (mirror git-commit gates) | BLOCK |
| deploy-package/opencode.json missing | BLOCK |
| git identity (user.name/user.email) missing | BLOCK |
| SHA256 mismatch after sync | BLOCK |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (or dry-run / no changes) |
| 2 | Usage/environment error (missing args/files incl. missing deploy-package, diff failure incl. invalid JSON) |
| 3 | Gate block (secret pattern, paste missing `provider.bifrost-litellm.models`, merge failure, merged JSON invalid, SHA256 mismatch, git identity/commit/push failure) |

## Hard rules

- Never bypass per-edit JSON validation
- Never overwrite non-model config sections (merge only `provider.bifrost-litellm.models`)
- Never push without explicit `-Push` flag
- Never edit user-level skills
- Never modify deploy-package/ directly (only via sync)
- Never force a git identity — use the user's configured `user.name`/`user.email`