# Upstream issue draft — anomalyco/opencode

File at: https://github.com/anomalyco/opencode/issues/new

---

**Title:** Skills: invalid SKILL.md frontmatter is silently dropped with no log/warning (registry ends up builtin-only); manual instance dispose required to recover — v1.18.27

## Environment

- opencode 1.18.27 (Windows desktop app)
- Custom skills in `~/.config/opencode/skills/<name>/SKILL.md`

## Symptom

The skill tool answers every custom skill with:

```
Skill "git-commit" not found. Available skills: customize-opencode
```

— the registry contains only the embedded builtin. No errors or warnings in `opencode.log` (no `failed to load skill`, nothing). The state persists for the whole process and survives config-file edits; only an instance dispose (or full restart) re-runs discovery.

## Root cause (confirmed by reading v1.18.27 source + live experiments)

In `packages/opencode/src/skill/index.ts`, `add()`:

```ts
const md = yield* Effect.tryPromise({
  try: () => ConfigMarkdown.parse(match),
  catch: (err) => err,          // <- parse errors become VALUES
}).pipe(Effect.catch(/* logError path */))

if (!md) return
if (!isSkillFrontmatter(md.data)) return   // <- silent drop, no log
```

Because `tryPromise`'s `catch` maps a parse failure into a *value*, the `Effect.catch` (the only branch that logs `failed to load skill`) never runs. `md` is then the error object — truthy — and `isSkillFrontmatter(md.data)` fails (`data.name` not a string), so the skill is **silently skipped with zero diagnostics**.

The same silent drop happens when YAML *parses* but changes the shape: a `description:` containing an unquoted `": "` sequence (e.g. `... (-Analyze: status, ...)`) decodes as a nested map instead of a string, `typeof data.description === "string"` fails → silent skip. Both of my SKILL.md files hit exactly this.

Experiment confirming the silent path: a minimal SKILL.md with clean frontmatter placed in `~/.agents/skills/probe-skill/` registered immediately (visible via `GET /skill`); the files with the YAML-shape bug were skipped — with no log difference between the two.

## Secondary findings

1. **Junctions are not followed**: an NTFS junction `~/.agents/skills -> ~/.config/opencode/skills` was not scanned (skills invisible), while real directories in the same location were found. If junctions are unsupported, a doc note would help; if `symlink: true` is meant to cover them, it doesn't.
2. **No recovery without dispose/restart**: once an instance's `Skill.state` caches the (empty) result, editing config files or the skills themselves does not rebuild it. `POST /instance/dispose?directory=...` was the only way to re-run discovery live (V2 code even carries a `QUESTION(Dax): Should local skill sources invalidate on filesystem watch events` comment).
3. The `init count=N` log line has no service/instance context, making skill-init issues hard to attribute in logs.

## Suggested fixes

- In `add()`: when `ConfigMarkdown.parse` fails OR `isSkillFrontmatter` returns false for a file matching `SKILL.md`, log a warning with the path and the reason (parse error vs. shape mismatch). Silent skips of user-authored skills are very hard to debug.
- Consider invalidating/re-running skill discovery on config changes (or document that a restart/instance dispose is required).
- Optionally: follow NTFS junctions on Windows or document the limitation.

## Repro

1. `~/.config/opencode/skills/bad/SKILL.md`:
   ```markdown
   ---
   name: bad
   description: Toolkit that analyzes (-Analyze: status, stats) and commits.
   ---
   body
   ```
2. Restart; call `skill(name="bad")` from any agent → `not found`, registry lists only `customize-opencode`, and **nothing** in the log explains why.
3. Quote the description (`description: '... (-Analyze: status, ...)'`), dispose the instance (or restart) → skill registers.
