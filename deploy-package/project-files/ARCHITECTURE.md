# Architecture Requirements

This file is the single source of truth for the OpenCode dual-primary-agent architecture. All other files must be consistent with this document.

## 1. Routing Tables

### orchestrator Whitelist (25 agents)

| # | Agent Name | Role |
|---|------------|------|
| 1 | orchestrator-identity-probe | Identity verification |
| 2 | dev-reviewer | Code review |
| 3 | dev-professor | Development guidance |
| 4 | mcp-github | GitHub operations |
| 5 | worker | Simple development tasks |
| 6 | bugfix | Bug fixing |
| 7 | rework | Rework on feedback |
| 8 | mcp-read | File reading |
| 9 | utility | Syntax checking, formatting |
| 10 | bugfix-triage | Initial bug analysis |
| 11 | plan-bug | Bug fix planning |
| 12 | devops-agent | DevOps operations |
| 13 | devops-reviewer | DevOps review |
| 14 | dev-planner | Development planning |
| 15 | mcp-search | Web search |
| 16 | docs-writer | Documentation writing |
| 17 | summarizer | Content summarization |
| 18 | execute-bug | Bug fix implementation |
| 19 | consistency-checker | Architecture consistency validation |
| 20 | view-image | Image analysis |
| 21 | docs-planner | Documentation planning (DOCS DEEP) |
| 22 | generate-image | Image generation (Gemini) |
| 23 | generate-image-gpt | Image generation (GPT/DALL-E) |
| 24 | git-commit | Gated conventional git commits |
| 25 | advisor | Step-boundary advisory reviewer (severity-tagged, read-only) |

### plankestrator Whitelist (10 agents)

| # | Agent Name | Role |
|---|------------|------|
| 1 | plankestrator-identity-probe | Identity verification |
| 2 | plan-writer-simple | Simple planning |
| 3 | plan-writer-complex | Complex planning |
| 4 | plan-reviewer-simple | Simple plan review |
| 5 | plan-reviewer-complex | Complex plan review |
| 6 | research-writer-simple | Simple research |
| 7 | research-writer-complex | Complex research |
| 8 | research-reviewer | Research review |
| 9 | devops-readonly | DevOps read-only |
| 10 | view-image | Image analysis |

### Agent Count Summary

| Primary Agent | Whitelist Count | Total (primary + whitelist) |
|---------------|-----------------|-----------------------------|
| orchestrator | 25 | 26 (orchestrator + 25 subagents) |
| plankestrator | 10 | 11 (plankestrator + 10 subagents) |
| **Grand Total** | **35** | **37** |

Note: 35 whitelist entries (view-image shared by both primaries) = 34 unique whitelisted subagents (incl. advisor — a step-boundary reviewer inside DEV COMPLEX / BUGFIX DEEP pipelines), PLUS scout — a subagent OUTSIDE both routing tables (never a pipeline step; called only internally by whitelisted subagents via their own permission.task allowlists). 35 unique subagents + 2 primary agents = 37 unique agents total.

### Shared Utility Agents

view-image is a shared utility agent available to BOTH primary agents. It is listed in BOTH routing tables (orchestrator: position 20 of 25; plankestrator: position 10 of 10) and granted `task.view-image: allow` in both permission blocks in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.

## Subagent Models

| Agent | Model |
|-------|-------|
| worker | bifrost-litellm/MiniMax-M3 |
| bugfix-triage | bifrost-litellm/GLM-5.3-Flash (res) |
| bugfix | bifrost-litellm/QWEN3.7-plus |
| plan-bug | bifrost-litellm/GLM-5.3 (res) |
| execute-bug | bifrost-litellm/MiniMax-M3 |
| dev-planner | bifrost-litellm/qwen3.8-max |
| dev-professor | bifrost-litellm/GLM-5.3 (res) |
| dev-reviewer | bifrost-litellm/Kimi K3 |
| rework | bifrost-litellm/Kimi K3 |
| consistency-checker | bifrost-litellm/QWEN3.7-plus |
| advisor | bifrost-litellm/HY4 |
| docs-writer | bifrost-litellm/mimo-v2.5-pro |
| docs-planner | bifrost-litellm/aliyun/qwen3.8-flash |
| utility | bifrost-litellm/MiniMax-M3 |
| mcp-github | bifrost-litellm/MiniMax-M3 |
| mcp-read | bifrost-litellm/MiniMax-M3 |
| mcp-search | bifrost-litellm/MiniMax-M3 |
| summarizer | bifrost-litellm/MiniMax-M3 |
| devops-agent | bifrost-litellm/MiniMax-M3 |
| devops-reviewer | bifrost-litellm/qwen3.8-max |
| orchestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plankestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plan-writer-simple | bifrost-litellm/QWEN3.7-plus |
| plan-writer-complex | bifrost-litellm/qwen3.8-max |
| plan-reviewer-simple | bifrost-litellm/GLM-5.3 (res) |
| plan-reviewer-complex | bifrost-litellm/Kimi K3 |
| research-writer-simple | bifrost-litellm/mimo-v2.5-pro |
| research-writer-complex | bifrost-litellm/Kimi K3 |
| research-reviewer | bifrost-litellm/GLM-5.3 (res) |
| devops-readonly | bifrost-litellm/MiniMax-M3 |
| git-commit | bifrost-litellm/mimo-v2.5 |
| generate-image | bifrost-litellm/mimo-v2.5 |
| generate-image-gpt | bifrost-litellm/mimo-v2.5 |
| view-image | bifrost-litellm/MiniMax-M3 |
| scout | bifrost-litellm/mimo-v2.5 |

Note: primary agents (orchestrator, plankestrator) run on `bifrost-litellm/QWEN3.7-plus` and are documented in §Identity Lock Mechanism (v3), item 5 — not duplicated in the Subagent Models table.

## Model Roles (v5 — single source of truth, OMP model-roles analog)

Роли централизуют назначение моделей 37 агентам. Рантайм opencode НЕ поддерживает role-алиасы (`model:` во frontmatter литерален) — таблица является каноническим mapping'ом для: (1) массовых смен моделей (правка таблицы → синхронная правка frontmatter), (2) валидации consistency-checker (Check 11), (3) документации. Квота-aware fallback-цепочки — платформенное требование (см. `PLAN_LLM_FALLBACK.md`; статус: НЕ реализовано, требует поддержки рантайма/proxy).

| Role | Model | Tier | Agents |
|------|-------|------|--------|
| primary | bifrost-litellm/QWEN3.7-plus | mid | orchestrator, plankestrator |
| probe | bifrost-litellm/QWEN3.7-plus | mid | orchestrator-identity-probe, plankestrator-identity-probe |
| plan-strong | bifrost-litellm/qwen3.8-max | top | dev-planner, plan-writer-complex, devops-reviewer |
| plan-lite | bifrost-litellm/QWEN3.7-plus | mid | plan-writer-simple |
| plan-flash | bifrost-litellm/GLM-5.3 (res) | mid | plan-bug |
| review-strong | bifrost-litellm/Kimi K3 | top | dev-reviewer, rework, plan-reviewer-complex, research-writer-complex |
| review-lite | bifrost-litellm/QWEN3.7-plus | mid | consistency-checker, bugfix |
| review-flash | bifrost-litellm/GLM-5.3 (res) | mid | plan-reviewer-simple, research-reviewer |
| triage-flash | bifrost-litellm/GLM-5.3-Flash (res) | low | bugfix-triage |
| advisory | bifrost-litellm/HY4 | mid | advisor |
| executor-strong | bifrost-litellm/GLM-5.3 (res) | mid | dev-professor |
| executor-cheap | bifrost-litellm/MiniMax-M3 | low | worker, execute-bug, utility, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-readonly, view-image |
| docs | bifrost-litellm/mimo-v2.5-pro | low | docs-writer, research-writer-simple |
| docs-plan | bifrost-litellm/aliyun/qwen3.8-flash | low | docs-planner |
| micro | bifrost-litellm/mimo-v2.5 | low | git-commit, generate-image, generate-image-gpt, scout |

Контроль суммы: 2 primary + 35 subagents = 37 агентов; каждая строка Subagent Models (§выше) принадлежит ровно одной роли.

**Правила:**
1. **Prewalk-принцип (OMP):** в паре planner→executor роль planner'а ДОЛЖНА быть tier ≥ executor'а: plan-bug (plan-flash, mid) → execute-bug (executor-cheap, low); dev-planner (plan-strong, top) → dev-professor (executor-strong, mid); docs-planner (docs-plan, low) → docs-writer (docs, low). Инверсия запрещена.
2. Смена модели агента = правка этой таблицы + frontmatter `agents/*.md` + Subagent Models + MCP_SETUP Models Distribution (4 места; все — через consistency-checker Check 11).
3. Новые агенты получают роль из таблицы; новая роль добавляется только с обоснованием в CHANGELOG.
4. Миграция frontmatter на role-алиасы (`model: "@review-strong"`) — ЗАБЛОКИРОВАНА до поддержки рантаймом opencode (задокументированное платформенное требование, аналогично quota-aware fallback).

### Permission Notes

| Agent | Special Permissions | Reason |
|-------|-------------------|--------|
| worker | `bash: allow` | Implementation agent — needs bash for npm install, git operations, running tests, executing commands |
| bugfix | `bash: allow` | Bug fixing agent — needs bash for running tests, git operations |
| execute-bug | `bash: allow` | Bug fix implementation — needs bash for running tests, executing commands |
| rework | `bash: allow` | Rework agent — needs bash for running tests, git operations |
| plan-bug | `edit: allow` (`.md` only) | Bug fix planning — writes plan to `bug_plan.md` for execute-bug to read |
| docs-planner | `edit: allow` (`.md` only) | Documentation planning — writes plan to `docs_plan.md` for docs-writer to read |
| devops-reviewer | `read: allow` in addition to `bash: allow` | DevOps review — needs bash for running commands, read for checking files |
| devops-agent | `bash: allow` only | DevOps operations — needs bash for npm, docker, deployment commands |

### Worker Bash Permission Details

Worker is the implementation agent — it MUST have `bash: allow` to execute commands:

| Command Type | Examples |
|--------------|----------|
| npm operations | `npm install`, `npm run build`, `npm run test` |
| git operations | `git status`, `git add`, `git commit`, `git push` |
| file operations | `mkdir`, `touch`, `rm` |
| linting tools | `eslint`, `prettier`, `tsc` |
| test runners | `jest`, `vitest`, `pytest` |
| any CLI tools | Any command-line tool execution |

**Critical:** Without `bash: allow`, worker cannot implement changes — it would be unable to run tests, install dependencies, or execute any commands.


### Edit Permissions (plankestrator subagents)

**Important:** `write` is a TOOL NAME, not a permission key. The `edit` permission key controls the `edit`, `write`, `patch`, and `multiedit` tools. However, `"*": "deny"` does NOT just restrict to other file types — it REMOVES the `edit`/`write`/`patch`/`multiedit` tools entirely from the agent's toolset. Use `"*": "ask"` to restrict by glob while keeping tools available, paired with explicit `"*.md": "allow"` (or similar) to whitelist intended targets.

| Agent | Permission | Restriction |
|-------|------------|-------------|
| plan-bug | `edit: allow` (`.md` only) | Only .md files, writes bug_plan.md |
| plan-writer-simple | `edit: allow` (`.md` only) | Only .md files, user request required |
| plan-writer-complex | `edit: allow` (`.md` only) | Only .md files, user request required |
| plan-reviewer-simple | `edit: allow` (`.md` only) | Only .md files, user request required |
| plan-reviewer-complex | `edit: allow` (`.md` only) | Only .md files, user request required |
| research-writer-simple | `edit: allow` (`.md` only) | Only .md files, user request required |
| research-writer-complex | `edit: allow` (`.md` only) | Only .md files, user request required |
| research-reviewer | `edit: allow` (`.md` only) | Only .md files, user request required |
| devops-readonly | `edit: allow` (`.md` only) | Only .md files, user request required (backup) |

### Permission Authority

⚠️ IMPORTANT: `agents/*.md` is the authoritative source for agent definitions

**Markdown frontmatter is merged AFTER opencode.json and WINS on shared keys.**

Verified against opencode source (`packages/opencode/src/config/config.ts`):

```js
// 1. JSON config files load first:
yield* merge(Global.Path.config, global, "global")
// 2. Markdown agents load after, overwriting shared keys:
result.agent = mergeDeep(result.agent ?? {}, ConfigAgent.load(dir))
```

`mergeDeep` (remeda) — deep merge where source (markdown) overwrites target (JSON) on shared keys. Non-shared keys survive.

**Consequences:**

| Field | Authoritative location | Reason |
|-------|----------------------|--------|
| `model` | `agents/*.md` frontmatter | Overwrites JSON; `agent.*.model` removed from opencode.json |
| `prompt` | `agents/*.md` body | Overwrites JSON; `agent.*.prompt` removed from opencode.json |
| `permission` | Deep merge of JSON + frontmatter | JSON keeps `task` allowlist / serena / unity-mcp keys; frontmatter wins on shared keys (edit/write/bash) |
| `mode`, `temperature` | Frontmatter wins if present | Keep values in sync |

**Rule:** Never define `model` or `prompt` for an agent in opencode.json if that agent has a `.md` file — the JSON value is dead config and misleads.

**Example of the failure mode this prevents:** bugfix-triage once kept running QWEN3.7-plus after opencode.json was changed to GLM-5.3-Flash (res) — because the stale frontmatter `model:` silently won.

**Note:** `write` is NOT a permission key — it is a tool name. To allow/deny the `write` tool, use the `edit` permission key. `write: "*.md"` as a permission key is a DEAD KEY — it is silently ignored by opencode.

**Note:** plankestrator has `edit: deny` — it MUST delegate to subagents, never write directly.

### Primary Agent Tool Lockdown (v3)

Both `orchestrator` and `plankestrator` are locked down to prevent them from doing work themselves. The effective permissions are a **deep merge of opencode.json + `agents/*.md` frontmatter** (frontmatter wins on shared keys — see Permission Authority). Both sources must agree on the deny rules below; the plugin runtime checks are belt-and-suspenders.

| Tool | orchestrator | plankestrator | Reason |
|------|:---:|:---:|--------|
| `task` | ✅ allow | ✅ allow | Delegation to specialists (primary purpose) |
| `read` | ✅ allow | ✅ allow | Inspect ARCHITECTURE.md / AGENTS.md / existing plans |
| `glob` | ✅ allow | ✅ allow | Assess scope (1 file vs many) |
| `grep` | ✅ allow | ✅ allow | Find references to inform classification |
| `edit` | ❌ deny | ❌ deny | Worker / bugfix / plan-writer-* handles this |
| `write` | ❌ deny | ❌ deny | Worker / docs-writer handles this |
| `patch` | ❌ deny | ❌ deny | Same as edit |
| `bash` | ❌ deny | ❌ deny | devops-agent / worker / execute-bug handles this |
| `webfetch` | ❌ deny | ❌ deny | mcp-read / mcp-search handles this |
| `question` | ❌ deny | ❌ deny | Primary agents don't ask the user |
| `todowrite` | ❌ deny | ❌ deny | Primary agents don't manage todos |

**Defense in depth — this lock is enforced by 4 layers:**

1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
2. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
3. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
4. **Inspection gate v4 (plankestrator)** — plugin hard-blocks `read`/`grep`/`glob`: (a) after the first pipeline Task call (`⛔ INSPECTION AFTER PIPELINE START`), (b) beyond the inspection budget of 3 calls per session (`⛔ INSPECTION BUDGET EXHAUSTED`; the prompt tells the model max 2), (c) after self-work content markers (`## Findings`, `## Analysis`, `Executive Summary`, ...) were detected in plankestrator's own message. view-image and identity-probe Task calls are auxiliary — they do NOT count as pipeline start. Child (subagent) sessions do not reset the parent's lock (parentID guard); subagent tool calls are excluded from enforcement via `activeTaskDepth`.

**Why this exists:** orchestrator and plankestrator kept "doing things themselves" because the old config had `edit: "ask"`, `todowrite: "allow"`, `question: "allow"` for orchestrator, and `edit: { "*.md": "allow" }` for plankestrator — the model had action tools available and used them. v3 lockdown removes those tools from the model's toolset entirely.

**Restrictions enforced in agent prompts:**
- File type: ONLY `.md` (Markdown) files
- User request: ONLY when user explicitly asks to write/save
- Forbidden: Any non-.md files (code, config, etc.)

### Subagent Depth (`subagent_depth`)

`subagent_depth` — параметр opencode-core (top-level поле в `opencode.json`), ограничивающий максимальную глубину вложенности вызовов субагентов через Task tool. При превышении лимита ядро отклоняет попытку создать следующего субагента.

**Текущее значение:** `3` (задаётся в `~/.config/opencode/opencode.json`, строка 3, сразу после `$schema`; продублировано в `deploy-package/opencode.json`). Документация: <https://opencode.ai/docs/config>.

**Отличие от `activeTaskDepth` (плагин):**

| Механизм | Источник | Назначение |
|----------|----------|------------|
| `subagent_depth` | opencode-core | Жёсткий лимит вложенности: при `depth >= subagent_depth` Task tool отказывается создавать субагента |
| `activeTaskDepth` | `workflow-enforcement.ts` (плагин, v4) | Подавление enforcement: пока выполняется субагент (`activeTaskDepth > 0`), плагин пропускает tool calls — иначе Gate A блокировал бы `edit`/`write` у writer-агентов |

Плагин НЕ управляет лимитом вложенности — это ответственность ядра. Плагин лишь не вмешивается в работу субагентов, чтобы не нарушать их контракт.

**Цепочка вызовов (пример с depth-счётом):**

```
Уровень 0 (depth 0): primary — orchestrator / plankestrator
Уровень 1 (depth 1): research-writer-complex / plan-writer-complex / worker / bugfix / ...
Уровень 2 (depth 2): scout / mcp-search / mcp-read / mcp-github / devops-readonly
Уровень 3 (depth 3): (резерв; потолок — следующий Task будет отклонён ядром)
```

При `subagent_depth: 3` цепочка `primary → research-writer-complex → scout` помещается в лимит с запасом в один уровень. Любая попытка вызвать субагента на depth = 3 будет отклонена ядром opencode до старта сессии.

### Direct Write Instruction

All writer agents have a "Direct Write Instruction" section in their prompts:

- **Write directly** using `edit` permission (controls the `write` tool)
- **DO NOT call other agents** for file operations
- **DO NOT delegate** to devops-readonly or any other agent

devops-readonly is for READING only — use it to read files, but NEVER call it for writing.

### Plankestrator Delegation Rule

plankestrator is a pure orchestrator — it MUST ALWAYS delegate to subagents:

| Task Type | Subagent to Call |
|-----------|------------------|
| PLAN (simple) | `plan-writer-simple` |
| PLAN (complex) | `plan-writer-complex` |
| RESEARCH (simple) | `research-writer-simple` |
| RESEARCH (complex) | `research-writer-complex` |
| RESEARCH+PLAN | `research-writer-*` → `plan-writer-*` |

**File output handling:**
- If user requests "write plan to X.md", plankestrator passes instruction to subagent
- Subagent (with `edit: allow` for .md) handles the actual file writing
- plankestrator NEVER writes files directly

**Inspection limits (v4):** plankestrator may call `read`/`grep`/`glob` ONLY on Turn 1 and ONLY to classify (prompt limit: max 2 calls; plugin hard limit: `INSPECTION_BUDGET = 3`). After the first pipeline Task call, any inspection throws. Type and complexity are classified from the REQUEST TEXT (keywords; number of questions/topics/objects), not from files. RESEARCH+PLAN is always COMPLEX. Context-heavy investigation is delegated to `devops-readonly` via Task. Plan/research CONTENT in plankestrator's own message (headings like `## Findings`, `## Analysis`) is detected by the plugin and blocks further inspection.

## 2. Pipelines

### Pipeline Notation

Pipelines are dependency graphs (DAG); a linear chain is the special case. Notation:

| Element | Syntax | Semantics |
|---------|--------|-----------|
| Sequential step | `a → b` | b starts after a completes |
| Parallel wave | `[a ∥ b ∥ c]` | a, b, c launch simultaneously (multiple Task calls in ONE message); branches MUST be mutually independent |
| Barrier | `→ barrier →` | synchronization point: the next stage starts only after ALL wave results have arrived |
| Rework loop | `[rework loop: rework → consistency-checker, max 3]` | conditional repetition of consistency-checker after rework (or worker) applies fixes — max 3 iterations |

**Scope rule:** top-level pipelines (PIPELINE TABLE in `agents/orchestrator.md` / `agents/plankestrator.md`; the `pipeline` JSON field) remain LINEAR `string[]` — one element = one Task call by the primary agent. Parallel waves exist ONLY INSIDE a pipeline element: a subagent's own Task fan-out (e.g. research-writer-complex scout wave). Every wave branch must come from the SUBAGENT's own `permission.task` allowlist (frontmatter + opencode.json), not from the primary's routing table.

Full-graph example (RESEARCH COMPLEX):

```
plankestrator → research-writer-complex → research-reviewer
                │ (internal DAG)
                └─ decompose → [mcp-search ∥ mcp-read ∥ mcp-github] → barrier (rank + brief) → synthesis → RESEARCH.md
```

### BUGFIX (SIMPLE)

```
bugfix-triage → worker → utility
```

### BUGFIX DEEP

```
bugfix-triage → plan-bug (writes bug_plan.md) → execute-bug (reads bug_plan.md) → advisor → dev-reviewer → rework → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

**Two-stage pipeline decision (mandatory):** the orchestrator NEVER guesses SIMPLE vs DEEP itself. For any BUGFIX it first sends `["bugfix-triage"]` with `complexity: null`. When triage returns its verdict, the orchestrator extends the pipeline ONCE:

- `TRIAGE_RESULT: SIMPLE` → continue `["worker", "utility"]`
- `TRIAGE_RESULT: DEEP` → continue `["plan-bug", "execute-bug", "advisor", "dev-reviewer", "rework", "consistency-checker", "utility"]`

**Single source of truth for pipeline selection:** the PIPELINE TABLE in each primary agent's own `.md` file (`agents/orchestrator.md` for BUGFIX/DEVOPS/DEV/DOCS, `agents/plankestrator.md` for PLAN/RESEARCH/RESEARCH+PLAN). Each table must stay identical to the corresponding section in this file. (The inline `prompt` field formerly present in opencode.json was removed — markdown wins per the merge order documented above.)

**Plan file:** `plan-bug` writes the bug fix plan to `bug_plan.md` in the project root. `execute-bug` reads this file before implementing. The orchestrator MUST include "Write the plan to bug_plan.md" in the plan-bug prompt and "Read bug_plan.md" in the execute-bug prompt.

**Prewalk pattern (v5, OMP prewalk analog):** one-shot handoff expensive→cheap at the planning/implementation boundary. `plan-bug` runs on the MID-tier planner model (`GLM-5.3 (res)`, tier plan-flash) and writes a SELF-CONTAINED `bug_plan.md`; `execute-bug` runs on the CHEAP executor model (`MiniMax-M3`, tier executor-cheap) and mechanically applies the plan in a fresh context. Escape hatch: `execute-bug` sets `plan_gap: true` in its JSON when the plan turns out incomplete — downstream dev-reviewer/consistency-checker escalate (consistency-checker `escalate_to: "execute-bug"` remains available). Same philosophy in DEV COMPLEX: dev-planner (plan-strong) > dev-professor (executor-strong). Rationale and source: `RESEARCH_OMP_FEATURES.md` P0-2, OMP `docs/prewalk.md`.

**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV SIMPLE

DEV SIMPLE has two variants depending on whether a plan exists:

| Variant | Flow | When to Use |
|---------|------|-------------|
| DEV SIMPLE (without plan) | `worker → utility` | plan_exists=false — direct implementation and validation |
| DEV SIMPLE (with plan) | `worker → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility` | plan_exists=true — plan-validated implementation with rework loop |

**Decision rule:** If plan_exists=true, use the "with plan" variant. Otherwise, use the "without plan" variant.

**Rework loop:** If consistency-checker finds critical issues, task returns to worker for fixes, then consistency-checker validates again. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV COMPLEX

```
dev-planner → dev-professor → advisor → dev-reviewer → rework → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes, then consistency-checker validates again. Loop repeats up to 3 iterations.

**Advisor step (v5, OMP Advisor Watchdog analog — step-boundary):** `advisor` (HY4, strictly read-only: read/grep/glob + read-only serena) observes the implementation result between pipeline steps and returns severity-tagged notes (`nit|concern|blocker`, contract — §3 Reviewer Severity Field). Mid-turn intervention is NOT possible (our agents are atomic within a step) — advisor fires only at step boundaries. Safeguards: emission guard (max 4 non-blocker notes per run, session dedup, empty-phrase filter — plugin v5 + advisor prompt), immuneTurns analog (`NIT_ONLY_MODE` for 3 pipeline steps after a consumed blocker — concern/blocker notes downgrade to nit), separate cost accounting (advisor ≈ 1 extra model call per step; logged in plugin + orchestrator acks). Advisor never re-orders the pipeline; blocker → ⚠️ ack + notes to dev-reviewer/rework; persistence after 3rd rework iteration → failure report.

### DEV SUPERCOMPLEX

```
PER PLAN STEP (repeated for each step in the step list):
  dev-planner → dev-professor → dev-reviewer → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

Super-complex development tasks with a large pre-existing plan (>3 steps) or huge volume of work. The orchestrator executes the full review/consistency/syntax chain **for every step** of the plan — never one pass over the whole task.

**Trigger conditions:**
- Explicit user request (e.g. "use SUPERcomplex", "run the super-complex pipeline"), OR
- A plan exists with more than 3 steps AND a huge volume of work

**Step list determination (once, before the first pipeline step; strict priority):**
1. **User listed the steps explicitly** (e.g. "Implement P0-1, then P0-2, then P0-3") → the steps are used verbatim.
2. **The plan/research file has a clear step structure** — headings like `## P0-1`, `## Phase 1`, `## Шаг 1`, `### P0-1` → the orchestrator extracts the steps via its ONE allowed classification `read` of the plan file, or — if it has not read the file — via a single `mcp-read` Task call listing the step headings (`mcp-read` is the orchestrator's whitelisted file-reading agent; `devops-readonly` is NOT callable by orchestrator — it belongs to plankestrator's routing table).
3. **No step list anywhere** → ONE `dev-planner` call in DECOMPOSITION mode (`MODE: DECOMPOSITION` in the Task prompt): dev-planner analyzes the research file and returns JSON `{"decomposition": true, "steps": [{"id": "...", "title": "...", "description": "..."}, ...]}` WITHOUT writing `dev_plan.md`.

**Per-step chain:** For each step, `dev-planner` writes the detailed plan for THIS step to `dev_plan.md`, `dev-professor` reads the plan file, critically reviews it, then implements the step, `dev-reviewer` reviews the code, `consistency-checker` validates architecture, then `utility` runs the syntax check before the orchestrator advances to the next step.

**Rework loop:** If consistency-checker finds critical issues within a step, the task returns to `rework` for fixes, then consistency-checker validates again. Loop repeats up to 3 iterations per step. If a step passes, the orchestrator advances to the next plan step and repeats the chain.

**Note:** This pipeline overrides the standard "PLAN EXISTS OVERRIDE" complexity rule — when the plan is large (>3 steps), complexity is classified as `SUPERCOMPLEX` instead of `SIMPLE`.

### DEVOPS

```
devops-agent → devops-reviewer
```

### DOCS

```
DOCS SIMPLE: docs-writer → utility
DOCS DEEP:   docs-planner (writes docs_plan.md)
           → docs-writer (reads docs_plan.md)
           → dev-reviewer
           → rework
           → consistency-checker
           → [rework loop: rework → consistency-checker, max 3]
           → utility
```

### Auto-DOCS Hook (BUGFIX / DEV pipelines)

After the final `utility` step of BUGFIX/DEV pipelines, check the JSON output of the implementation agent (execute-bug, dev-professor, worker).

**Trigger:** call `docs-writer → utility` if implementation agent's JSON output has `requires_docs_update: true`.

Set `requires_docs_update: true` if ANY of these were modified:
- `bug_plan.md` or `dev_plan.md` files
- Any `*.md` file (README, ARCHITECTURE, docs/, CHANGELOG)
- Public API (heuristic: public class/method/interface, signature changes)
- Significant docstrings or code comments on public APIs

**Pipelines WITH hook** (final utility → if hook → docs-writer → utility):
- BUGFIX SIMPLE / DEEP
- DEV SIMPLE / COMPLEX / SUPERCOMPLEX

**Pipelines WITHOUT hook** (no docs trigger):
- DEVOPS (deployments don't affect docs)
- DOCS (recursive — would loop forever)
- PLAN, RESEARCH (out of orchestrator's scope)

### PLAN

```
plan-writer-* → plan-reviewer-*
```

### RESEARCH

```
research-writer-* → research-reviewer
```

**Internal fan-out (research-writer-complex):** the top-level pipeline stays linear, but research-writer-complex fans out INTERNALLY — independent sub-questions are dispatched as ONE parallel Task wave to scout agents (mcp-search / mcp-read / mcp-github / devops-readonly / scout — all on cheap models); dependent sub-questions form follow-up waves:

```
research-writer-complex (internal DAG):
  decompose → [mcp-search ∥ mcp-read ∥ mcp-github ∥ devops-readonly ∥ scout] → barrier (rank + brief) → synthesis (Kimi K3) → RESEARCH.md
```

The wave and the barrier are prompt-level behavior of the writer agent. The plugin and plankestrator's PIPELINE TABLE are NOT affected: enforcement is suppressed inside subagent sessions (`activeTaskDepth > 0`), and task-permissions for all scouts are already granted in opencode.json + frontmatter (verified 2026-09-19).

### Wave → Barrier → Synthesis Pattern

A **barrier** is a synchronization point: the next stage starts only after ALL results of a parallel wave have arrived. In this architecture the barrier is NOT a separate agent — it is a structural property of the Task tool (all parallel Task calls issued in one message return before the agent's next turn) plus an explicit prompt-level step of the writer agent.

Implementation (research-writer-complex): wave results → rank by relevance/reliability → internal brief (key facts, contradictions, gaps) → synthesis from the brief on the strong model. "Pointer, not transcript": the report references sources and the output file, raw scout transcripts never leave the writer's context.

**Decision record (2026-09-19):** a separate `summarizer` barrier agent (Option A) was DEFERRED — parallel Task calls already provide a free structural barrier, a summarizer hop would require passing raw wave transcripts in its prompt (violates pointer-not-transcript), and ranking is inseparable from synthesis, which must run on the strong model. Escalation path if pilots show context overflow: grant `"summarizer": "allow"` in research-writer-complex task permissions and pass waves via a file pointer.

## 3. JSON Validation Fields

### orchestrator Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"orchestrator"` |
| `type` | string \| null | `"BUGFIX"`, `"DEVOPS"`, `"DEV"`, `"DOCS"`, `null` |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `"DEEP"`, `"SUPERCOMPLEX"`, `null` |
| `plan_exists` | boolean \| null | `true`, `false`, `null` |
| `plan_source` | string \| null | description or `null` |
| `goal` | string | one sentence description |
| `next_agent` | string \| null | agent name from whitelist or `null` |
| `pipeline` | string[] | array of agent names (each from the primary's whitelist — see §2 Pipeline Notation) or `[]` |

### plankestrator Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"plankestrator"` |
| `state` | string | `"CLASSIFY"`, `"EXECUTE"`, `"REVIEW"`, `"COMPLETE"` |
| `type` | string \| null | `"PLAN"`, `"RESEARCH"`, `"RESEARCH+PLAN"`, `null` |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `null` |
| `goal` | string | one sentence description |
| `next_agent` | string \| null | agent name from whitelist or `null` |
| `pipeline` | string[] | array of agent names (each from the primary's whitelist — see §2 Pipeline Notation) or `[]` |

### consistency-checker Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"consistency-checker"` |
| `checks_performed` | number | integer |
| `issues_found` | number | integer |
| `issues_fixed` | number | integer |
| `issues_unfixable` | number | integer |
| `details` | array | array of check result objects |
| `files_modified` | array | list of file paths |
| `escalate_to` | string \| null | `"dev-reviewer"` \| `"rework"` \| `"worker"` \| `"execute-bug"` \| `null` |
| `severity` | string | `"nit"` \| `"concern"` \| `"blocker"` (mandatory; PASS → `"nit"`) |

### escalate_to Field — Expanded Values

The `escalate_to` field in consistency-checker output determines which agent receives the task when issues are found.

| Value | When to Use | Pipeline Context |
|-------|-------------|------------------|
| `"dev-reviewer"` | Issues require architectural review or design decisions | DEV COMPLEX, BUGFIX DEEP (before rework) |
| `"rework"` | Issues are concrete and can be fixed by applying feedback | DEV COMPLEX (after rework), BUGFIX DEEP (after rework), DEV PLAN EXISTS |
| `"worker"` | Issues are simple implementation fixes | DEV PLAN EXISTS (simple rework loop) |
| `"execute-bug"` | Issues are bug-specific and require targeted bug fix | BUGFIX DEEP (if rework cannot fix) |
| `null` | No escalation needed (consistency-checker passed) | All pipelines |

**Decision logic for consistency-checker:**
```
if issues_found == 0:
    escalate_to = null
elif issues are architectural/design-level:
    escalate_to = "dev-reviewer"
elif issues are concrete fixable items and pipeline has rework agent:
    escalate_to = "rework"
elif issues are simple implementation fixes:
    escalate_to = "worker"
elif issues are bug-specific:
    escalate_to = "execute-bug"
else:
    escalate_to = "dev-reviewer"  # default fallback
```

### Reviewer Severity Field (v5 — OMP emission-guard analog)

Reviewer subagents (`dev-reviewer`, `consistency-checker`, `advisor` — см. §2 Advisor Step) tag their final JSON with a mandatory `severity` field. Source: `RESEARCH_OMP_FEATURES.md` P0-1 (OMP Advisor Watchdog severity semantics: nit = aside, concern = steer, blocker = triggered turn).

| Severity | Канал (наш аналог) | Эффект в пайплайне |
|----------|--------------------|--------------------|
| `nit` | aside — логируется | НЕ триггерит rework; после dev-reviewer (все findings исправлены) шаг `rework` ПРОПУСКАЕТСЯ |
| `concern` | steer — rework-loop | триггерит rework → consistency-checker (max 3 итерации) |
| `blocker` | triggered turn | немедленный rework + `⚠️ BLOCKER` в ack orchestrator'а; персистенция после 3-й итерации → failure report пользователю |

**Rules:**
- Fail-closed: отсутствующее/невалидное `severity` трактуется orchestrator'ом как `concern`.
- Emission guard (plugin v5, warn-only): дедупликация текстов замечаний между итерациями rework-loop (session-scoped, нормализация lowercase+NFKC+схлопывание не-алфанум); фильтр пустых фраз (`lgtm`, `no issues`, `nothing to add`, …); бюджет **max 4 non-blocker findings на update** (blocker освобождён от бюджета).
- Плагин не блокирует вывод субагентов (enforcement в субсессиях подавлен при `activeTaskDepth > 0`) — severity-валидация логируется как warn/error; потребление — промпт-уровень orchestrator'а.
- Поле НЕ входит в `REQUIRED_JSON_FIELDS` primary-агентов (валидация primary не затрагивается).

### File-Pointer Fields (optional, subagent JSON output)

Writer subagents that write their work product to a file MUST report a file pointer in their final JSON output ("pointer, not transcript" pattern — the same protection Anthropic describes against game-of-telephone). Reviewer subagents MUST check for the pointer and read the file instead of relying on conversation context.

| Field | Type | Emitted by | Consumed by | Companion fields |
|-------|------|-----------|-------------|------------------|
| `plan_file` | string \| null | plan-writer-simple, plan-writer-complex | plan-reviewer-simple, plan-reviewer-complex | `plan_written: boolean`, `next_action: string` |
| `research_file` | string \| null | research-writer-simple, research-writer-complex | research-reviewer | `research_written: boolean`, `next_action: string` |

**Rules:**
- Fields are OPTIONAL — emitted only when the user requested file output. Absent/null means "the work product is in the response body".
- They are NOT part of `REQUIRED_JSON_FIELDS` for primary agents — the plugin validates primary-agent JSON only (subagent messages are skipped while `activeTaskDepth > 0`). File-pointer fields are enforced at the PROMPT level: writer emits, reviewer consumes.
- The pointer value is a path string only — never paste plan/research content into the JSON.
- Same-pattern fixed-name file pointers in orchestrator pipelines (passed via Task prompts, not JSON fields): `bug_plan.md` (plan-bug → execute-bug), `dev_plan.md` (dev-planner → dev-professor), `docs_plan.md` (docs-planner → docs-writer).

## 4. MCP Servers

All MCP servers are configured in `opencode.json` under the `mcp` section. Three Z.AI servers are proxied through Bifrost LiteLLM.

| Server Name | MCP Tool Prefix | Purpose |
|-------------|-----------------|---------|
| zai_zread | `zai_zread_` | GitHub repository reading: `zai_zread_search_doc`, `zai_zread_get_repo_structure`, `zai_zread_read_file` |
| zai_web_search | `zai_web_search_` | Web search: `zai_web_search_web_search_prime` |
| zai_web_reader | `zai_web_reader_` | URL content reading: `zai_web_reader_webReader` |
| serena | `serena_` | Code symbol operations: `find_symbol`, `rename_symbol`, etc. |
| unity-mcp | `unity-mcp.*` | Unity Editor operations: `manage_gameobject`, `manage_scene`, etc. |

### Usage Rules

- Use `zai_web_search` for all web searches — do NOT use `webfetch`
- Use `zai_web_reader` for reading URL content — do NOT use `webfetch`
- Use `zai_zread` tools for GitHub repositories — do NOT use `webfetch` or manual browsing

### MCP Proxy Architecture

All three Z.AI MCP servers (`zai_zread`, `zai_web_search`, `zai_web_reader`) are routed through Bifrost LiteLLM at `https://hcbifrost.herocraft.com/litellm/`. Authentication uses a single `LITELLM_API_KEY` environment variable shared with the LLM provider.

### Serena MCP Rules

**⚠️ MANDATORY: Serena tools are PRIMARY for code operations**

| Task | PRIMARY (Serena) | SECONDARY (Built-in) |
|------|------------------|---------------------|
| Find symbol by name | `serena_find_symbol` | grep (fallback) |
| Find all usages | `serena_find_referencing_symbols` | grep (fallback) |
| File structure overview | `serena_get_symbols_overview` | read (fallback) |
| Rename symbol | `serena_rename_symbol` | edit (fallback) |
| Delete symbol | `serena_safe_delete_symbol` | edit (fallback) |
| Replace symbol body | `serena_replace_symbol_body` | edit (fallback) |
| Insert after symbol | `serena_insert_after_symbol` | edit (fallback) |

**DO NOT use built-in tools (grep, read, glob, edit) for symbol operations — USE Serena tools MAXIMALLY ALWAYS**

### unity-mcp Rules

**⚠️ MANDATORY: unity-mcp is PRIMARY for Unity operations — use it MAXIMALLY ALWAYS**

| Task | unity-mcp Tool | Do NOT Use |
|------|----------------|------------|
| Create GameObject | `unity-mcp_manage_gameobject` | edit (manual) |
| Modify GameObject | `unity-mcp_manage_gameobject` | edit (manual) |
| Create/Save Scene | `unity-mcp_manage_scene` | bash (manual) |
| Create C# Script | `unity-mcp_create_script` | write (manual) |
| Edit C# Script | `unity-mcp_manage_script` | edit (manual) |
| Import Assets | `unity-mcp_manage_asset` | bash (manual) |
| Read Console Logs | `unity-mcp_read_console` | read (log files) |
| Validate Scripts | `unity-mcp_validate_script` | bash (manual) |

**unity-mcp tools → auto-approved → agent can use immediately**
**Built-in tools for Unity → asks user → nudges agent to use unity-mcp**

**DO NOT use built-in tools (edit, write, bash) for Unity operations — USE unity-mcp tools MAXIMALLY ALWAYS**

**Prerequisites:**
- Unity 2021.3 LTS or later
- Python 3.10+ and uv installed
- Unity MCP package from CoplayDev: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
- Unity Editor must be running with MCP server started

## unity-mcp Permissions

### ALL Agents Have unity-mcp Access (exceptions: scout, advisor)

unity-mcp is available for ALL agents, not just orchestrator and plankestrator.

| Agent Category | unity-mcp Permission | Reason |
|----------------|---------------------|--------|
| Primary agents | `unity-mcp.*: allow` | orchestrator, plankestrator route Unity tasks |
| Implementation agents | `unity-mcp.*: allow` | worker, bugfix, execute-bug, rework implement Unity changes |
| Development agents | `unity-mcp.*: allow` | dev-professor, dev-reviewer, dev-planner guide Unity development |
| Validation agents | `unity-mcp.*: allow` | consistency-checker, utility, docs-writer validate Unity code |
| DevOps agents | `unity-mcp.*: allow` | devops-agent, devops-reviewer, bugfix-triage, plan-bug manage Unity builds |
| MCP agents | `unity-mcp.*: allow` | mcp-github, mcp-read, mcp-search, summarizer read Unity content |
| Planning agents | `unity-mcp.*: allow` | plan-writer-*, plan-reviewer-*, research-writer-*, research-reviewer plan Unity features |
| Read-only agents | `unity-mcp.*: allow` | devops-readonly reads Unity DevOps info |
| Advisory agent | ❌ deny | advisor is strictly read-only (read/grep/glob + read-only serena); unity-mcp tools are mutating — excluded like scout |

### unity-mcp Tools Available

All agents can use these unity-mcp tools:
- `unity-mcp_manage_gameobject` — create, find, modify, delete GameObjects
- `unity-mcp_manage_scene` — load, save, create scenes, query hierarchy
- `unity-mcp_manage_asset` — asset management operations
- `unity-mcp_create_script` — create C# scripts
- `unity-mcp_delete_script` — delete C# scripts
- `unity-mcp_manage_script` — CRUD operations on C# scripts
- `unity-mcp_script_apply_edits` — advanced script editing
- `unity-mcp_apply_text_edits` — apply text edits to C# scripts
- `unity-mcp_validate_script` — validate C# scripts
- `unity-mcp_manage_shader` — CRUD operations on shader files
- `unity-mcp_read_console` — read/clear Unity Editor console logs
- `unity-mcp_manage_editor` — control/query Editor state, Tags, Layers
- `unity-mcp_manage_components` — add/remove/set properties on components
- `unity-mcp_manage_prefabs` — manage Unity Prefab assets
- `unity-mcp_manage_material` — manage Unity materials
- `unity-mcp_manage_animation` — manage Unity animation
- `unity-mcp_manage_vfx` — manage ParticleSystem, VisualEffect
- `unity-mcp_manage_camera` — manage cameras (Unity Camera + Cinemachine)
- `unity-mcp_manage_build` — manage Unity player builds
- `unity-mcp_manage_packages` — manage Unity packages
- `unity-mcp_manage_physics` — manage physics settings, collision matrix
- `unity-mcp_manage_ui` — manage Unity UI Toolkit
- `unity-mcp_manage_graphics` — manage rendering graphics
- `unity-mcp_manage_probuilder` — manage ProBuilder meshes
- `unity-mcp_manage_profiler` — Unity Profiler session control
- `unity-mcp_batch_execute` — batch execute (10-100x faster)
- `unity-mcp_unity_docs` — fetch official Unity documentation
- `unity-mcp_unity_reflect` — inspect Unity's live C# API

## 5. Identity Probe Whitelists

| Primary Agent | Allowed Probe | Denied Probe |
|---------------|---------------|--------------|
| orchestrator | `orchestrator-identity-probe` ✅ | `plankestrator-identity-probe` ❌ |
| plankestrator | `plankestrator-identity-probe` ✅ | `orchestrator-identity-probe` ❌ |

### Probe Procedure (legacy — superseded by Identity Lock v3)

```
Step 0 — IDENTITY PROBE (MANDATORY FIRST STEP):
1. Attempt to call orchestrator-identity-probe
2. If SUCCESS → You are orchestrator → Output identity verification
3. If DENIED → Attempt to call plankestrator-identity-probe
4. If SUCCESS → You are plankestrator → Output identity verification
5. If DENIED → IDENTITY ERROR → STOP
```

### Identity Lock Mechanism (v3) — REPLACES Probe Procedure

To prevent orchestrator↔plankestrator confusion mode, the system uses a **machine-asserted identity lock** at session start:

1. **Session start** — `workflow-enforcement.ts` reads `session.agent` from the `session.created` event (priority order: explicit `agent` field → alternate field names → title → description). If it identifies `orchestrator` or `plankestrator`, it sets `identityLocked = true` and records `lockedAgentName`. The agent cannot be re-bound after this point.
2. **RUNTIME IDENTITY block** — both primary agent prompts (`agents/orchestrator.md`, `agents/plankestrator.md`) start with an explicit `OPENCODE_AGENT_NAME = ...` block asserted by opencode (machine-injected, not self-claimed). The agent MUST check this block before any output; if it contradicts the agent file, the agent must refuse.
3. **Identity drift = hard error** — once `identityLocked = true`, any JSON output where `agent` does not match `lockedAgentName` is logged as `error` (not `warn`) and the agent's `currentAgent` value is NOT updated. Downstream Task calls are still validated against the locked routing table.
4. **Forbidden vocabulary check** — the plugin greps locked-agent message text for terminology that belongs to the other primary agent (e.g. orchestrator message containing "I am plankestrator" or "## PLAN"). Violations are logged as `error`.
5. **Model** — both primary agents run on `bifrost-litellm/QWEN3.7-plus` (Qwen 3.7 Plus via the bifrost-litellm provider). Other agents use their own providers as listed in the Subagent Models table above.

**Why the probe procedure is now legacy:** the probe relied on the agent following instructions in its own prompt — a self-claim. The v3 lock reads identity from opencode's session metadata (which opencode controls, not the model) and from the system-prompt-injected RUNTIME IDENTITY block. Self-claims are no longer authoritative.

### Session Naming Convention

Give every new session a clear name. The plugin uses the title as a fallback for identity detection if `session.agent` is not available. Recommended patterns:

- `orchestrator — fix login bug`
- `orchestrator — add user settings page`
- `plankestrator — plan auth refactor`
- `plankestrator — research state-management libs`

Avoid generic names like `New session` or `Untitled`. They prevent the plugin from locking identity early.

## 6. Outdated Terms

These terms must NOT appear in any agent .md files, plugin code, or configuration:

| Term | Status | Replacement |
|------|--------|-------------|
| `ensemble` | REMOVE | Use `pipeline` or `workflow` |
| `team_*` (any team-prefixed name) | REMOVE | No replacement — legacy concept |
| `4747` | REMOVE | No replacement — debug artifact |

## 7. Primary Agent Roles

| Agent | Handles | Workflows |
|-------|---------|-----------|
| orchestrator | Operational and execution tasks | BUGFIX, DEVOPS, DEV, DOCS |
| plankestrator | Planning and research tasks | PLAN, RESEARCH, RESEARCH+PLAN |

Agents do NOT call each other — the user must manually switch between them.

## 8. File Locations

### Configuration

| Item | Path |
|------|------|
| Main Config | `~/.config/opencode/opencode.json` |
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Agents | `~/.config/opencode/agents/*.md` |
| Architecture (this file) | Project root `ARCHITECTURE.md` |

### Data Storage

| Item | Path | Format |
|------|------|--------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | JSON |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Various |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | JSON |
| Logs | `~/.local/share/opencode/log/` | `.log` files |

### Documentation

| Item | Location |
|------|----------|
| Project Rules | `AGENTS.md` (project root) |
| Plugin Docs | `PLUGIN.md` (project root) |
| Identity Probes | `identity_probe_section.md` (project root) |
| MCP Setup | `MCP_SETUP.md` (project root) |

- Reviewer context (per-audience, OMP WATCHDOG.md analog): `REVIEW_CONTEXT.md` — project root + user-level `~/.config/opencode/REVIEW_CONTEXT.md`; loaded ONLY by reviewer agents (dev-reviewer, consistency-checker, devops-reviewer, plan-reviewer-*, research-reviewer, advisor); plugin v5 injects a pointer into their Task prompts

### Per-Audience Context Files (v5, OMP WATCHDOG.md analog)

Конвенция: инструкции для конкретного класса агентов хранятся ОТДЕЛЬНО от общего AGENTS.md и подключаются только в промпты этого класса. Действующие файлы: `REVIEW_CONTEXT.md` (reviewer-агенты; два уровня — project root и user-level `~/.config/opencode/`). Будущие кандидаты: `PLAN_CONTEXT.md` (planner-агенты) — вне текущего объёма. Правило: «every loaded instruction consumes context» — файл ≤150 строк.

## 9. Plugin Hooks

The workflow-enforcement plugin implements 6 lifecycle hooks:

| Hook | When | Purpose |
|------|------|---------|
| `tool.execute.before` | Before any tool call | Routing table enforcement; JSON-before-Task gate (no grace for locked agents, v4); inspection budget & post-pipeline inspection ban for plankestrator (v4); suppressed while a Task subagent runs (`activeTaskDepth > 0`, v4) |
| `tool.execute.after` | After tool completes | Logs tool completion |
| `session.created` | New session starts | Detects which agent is running; CHILD (subagent) sessions preserve the parent's identity-lock state (parentID guard, v4) |
| `session.updated` | Session changes | Detects identity drift |
| `session.idle` | Session ends | Logs workflow summary |
| `message.updated` | Message added | Validates JSON output format (INVALID JSON logged as error, v4); detects forbidden vocabulary and self-work content markers (v4); skipped while a Task subagent runs |

## 10. Identity Verification Format

Both primary agents must output identity verification to prevent drift:

### Required Output Format

```
✓ IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].
```

### JSON Output Requirement

All agents must include an `"agent"` field in their JSON output:

```json
{
  "agent": "orchestrator",
  ...
}
```

or

```json
{
  "agent": "plankestrator",
  ...
}
```

### Plugin Agent Detection

The workflow-enforcement plugin detects the agent using multiple methods (priority order):

1. **IDENTITY VERIFIED text** — highest priority
   - Extracted from "IDENTITY VERIFIED: I am orchestrator..." text
   - `extractIdentityFromMessage()` function in plugin

2. **JSON output** — secondary priority
   - Extracted from JSON `"agent"` field
   - `extractJSONFromMessage()` function in plugin

3. **Reverse routing lookup** — fallback
   - If agent calls a subagent, detect based on routing table
   - `detectAgentFromSubagent()` function in plugin

This ensures correct agent identification even if session data is incorrect.
