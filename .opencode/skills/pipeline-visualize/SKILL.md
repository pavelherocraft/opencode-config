---
name: pipeline-visualize
description: 'Fast LLM-free ASCII visualization of every orchestration pipeline parsed from root ARCHITECTURE.md section "2. Pipelines" — step-chain diagrams where each agent step is annotated with its frontmatter model and Model Roles role/tier; prewalk pairs highlighted (planner-role step handing off to an equal-or-cheaper tier, e.g. dev-planner top ==> dev-professor mid); rework loops, parallel waves, wildcards and pseudo-steps rendered as distinct nodes; notation examples and decision-tree arrows excluded. Formats: ascii (default), markdown, json. Strictly read-only, runs in seconds. Exit 0 rendered, exit 2 usage/environment error.'
---

# Pipeline Visualize

Deterministic, LLM-free renderer of the orchestration pipelines defined in
root `ARCHITECTURE.md` `## 2. Pipelines`: ASCII step-chain diagrams with model
and tier annotations per agent step, prewalk handoffs highlighted, rework
loops and parallel waves as grouped nodes. Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Onboarding/overview: all pipelines with model costs at a glance
- Before/after model migrations: where cheap/expensive models sit in flows
- Prewalk audit: which planner→executor handoffs exist per pipeline
- Diagrams for plans/reviews/docs (-Format markdown / -Format json)

## When NOT to use

- Tier compliance validation (Check 11) — use the `consistency-checker` agent
- Fleet data (routing, permissions) — use `agent-report`
- Counters/pairs/integrity gating — use `integrity-check`
- Editing pipelines — ARCHITECTURE.md is edited manually via text anchors

## Parsing rules (what becomes a diagram)

| Rule | Detail |
|------|--------|
| Span | `## 2. Pipelines` → next `## ` heading (anchor missing → exit 2) |
| Labels | nearest `###` heading; a line prefix `NAME:` (e.g. `DOCS DEEP:`) overrides the label; duplicate labels get ` #N` suffix |
| Chains | lines containing an arrow (U+2192 or `->`); a line STARTING with an arrow CONTINUES the previous chain (multi-line fences) |
| Pending heads | an arrow-free `NAME:` head line directly followed by an arrow-initial line is glued to that continuation (DOCS DEEP fence head) |
| Table rows | a line starting with `\|`: the first arrow-free cell becomes the variant label, arrow-containing cells become the chain (DEV SIMPLE table variants) |
| Excluded spans | `### Pipeline Notation`, `### DEV Complexity Classification`, `### Auto-DOCS Hook` (syntax demos / decision tree / hook rule — not pipelines) |
| Excluded lines | lines containing `TRIAGE_RESULT`; chains with <2 tokens or ZERO agent/wildcard-resolved tokens (a WAVE node counts as resolved when any member is a real agent name) |
| Annotations | parentheticals `(writes bug_plan.md)`, `(Kimi K3)` etc. dropped; markdown bullets/backticks/bold stripped |
| Loops | `[rework loop: a → b, max 3]` → LOOP node (inner text + max N) |
| Waves | `[a ∥ b ∥ c]` (U+2225 inside brackets) → WAVE node (parallel members) |
| Steps | exact agent name → AGENT node; `name-*` with >=1 prefix match → WILDCARD node; anything else (barrier, decompose, synthesis, RESEARCH.md) → PSEUDO node |

Models come from agent frontmatter (live by default; `-Source deploy` for
deploy-package); role/tier from root ARCHITECTURE.md `## Model Roles`.
Expected labels (WARN:PIPELINE_NOT_FOUND when absent, case-insensitive
substring over parsed labels): `BUGFIX (SIMPLE)`, `BUGFIX DEEP`, `DEV SIMPLE`,
`DEV COMPLEX`, `DEV SUPERCOMPLEX`, `DEVOPS`, `DOCS`, `PLAN`, `RESEARCH`.

Identical token sequences across sections are deduplicated (first wins —
e.g. a fan-out chain repeated under a pattern-description heading).

## Prewalk highlighting

tierRank: top=3, mid=2, low=1 (`?`=unmapped — never analyzed). For adjacent
AGENT-resolved steps A → B (loops/waves/pseudo/wildcards skipped; loop
interiors not analyzed):

| Condition | Marker | Connector |
|-----------|--------|-----------|
| role(A) starts with `plan` or equals `docs-plan`, AND tierRank(A) >= tierRank(B) | `PREWALK:` | `==>` |
| role(A) starts with `plan` or equals `docs-plan`, AND tierRank(A) < tierRank(B) | `WARN:PREWALK_INVERSION` | `!->` |
| otherwise tierRank(A) > tierRank(B) | `INFO:TIER_DROP` | `~->` |
| otherwise | — | `-->` |

Compliance enforcement stays with consistency-checker Check 11 — markers here
are advisory. Canonical expected pairs: plan-bug ==> execute-bug (BUGFIX DEEP),
dev-planner ==> dev-professor (DEV COMPLEX), docs-planner ==> docs-writer
(DOCS DEEP, equal tier).

## Workflow

1. Resolve flags/paths (invalid → exit 2); read ARCHITECTURE.md
2. Extract §2 span (missing → exit 2); cut excluded subsections; scan lines →
   raw chain list (label/variant, continuations, loop/wave placeholders)
3. Filter (>=2 tokens, >=1 agent-resolved) / dedupe / label `#N` suffixes;
   expected-label check (WARN)
4. Resolve steps: model via frontmatter (`model=<missing>` → WARN:STEP_NO_MODEL),
   role/tier via Model Roles (WARN:ROLE_UNMAPPED), wildcards (WARN:STEP_UNRESOLVED
   kind=wildcard matches=N), pseudo/unknown (WARN:STEP_UNRESOLVED kind=pseudo|unknown)
5. Detect prewalk / inversion / tier-drop pairs
6. Render per -Format; `-Pipeline` filter (zero matches → exit 2); SUMMARY; exit 0

## Usage

```powershell
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1"
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Pipeline "DEV COMPLEX"
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Format markdown
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Format json
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Source deploy -NoModels
```

### POSIX mirror

```bash
python .opencode/skills/pipeline-visualize/scripts/visualize.py [--pipeline SUBSTR] [--format ascii|markdown|json] [--source live|deploy] [--no-models]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Pipeline <substr>` | render only pipelines whose label contains substr (case-insensitive); zero matches → exit 2 |
| `-Format ascii\|markdown\|json` | output format (default ascii) |
| `-Source live\|deploy` | agents dir for models (default live) |
| `-AgentsDir <dir>` | explicit agents dir (overrides `-Source`) |
| `-NoModels` | compact boxes: index+name and tier only |
| `-Arch <path>` | ARCHITECTURE.md (default: repo root) |

## Output format

ascii/markdown modes:

```
STATUS:VIS_START arch=ARCHITECTURE.md pipelines=12 agents_source=live
=== DEV COMPLEX (8 steps) ===
+-------------------+     +---------------------+
| 1. dev-planner    | ==> | 2. dev-professor    | --> ...
|    qwen3.8-max    |     |    GLM-5.3 (res)    |
|    top            |     |    mid              |
+-------------------+     +---------------------+
LEGEND: --> seq | ==> prewalk | ~-> tier drop | !-> INVERSION | LOOP/WAVE boxes
PIPELINE:DEV COMPLEX steps=8 agents=7 pseudo=0 loops=1 waves=0 prewalk=1 drops=1
PREWALK:DEV COMPLEX dev-planner(plan-strong,top) ==> dev-professor(executor-strong,mid)
INFO:TIER_DROP:DEV COMPLEX dev-reviewer(top) -> rework(low)
WARN:PIPELINE_NOT_FOUND name=<expected>
WARN:STEP_UNRESOLVED pipeline=PLAN step=plan-writer-* kind=wildcard matches=2
SUMMARY:pipelines=12 steps=84 agents=70 pseudo=6 loops=6 waves=1 prewalk=3 inversions=0 drops=8 unresolved=6 warn=6
STATUS:SUCCESS
```

json mode emits ONLY: `{generated_utc, arch, source, pipelines:[{label,
steps:[{kind,name,model,role,tier,loop:{text,max}|null,wave:[names]|null}],
prewalk:[{from,to,from_tier,to_tier}], tier_drops:[...]}], warnings:[],
summary:{...}}`

markdown mode: per pipeline `### <LABEL>` + fenced ```text block (same ASCII)
+ step table `| # | Step | Kind | Model | Role | Tier |` + `**Prewalk:**` /
`**Tier drops:**` bullet lists.

## Gates

| Gate | Effect |
|------|--------|
| `-Source deploy` + `-AgentsDir` together | BLOCK (exit 2) |
| `-Format` / `-Source` value outside the allowed set | BLOCK (exit 2) |
| ARCHITECTURE.md missing or unreadable | BLOCK (exit 2) |
| Anchors `## 2. Pipelines` / `## Model Roles` absent | BLOCK (exit 2) |
| Agents dir missing or empty | BLOCK (exit 2) |
| `-Pipeline` matched no parsed label | BLOCK (exit 2) |
| WARN/INFO (PIPELINE_NOT_FOUND, STEP_UNRESOLVED, STEP_NO_MODEL, ROLE_UNMAPPED, PREWALK_INVERSION) | advisory (exit code unchanged) |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Diagrams rendered (WARN/INFO allowed) |
| 2 | Usage/environment error (bad flags, ARCHITECTURE.md or agents dir missing, `## 2. Pipelines` / `## Model Roles` anchors absent, `-Pipeline` matched nothing) |

No exit 3 — visualization does not gate (WARN:PREWALK_INVERSION is advisory;
authoritative enforcement is consistency-checker Check 11).

## Hard rules

- STRICTLY READ-ONLY: never writes, fixes or deletes anything
- No LLM, no network — deterministic parsing/rendering only (seconds)
- OUTPUT IS ASCII-ONLY (`->`, `==>`, `+`, `|`): unicode arrows U+2192/U+2225
  are INPUT syntax, never printed (console cp866/cp1251 safety); script
  SOURCES contain no unicode literals — `\u2192`/`\u2225` escapes only
- Agent/model names byte-exact (`GLM-5.3 (res)`, `Kimi K3`); `[regex]::Escape()`/
  `re.escape()` in every pattern; token-exact step matching (no fuzzy)
- Displayed model = model key WITHOUT the provider prefix (split on first `/`);
  frontmatter is the only model authority
- Excluded-span headings and the expected-pipeline label list are script-top
  constants — update them together with this SKILL.md when §2 legitimately changes
- WARN/INFO never change the exit code
- PS and PY mirrors produce byte-identical diagrams (output parity)
- Never edit user-level skills
