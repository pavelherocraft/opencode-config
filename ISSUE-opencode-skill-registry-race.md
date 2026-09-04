# Upstream issue draft — anomalyco/opencode

File at: https://github.com/anomalyco/opencode/issues/new

---

**Title:** Skills: registry intermittently initializes empty (race between config load and Skill.state init); sticky for process lifetime — v1.18.27

## Environment

- opencode 1.18.27 (Windows desktop app, server logs `version=1.18.27`)
- Global config dir `~/.config/opencode/` with two custom skills in `skills/<name>/SKILL.md` (valid `name:` + `description:` frontmatter)
- Also configured: `"skills": { "paths": ["~/.config/opencode/skills"] }` (did not help — see analysis)

## Symptom

After **some** restarts, the skill tool returns for every custom skill:

```
Skill "git-commit" not found. Available skills: customize-opencode
```

i.e. the registry contains only the embedded builtin skill. Other restarts with **byte-identical** config and skill files: everything works (skills load via the skill tool, `evaluated permission=skill ... allow` logged).

Once broken, the empty registry is **sticky for the whole process lifetime** — config file changes (e.g. adding/removing AGENTS.md in the config dir) do not rebuild it. Only another app restart re-rolls the dice.

## Evidence (opencode.log)

At startup, multiple instance initializations log lines consistent with skill-state init ~300 ms apart, with diverging counts:

```
15:09:38.431 message=init count=12
15:09:38.735 message=init count=1     <- builtin only
15:09:41.350 message=init count=1
```

In broken runs the failing instances answer every `skill()` call with the NotFoundError above. In lucky runs the same instances load skills normally.

## Analysis (from reading v1.18.27 sources)

`Skill.discovery` / `Skill.state` are `InstanceState.make(...)` ScopedCaches keyed by directory (`packages/opencode/src/skill/index.ts`). The initializer performs:

```ts
const configDirs = yield* config.directories()   // scan {skill,skills}/**/SKILL.md
const cfg = yield* config.get()                  // cfg.skills?.paths scan
```

Hypothesis: the first instance initialization can run **before the (async) config load completes**, so discovery scans with an empty/default config:

- `config.directories()` yields nothing to scan (or only default dirs),
- the `cfg.skills?.paths` loop never runs (`cfg.skills` undefined at that moment) — notably the log shows **no** `skill path not found` warning in broken runs, which the loop would emit for an invalid dir, supporting "loop never ran" over "dir was wrong",
- result: zero matches → registry = builtin only,
- ScopedCache keeps the empty result forever; there appears to be no invalidation hook on config updates for these caches (the V2 skill service even carries a `QUESTION(Dax): Should local skill sources invalidate on filesystem watch events` comment acknowledging the invalidation gap).

This explains the intermittency (~300 ms window at startup), the stickiness, and why `skills.paths` doesn't help when the race hits.

## Repro (intermittent, rough coin-flip)

1. Put a custom skill into `~/.config/opencode/skills/<name>/SKILL.md` (frontmatter with `name` and `description`).
2. Allow the skill tool for some agent; restart opencode.
3. From that agent call `skill(name="<name>")`.
4. Repeat restarts: some runs → not found (registry = builtin only); other runs → loads fine. Same files every time.

## Suggested directions

- Guarantee the config service is fully loaded before the first `Skill.state` initialization (ordering/dependency), **or**
- Invalidate/re-run skill discovery when the config updates (config change events).
- Minor: add a logger/span name to the `init count=N` line so skill-service init is attributable in logs (currently indistinguishable from other `init` lines).

## Workarounds (ours)

- Restart again.
- Agent prompts treat the skill tool as optional and fall back to reading `SKILL.md` / invoking the skill's scripts directly (registry-independent).
