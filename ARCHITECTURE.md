# Architecture Requirements

This file is the single source of truth for the OpenCode dual-primary-agent architecture. All other files must be consistent with this document. It exists ONLY here, in the repo (canonical project doc; it is NOT copied to the live config).

This document declares the project's requirements and consistency rules in full. The consistency-checker agent verifies that the actual project state fulfills them.

## 1. Routing Tables

### orchestrator Whitelist (29 agents)

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
| 22 | image-creator | Image creation (MCP media: generation + editing) |
| 23 | video-generator | Video generation (MCP media: MiniMax-H3 default — 2K, first+last frame; Hailuo family; async polling) |
| 24 | git-commit | Gated conventional git commits |
| 25 | advisor | Step-boundary advisory reviewer (severity-tagged, read-only) |
| 26 | voice-synthesizer | Voice synthesis (TTS, MCP media) |
| 27 | voice-transcriber | Speech-to-text (MCP media ASR) |
| 28 | voice-clone | Voice cloning TTS (MCP media) |
| 29 | codebase-analyzer | Codebase analysis agent. Deep structural analysis of dependencies, architecture, and refactoring impact. Read-only (read/glob/grep). Kimi K2.8. |

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
| orchestrator | 29 | 30 (orchestrator + 29 subagents) |
| plankestrator | 10 | 11 (plankestrator + 10 subagents) |
| **Grand Total** | **39** | **41** |

Note: 39 whitelist entries (view-image shared by both primaries) = 38 unique whitelisted subagents (incl. advisor — a step-boundary reviewer inside DEV COMPLEX / DEV SUPERCOMPLEX / BUGFIX DEEP pipelines), PLUS scout — a subagent OUTSIDE both routing tables (never a pipeline step; called only internally by whitelisted subagents via their own permission.task allowlists). 39 unique subagents + 2 primary agents = 41 unique agents total.

### Shared Utility Agents

view-image is a shared utility agent available to BOTH primary agents. It is listed in BOTH routing tables (orchestrator: position 20 of 29; plankestrator: position 10 of 10) and granted `task.view-image: allow` in both permission blocks in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.

## Subagent Models

| Agent | Model |
|-------|-------|
| worker | bifrost-litellm/stepfun/step-5-preview |
| bugfix-triage | bifrost-litellm/openrouter/deepseek-v4.1-flash |
| bugfix | bifrost-litellm/QWEN3.7-plus |
| plan-bug | bifrost-litellm/GLM-5.3 (res) |
| execute-bug | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| dev-planner | bifrost-litellm/qwen3.8-max |
| dev-professor | bifrost-litellm/GLM-5.3 (res) |
| dev-reviewer | bifrost-litellm/Kimi K3 |
| rework | bifrost-litellm/openrouter/deepseek-v4.1-flash |
| consistency-checker | bifrost-litellm/xiaomi/mimo-v2.6-pro |
| advisor | bifrost-litellm/tencent/Hy4 |
| docs-writer | bifrost-litellm/xiaomi/mimo-v2.6-pro |
| docs-planner | bifrost-litellm/openrouter/deepseek-v4.1-flash |
| utility | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| mcp-github | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| mcp-read | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| mcp-search | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| summarizer | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| devops-agent | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| devops-reviewer | bifrost-litellm/Kimi K2.8 |
| orchestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plankestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plan-writer-simple | bifrost-litellm/QWEN3.7-plus |
| plan-writer-complex | bifrost-litellm/qwen3.8-max |
| plan-reviewer-simple | bifrost-litellm/GLM-5.3 (res) |
| plan-reviewer-complex | bifrost-litellm/Kimi K3 |
| research-writer-simple | bifrost-litellm/xiaomi/mimo-v2.6-pro |
| research-writer-complex | bifrost-litellm/Kimi K3 |
| research-reviewer | bifrost-litellm/GLM-5.3 (res) |
| devops-readonly | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| git-commit | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| image-creator | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| video-generator | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| view-image | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| scout | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| voice-synthesizer | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| voice-transcriber | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| voice-clone | bifrost-litellm/MiniMax-M3.1-Flash-Preview |
| codebase-analyzer | bifrost-litellm/Kimi K2.8 |

Note: primary agents (orchestrator, plankestrator) run on `bifrost-litellm/QWEN3.7-plus` and are documented in §Identity Lock Mechanism (v3), item 5 — not duplicated in the Subagent Models table.

### Voice media models (via media MCP — not agent LLMs)

| Model | Provider | Agents | Usage |
|-------|----------|--------|-------|
| voice/xiaomi/mimo-v2.5-tts | bifrost-litellm | 0 | Via media MCP — voice-synthesizer (preset-voice TTS) |
| voice/xiaomi/mimo-v2.5-asr | bifrost-litellm | 0 | Via media MCP — voice-transcriber (speech-to-text) |
| voice/xiaomi/mimo-v2.5-tts-voiceclone | bifrost-litellm | 0 | Via media MCP — voice-clone: zero-shot per-request clone (`clone_speech`) |
| MiniMax-H3 / Hailuo-2.3 / Hailuo-02 / T2V-01 (video) | bifrost-litellm | 0 | Via media MCP — video-generator; H3 = default (2K, first+last frame, PAYG), Hailuo family = TokenPlan |
| 7 image + 7 image-edit models | bifrost-litellm | 0 | Via media MCP — image-creator; authoritative set is the live catalog |
| voice/xiaomi/mimo-v2.5-tts-voicedesign | bifrost-litellm | 0 | Via media MCP — voice-synthesizer (VoiceDesign mode) |
| minimax/speech-2.8-hd | bifrost-litellm | 0 | Via media MCP — voice-synthesizer: 8 system voices + registered persistent clone voices via `voice_id` (PAYG) |

Полный и актуальный набор моделей/параметров media MCP — в живом каталоге (`media_media-list_media_models`); он не хардкодится здесь и проверяется при изменениях. Параметры (duration/resolution/ratio/frames для видео, style/voice/voice_id для речи) закреплены в промптах агентов video-generator.md, image-creator.md, voice-synthesizer.md, voice-clone.md. Биллинг: MiniMax-H3 и persistent voice clone (`media_media-register_voice_clone`) → PAYG-аккаунт MiniMax; остальные модели — по каналам провайдера.

## Model Roles (v5 — single source of truth, OMP model-roles analog)

Роли централизуют назначение моделей 41 агентам. Рантайм opencode НЕ поддерживает role-алиасы (`model:` во frontmatter литерален) — таблица является каноническим mapping'ом для: (1) массовых смен моделей (правка таблицы → синхронная правка frontmatter), (2) валидации consistency-checker (Model Roles), (3) документации. Квота-aware fallback-цепочки — платформенное требование (статус: НЕ реализовано, требует поддержки рантайма/proxy).

| Role | Model | Tier | Agents |
|------|-------|------|--------|
| primary | bifrost-litellm/QWEN3.7-plus | mid | orchestrator, plankestrator |
| probe | bifrost-litellm/QWEN3.7-plus | mid | orchestrator-identity-probe, plankestrator-identity-probe |
| plan-strong | bifrost-litellm/qwen3.8-max | top | dev-planner, plan-writer-complex, devops-reviewer |
| plan-lite | bifrost-litellm/QWEN3.7-plus | mid | plan-writer-simple |
| plan-flash | bifrost-litellm/GLM-5.3 (res) | mid | plan-bug |
| review-strong | bifrost-litellm/Kimi K3 | top | dev-reviewer, plan-reviewer-complex, research-writer-complex |
| rework-flash | bifrost-litellm/openrouter/deepseek-v4.1-flash | low | rework |
| review-lite | bifrost-litellm/QWEN3.7-plus | mid | bugfix |
| consistency-flash | bifrost-litellm/xiaomi/mimo-v2.6-pro | low | consistency-checker |
| review-flash | bifrost-litellm/GLM-5.3 (res) | mid | plan-reviewer-simple, research-reviewer |
| triage-flash | bifrost-litellm/openrouter/deepseek-v4.1-flash | low | bugfix-triage |
| advisory | bifrost-litellm/tencent/Hy4 | mid | advisor |
| executor-strong | bifrost-litellm/GLM-5.3 (res) | mid | dev-professor |
| executor-cheap | bifrost-litellm/MiniMax-M3.1-Flash-Preview | low | execute-bug, utility, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-readonly, view-image, git-commit, voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone |
| executor-step5 | bifrost-litellm/stepfun/step-5-preview | low | worker |
| docs | bifrost-litellm/xiaomi/mimo-v2.6-pro | low | docs-writer, research-writer-simple |
| docs-plan | bifrost-litellm/openrouter/deepseek-v4.1-flash | low | docs-planner |
| micro | bifrost-litellm/MiniMax-M3.1-Flash-Preview | low | scout |
| analyzer | bifrost-litellm/Kimi K2.8 | mid | codebase-analyzer |

Контроль суммы: 2 primary + 39 subagents = 41 агентов; каждая строка Subagent Models (§выше) принадлежит ровно одной роли.

**Правила:**
1. **Prewalk-принцип (OMP):** в паре planner→executor роль planner'а ДОЛЖНА быть tier ≥ executor'а: plan-bug (plan-flash, mid) → execute-bug (executor-cheap, low); dev-planner (plan-strong, top) → dev-professor (executor-strong, mid); docs-planner (docs-plan, low) → docs-writer (docs, low). Инверсия запрещена.
2. Смена модели агента = правка этой таблицы + frontmatter live `agents/*.md` + Subagent Models (эта таблица) — 2 синхронных места; после правки live выполнить `config-sync --save` (repo-зеркало). Валидация — consistency-checker (Model Roles).
3. Новые агенты получают роль из таблицы; новая роль добавляется только с обоснованием в CHANGELOG.
4. Миграция frontmatter на role-алиасы (`model: "@review-strong"`) — ЗАБЛОКИРОВАНА до поддержки рантаймом opencode (задокументированное платформенное требование, аналогично quota-aware fallback).

### Permission Notes

| Agent | Special Permissions | Reason |
|-------|-------------------|--------|
| worker | `bash: allow` | Implementation agent — needs bash for npm install, git operations, running tests, executing commands |
| bugfix | `bash: allow` | Bug fixing agent — needs bash for running tests, git operations |
| execute-bug | `bash: allow` | Bug fix implementation — needs bash for running tests, executing commands |
| rework | `bash: allow` | Rework agent — needs bash for running tests, git operations |
| plan-bug | `edit, write: allow` (`.md` only) | Bug fix planning — writes plan to `bug_plan.md` for execute-bug to read |
| docs-planner | `edit, write: allow` (`.md` only) | Documentation planning — writes plan to `docs_plan.md` for docs-writer to read |
| devops-reviewer | `read: allow` in addition to `bash: allow` | DevOps review — needs bash for running commands, read for checking files |
| devops-agent | `bash: allow` only | DevOps operations — needs bash for npm, docker, deployment commands |

**View-Image Permission — build agents:** worker, bugfix, execute-bug and rework carry `task.view-image: allow` to delegate image analysis (UI screenshots, diagrams, error images) to the view-image agent via the Task tool.

### Worker Bash Permission Details

Worker is the implementation agent — it MUST have `bash: allow` to execute commands:

| Command Type | Examples |
|--------------|----------|
| npm operations | `npm install`, `npm run build`, `npm run test` |
| git operations | `git status`, `git add`, `git branch`, `git log`, `git diff` (NOT `git commit` / `git push` — denied in frontmatter; delegate to `git-commit`) |
| file operations | `mkdir`, `touch`, `rm` |
| linting tools | `eslint`, `prettier`, `tsc` |
| test runners | `jest`, `vitest`, `pytest` |
| any CLI tools | Any command-line tool execution |

**Critical:** Without `bash: allow`, worker cannot implement changes — it would be unable to run tests, install dependencies, or execute any commands.


### Edit Permissions (plankestrator subagents)

**Important:** `edit` and `write` are BOTH valid glob-scoped permission keys (verified empirically on a real `plan-bug` run). They gate two different tools with different capabilities:

| Permission key | Tool | Creates new files? | Edits existing files? |
|----------------|------|:---:|:---:|
| `edit` | `edit` | ❌ no (string replacement on an existing file) | ✅ yes |
| `write` | `write` | ✅ yes | ✅ yes |

Because the `edit` tool fails on a non-existent path, an `edit`-only grant cannot create a new file (e.g. `bug_plan.md` / `dev_plan.md`) — the agent must also be granted `write`. A glob restriction such as `{ "*.md": "allow", "*": "deny" }` narrows the tool to matching paths; it does **not** remove the tool from the agent's toolset.

**Recommended pattern for plan/plan-writer agents** (create and edit `.md` only):

```yaml
permission:
  edit:
    "*.md": "allow"
    "*": "deny"
  write:
    "*.md": "allow"
    "*": "deny"
```

| Agent | Permission | Restriction |
|-------|------------|-------------|
| plan-bug | `edit, write: allow` (`.md` only) | Only .md files, writes bug_plan.md |
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

**Note:** `write` IS a valid permission key — it is glob-scoped, like `edit`, and gates the `write` tool (which creates new files). `edit` gates the `edit` tool (which only modifies existing files). Agents that must create and then edit a new `.md` (e.g. plan-bug → `bug_plan.md`) need BOTH keys; a glob-scoped `write` key such as `write: { "*.md": "allow", "*": "deny" }` is honoured, not ignored.

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

**Текущее значение:** `3` (задаётся в live `~/.config/opencode/opencode.json`, строка 3, сразу после `$schema`; repo-зеркало — `opencode.json` в корне репо). Документация: <https://opencode.ai/docs/config>.

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
Уровень 2 (depth 2): scout / codebase-analyzer / mcp-search / mcp-read / mcp-github / devops-readonly / docs-writer (прямой вызов из worker/dev-professor/execute-bug)
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

**Scope rule:** top-level pipelines (PIPELINE TABLE in `agents/orchestrator.md` / `agents/plankestrator.md`; the `pipeline` JSON field) remain LINEAR `string[]` — one element = one Task call by the primary agent. Parallel waves exist ONLY INSIDE a pipeline element: a subagent's own Task fan-out (e.g. research-writer-complex scout wave). Every wave branch must come from the SUBAGENT's own `permission.task` allowlist (frontmatter + opencode.json), not from the primary's routing table. MULTI_PHASE keeps this rule: the `pipeline` field holds the CURRENT phase's linear chain; phases are concatenated sequentially by the primary, never in parallel.

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
bugfix-triage → plan-bug (writes bug_plan.md) → execute-bug (reads bug_plan.md) → advisor → dev-reviewer → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

**Two-stage pipeline decision (mandatory):** the orchestrator NEVER guesses SIMPLE vs DEEP itself. For any BUGFIX it first sends `["bugfix-triage"]` with `complexity: null`. When triage returns its verdict, the orchestrator extends the pipeline ONCE:

- `TRIAGE_RESULT: SIMPLE` → continue `["worker", "utility"]`
- `TRIAGE_RESULT: DEEP` → continue `["plan-bug", "execute-bug", "advisor", "dev-reviewer", "consistency-checker", "utility"]`

**Single source of truth for pipeline selection:** the PIPELINE TABLE in each primary agent's own `.md` file (`agents/orchestrator.md` for BUGFIX/DEVOPS/DEV/DOCS, `agents/plankestrator.md` for PLAN/RESEARCH/RESEARCH+PLAN). Each table must stay identical to the corresponding section in this file. (The inline `prompt` field formerly present in opencode.json was removed — markdown wins per the merge order documented above.)

Prompt-local reference sections (`PIPELINE GUIDE`, `CLASSIFICATION EXAMPLES`) in agents/*.md are illustrative and are NOT mirrored here; on conflict, the PIPELINE TABLE + CLASSIFICATION RULES + this file win.

**Plan file:** `plan-bug` writes the bug fix plan to `bug_plan.md` in the project root. `execute-bug` reads this file before implementing. The orchestrator MUST include "Write the plan to bug_plan.md" in the plan-bug prompt and "Read bug_plan.md" in the execute-bug prompt.

**Prewalk pattern (v5, OMP prewalk analog):** one-shot handoff expensive→cheap at the planning/implementation boundary. `plan-bug` runs on the MID-tier planner model (`GLM-5.3 (res)`, tier plan-flash) and writes a SELF-CONTAINED `bug_plan.md`; `execute-bug` runs on the CHEAP executor model (`MiniMax-M3.1-Flash-Preview`, tier executor-cheap) and mechanically applies the plan in a fresh context. Escape hatch: `execute-bug` sets `plan_gap: true` in its JSON when the plan turns out incomplete — downstream dev-reviewer/consistency-checker escalate (consistency-checker `escalate_to: "execute-bug"` remains available). Same philosophy in DEV COMPLEX: dev-planner (plan-strong) > dev-professor (executor-strong). Source: OMP prewalk pattern (`docs/prewalk.md`).

**Rework loop:** `rework` is NOT in the base pipeline. If dev-reviewer or consistency-checker reports issues (severity: concern/blocker), `rework` is inserted into the pipeline at the current position, then consistency-checker re-validates. Loop repeats up to 3 iterations. If no issues found → skip rework entirely. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV Complexity Classification (decision tree)

Canonical classification rules for DEV tasks (SIMPLE / COMPLEX / SUPERCOMPLEX). `agents/orchestrator.md` (CLASSIFICATION RULES) mirrors this section — any change here must land there in the same commit. Apply IN ORDER:

| # | Question | YES | NO |
|---|----------|-----|----|
| Q1 | User EXPLICITLY requests SUPERCOMPLEX ("use SUPERcomplex", "run the super-complex pipeline")? | SUPERCOMPLEX → Q1a | → Q2 |
| Q1a | A plan with a step list exists? | SUPERCOMPLEX | `dev-planner` `MODE: DECOMPOSITION` runs first (JSON step list, no `dev_plan.md`); classification STAYS SUPERCOMPLEX regardless of step count — explicit request wins; `plan_exists: true`, `plan_source: "DECOMPOSITION"` |
| Q2 | A plan/research file exists with >3 steps AND huge volume? | SUPERCOMPLEX | → Q2a |
| Q2a | A plan/research file exists (any size)? | SIMPLE with-plan variant — PLAN EXISTS OVERRIDE | → Q3 |
| Q3 | Task appears to have >3 logical steps but NO plan exists? | ⚠️ Do NOT classify yet — `dev-planner` `MODE: DECOMPOSITION` first, then re-evaluate: >3 steps + huge volume → SUPERCOMPLEX (`plan_exists: true`, `plan_source: "DECOMPOSITION"`); 2–3 steps → COMPLEX (`plan_exists: false` — dev-planner writes `dev_plan.md` in-pipeline); 1 step → SIMPLE (no architectural decisions) or COMPLEX (architectural decisions needed) | → Q4 |
| Q4 | 2–3 logical steps OR complex architecture (multi-file changes with dependencies, cross-cutting concerns, architectural decisions)? | COMPLEX | → Q5 |
| Q5 | Single focused change? | SIMPLE | COMPLEX (default for ambiguous cases) |

**🚫 CRITICAL RULE:** `complexity: SUPERCOMPLEX` with `plan_exists: false` is INVALID. SUPERCOMPLEX requires a determinable step list: a pre-existing plan with >3 steps OR a completed DECOMPOSITION.

**Count logical implementation steps**, not files or skills/technologies: "rename a variable across 5 files" is SIMPLE; one bug fix touching auth, database and caching may still be a single step.

**PLAN EXISTS OVERRIDE:** `plan_exists=true` + not SUPERCOMPLEX → DEV is ALWAYS SIMPLE (with-plan variant). An existing plan replaces in-pipeline planning — never reclassify a planned ≤3-step task as COMPLEX. Consequently DEV COMPLEX always implies `plan_exists: false`.

**Superseded (2026-09-22):** the former rule that routed unplanned multi-step DEV tasks (no plan + COMPLEX) to plankestrator as out of scope is NO LONGER valid — they stay with the orchestrator: Q3 decomposition first, then SUPERCOMPLEX / COMPLEX / SIMPLE per the outcome. PLAN/RESEARCH requests themselves remain out of orchestrator's scope.

### Type Selection Decision Tree (orchestrator)

Selects the TYPE (BUGFIX / DEVOPS / DEV / DOCS / null) BEFORE the complexity rules (Q1–Q5). `agents/orchestrator.md` mirrors this section — any change must land in both files in the same commit.

| # | Question | YES → | NO → |
|---|----------|-------|------|
| T0 | Request contains TWO OR MORE primary deliverables of DIFFERENT types, each independently resolving via T3–T6 to a different row, ALL within orchestrator scope (no plan/research deliverable), phases ≤ 3? | MULTI_PHASE → phase planning + user confirmation ("Multi-Phase Pipelines" section) | T1 |
| T1 | Identity test / small talk / meta question ("what did we do", "status")? | `type: null` — brief answer after the JSON, no Task call | T2 |
| T2 | Deliverable IS a plan/research document, no implementation requested ("plan", "research", "investigate options", "design the architecture", "create a plan")? | `type: null` + OUT OF SCOPE message (switch to plankestrator), no Task call | T3 |
| T3 | Broken behavior described: error / stack trace / crash / failing test / "not working" / "broken" / regression? **Strong triggers:** "исправь" / "fix" / "ошибка" / "error" / "баг" / "bug" / "сломалось" / "broken" / "не работает" / "not working" / "почему не работает" / "why it doesn't work" / "почему падает" / "why it crashes" / "почему ошибка" / "why error" → ALWAYS consider BUGFIX first | BUGFIX (row 1), `complexity: null`, `plan_exists: null` | T4 |
| T4 | Main action = RUNNING operations (build / deploy / test-run / lint / git / env / deps / model migration), no code writing? | DEVOPS (row 2) | T5 |
| T5 | Deliverable = markdown/docs only, zero logic change? | DOCS (row 7 or 8 by size) | T6 |
| T6 | Deliverable = new or modified code? | DEV → complexity Q1–Q5 | Re-check T2 |

**T0 strong triggers (combination required — a single conjunction is NOT enough):**
1. Sequence conjunctions + verbs from DIFFERENT T-branches: «исправь … и добавь …» (BUGFIX+DEV), «реализуй …, запусти тесты …, задеплой» (DEV+DEVOPS+DEVOPS).
2. Explicit numbering of heterogeneous steps: «1. Настрой CI. 2. Добавь тесты. 3. Задеплой» (T4, T6, T4).
3. Explicit user request: «сделай в несколько этапов/фаз», «multi-phase».

**T0 anti-triggers (NEVER multi-phase):**

| Request | Why single-phase |
|---------|------------------|
| «Исправь баг и обнови README» | DOCS secondary → Auto-DOCS hook |
| «Исправь баг и задеплой» | Deploy = follow-up in summary; multi-phase ONLY if the deploy is non-trivial (migrations, rollback) |
| «Добавь фичу и напиши к ней тесты» | Both DEV — tests are part of the feature |
| «Исправь баги в auth и в кэше» | One type → one BUGFIX |
| «Сделай рефакторинг оплаты (6 шагов)» | One type, many steps → SUPERCOMPLEX |

**Primacy heuristic:** a deliverable is primary if it CANNOT be covered by (a) the Auto-DOCS hook, (b) a follow-up mention, (c) one step of the existing pipeline. **Default = single-phase** (multi-phase is k full chains + a confirmation round-trip — irreversibly more expensive).

**T0 scope-guard:** if ANY deliverable is a plan/research document → T0 = NO (the request goes to T1/T2 as today — multi-phase NEVER mixes primaries; the plankestrator boundary is not crossed). Identity / small talk → T0 = NO (no deliverables).

**Mixed-intent priority (request spans several types):** BUGFIX > DEV > DOCS > DEVOPS. Pick exactly ONE row — the primary deliverable. Secondary intents are NOT separate pipelines: docs about the code change ride the Auto-DOCS hook (`requires_docs_update`); a deploy after a fix is mentioned in the final completion summary as a follow-up request. NEVER split one request into two pipelines **SILENTLY** — splitting is legal ONLY as a MULTI_PHASE pipeline: explicit `phases[]` in the JSON + user confirmation before execution (T0, "Multi-Phase Pipelines" below). Mixed-intent priority remains the DEFAULT and the fallback for borderline cases: if in doubt — single-phase.

**Deliverable test (T2 vs T6 — golden boundary):** «составь план рефакторинга» → the PLAN is the deliverable → `type: null` (plankestrator). «сделай рефакторинг» → the CODE is the deliverable → DEV (unplanned multi-step DEV stays with you — Q3 DECOMPOSITION; superseded rule 2026-09-22). The topic (refactoring / bugs / docs) never decides — the requested deliverable does.

**Edge cases (deterministic resolutions):**

| Situation | Resolution |
|-----------|------------|
| «запусти тесты» vs «тесты падают» | run tests = DEVOPS (row 2); failing tests = BUGFIX (row 1) |
| «почему X сломался?» — question only, no fix requested | BUGFIX (row 1): triage investigates; you never answer or investigate yourself |
| Build fails with a compile error in source code | BUGFIX (root cause = code). Repairing/configuring the CI setup itself = DEVOPS |
| Docstrings / comments only | DOCS (row 7/8). Any logic change → DEV; doc updates ride the Auto-DOCS hook |
| «реализуй план/исследование из <file>» | DEV; the file = plan → `plan_exists: true`, `plan_source: "<file>"`; step count + volume decide Q2 / Q2a |
| DOCS request referencing a plan file («напиши документацию по PLAN.md») | DOCS by size (row 7/8). `plan_exists` applies to DEV ONLY — leave it `null` for DOCS; the file is input context for docs-planner/docs-writer |
| Ambiguous DEV scope | COMPLEX (Q5 default) |
| «сделай быстро, без ревьюеров» | The pipeline is frozen and reviewers are mandatory (PROHIBITIONS). The only legal accelerator is the severity-nit rework SKIP (SEVERITY RULES) |
| Subagent result says «нужно сначала исследовать/спланировать» | Pipeline FROZEN: complete it; surface the recommendation in the final completion summary. Never re-route, never call plankestrator's agents |
| Unplanned multi-step DEV («сделай рефакторинг всей системы оплаты») | NOT out of scope — Q3: DECOMPOSITION PROTOCOL first, then row 6 / 5 / 3 per outcome |
| «Исправь баг и добавь фичу» (2 primary deliverables, T3+T6) | MULTI_PHASE (T0): P1 BUGFIX → P2 DEV, user confirmation mandatory |
| «Исправь баг и обнови README» | NOT multi-phase (T0 anti-trigger): BUGFIX + Auto-DOCS hook |
| Multi-phase: user silence / ambiguous reply after the plan | Fail-closed: NOT a confirmation; re-show the plan (max 2 edit rounds), then CANCELLED |
| Multi-phase: phase FAILED | Fail-fast: downstream phases SKIPPED, report to the user; resume via PHASE_STATE.md (new session preferred) |

### Multi-Phase Pipelines (MVP — linear chain, 2–3 phases, user-confirmed)

**Definition.** A MULTI_PHASE session executes a SEQUENCE of phases for ONE request. A **phase** = one existing PIPELINE TABLE row (1–8) with its own `(type, complexity, plan_exists)`. Phases are strictly sequential (one phase at a time; parallel waves inside subagents are unaffected — Scope rule above). The phase plan is fixed BEFORE execution starts and is confirmed by the user. Each phase produces a Phase Result envelope (below) consumed by the next phase.

```
Запрос → T0 (2+ первичных разнотипных deliverable?) ── NO → T1–T6 (как сегодня, default)
   │ YES
   ▼
Turn 1: JSON {type: "MULTI_PHASE", state: "AWAITING_CONFIRMATION",
              next_agent: null, pipeline: [], phases: [P1, P2, …], current_phase: null}
        + "## MULTI-PHASE PLAN" (таблица фаз) + ack → STOP, Task НЕ вызывается
        [плагин: awaitingConfirmation=true; Task в этом же ходе → THROW]
    ▼
Ответ пользователя: «да» → старт P1 | правка (≤2 раундов) → новый AWAITING | «отмена» → state:"CANCELLED"
    ▼
Фаза P1 = строка PIPELINE TABLE по (type, complexity, plan_exists) фазы
    → phase_result_1 (JSON-конверт, small data) + секция в PHASE_STATE.md (пишет utility через bash)
    ▼ (фазовая граница = легальная мутация pipeline: MP-5)
    Фаза P2 … → FINAL SUMMARY по всем фазам
```

**PIPELINE TABLE meta-rule (NO new rows; mirrored 1:1 in agents/orchestrator.md):**

**Multi-phase:** `phases` — array of 2–3 phases (MVP); each phase independently resolves to row 1–8 by its own `(type, complexity, plan_exists)`. The session `pipeline` field ALWAYS contains the CURRENT phase's chain only; phase state lives in `phases[]` + `current_phase`. The session pipeline = sequential concatenation of phase chains with phase barriers (barrier = structural: all Task calls of the phase completed; NOT a dialog point — dialog happened at confirmation).

**Phase classification.** Phase TYPE — T1–T6 applied to the phase's sub-task (not to the whole request). Phase COMPLEXITY — existing rules: BUGFIX → `null` + triage; DEV → Q1–Q5; DOCS → by size; DEVOPS → `null`. Two-stage protocols are preserved INSIDE the phase (BUGFIX one-time continuation; DEV DECOMPOSITION). Multi-phase does NOT change T1–T6 / Q1–Q5 — classification is applied k times, once per phase.

**JSON extension (backward compatible).** `type: "MULTI_PHASE"` + conditional fields `state` / `phases[]` / `current_phase` — full spec in §3 "Multi-Phase Fields (orchestrator)". Example (executing turn):

```json
{
  "agent": "orchestrator", "type": "MULTI_PHASE", "complexity": null,
  "plan_exists": null, "plan_source": null, "goal": "one sentence",
  "next_agent": "bugfix-triage", "pipeline": ["bugfix-triage"],
  "state": null,
  "phases": [
    {"id": "P1", "type": "BUGFIX", "complexity": null, "plan_exists": null, "goal": "...", "depends_on": []},
    {"id": "P2", "type": "DEV", "complexity": "COMPLEX", "plan_exists": false, "goal": "...", "depends_on": ["P1"]}
  ],
  "current_phase": "P1"
}
```

`pipeline` ALWAYS holds the CURRENT phase's chain. On a phase boundary `current_phase` switches and `pipeline` is REPLACED by the next phase's chain — a legal mutation (whitelist MP-5, Enforcement gates below).

**Confirmation protocol.**

- Turn 1 (phase planning): JSON with `state: "AWAITING_CONFIRMATION"`, `next_agent: null`, `pipeline: []`, `current_phase: null` + a human-readable phase table (id / type / goal / pipeline row / depends_on) + ack. NO Task call this turn — the plugin confirmation gate throws.
- Turn 2 (the user's reply): approve («да/ок») → start P1; edit → recompute the affected phase + dependency cascade → new AWAITING turn (max 2 edit rounds, then start-as-is or cancel); reject («отмена») → `state: "CANCELLED"`, zero Task calls.
- Allowed edits: (a) drop a phase → SKIPPED with dependency cascade, (b) lower complexity (SUPERCOMPLEX→COMPLEX), (c) reorder independent phases (in the MVP linear chain — effectively cancel + reassemble), (d) cancel everything. Forbidden edits: new agent types, skipping mandatory reviewers.
- Silence / ambiguous reply = NOT a confirmation (fail-closed).
- Explicit override in the ORIGINAL request («без подтверждений, делай сразу») → the plan is shown informatively and execution starts immediately (auto-approve, no AWAITING turn).
- Confirmation happens via a plain text reply — the tool `question` is NOT used (`question: deny` preserved, §1 Primary Agent Tool Lockdown).

**Context passing — 3 channels ("pointer, not transcript").**

1. **Phase Result envelope** — machine-readable, SMALL data only (XCom principle): summary ≤3 sentences, facts ≤10 keys; large content NEVER travels in JSON — only file pointers. Canonical spec duplicated in §3 "Multi-Phase Fields (orchestrator)":

```json
{
  "phase_id": "P1",
  "phase_type": "BUGFIX",
  "status": "SUCCESS | FAILED | SKIPPED",
  "summary": "≤3 sentences",
  "artifacts": ["src/auth/middleware.ts", "bug_plan.md"],
  "facts": { "tests": "green", "files_changed": 3, "public_api_changed": false },
  "blockers": [],
  "docs_deferred_to": "P3 | null"
}
```

2. **`PHASE_STATE.md`** — human-readable journal in the project root, one section per phase (goal, what was done, key decisions, artifacts). Scribe = `utility` via bash (mechanical verbatim append; APPEND-ONLY — previous sections are never modified). MVP limitation: if the chain ENDS with a DEVOPS phase (no utility in the row), the trailing section is not written — the final summary lists phase results as text (Stage 2: devops-scribe).
3. **Verbatim handoff** — the first Task prompt of the next phase receives the previous phase's envelope VERBATIM + a context phrase: `Phase P<i> (<type>) completed: <summary>. Artifacts: <list>. Facts: <facts>. Read PHASE_STATE.md if you need more context.`

**PHASE_STATE.md lifecycle** (deterministic — file must never become a stale, committed artifact):

- **Created:** `utility` (scribe) creates the file with header `# PHASE_STATE` on first mechanical append (Phase 2).
- **Reset:** utility-scribe recreates PHASE_STATE.md with fresh header on FIRST phase (replaces any stale file from previous chain) — so every chain starts from an empty journal.
- **Session ID:** each phase section MUST include a session timestamp, so a stale file from a previous session can never be mistaken for the current chain.
- **Cleanup:** deleted after the final phase completes (before delegating to `git-commit`), so the journal never lands in a commit.
- **Git-ignored:** `PHASE_STATE.md` is listed in `.gitignore` as a second line of defence against accidental commits.

**Fail-fast.** A phase FAILED → the chain STOPS, downstream phases are SKIPPED, report to the user (which phase, its envelope, options — including «продолжи с P<k>» resume). Silent continuation is FORBIDDEN. Rework lives INSIDE a phase only (max 3) — no global cross-phase rework. `BLOCKER STOP AFTER 3` inside a phase = phase FAILED.

**SUPERCOMPLEX disambiguation.** SUPERCOMPLEX = iteration over the steps of ONE DEV plan inside ONE phase; multi-phase = iteration over phases of DIFFERENT types. ≤1 SUPERCOMPLEX phase per plan; nested multi-phase is FORBIDDEN (a phase may BE SUPERCOMPLEX; phases never contain sub-phases). Two-level ack: `→ PHASE 1/2 (P1), STEP 3/8 (S-3): DELEGATED to dev-professor`. Classification priority: T0/multi-phase FIRST, then Q1–Q5 inside each DEV phase.

**Edge cases (deterministic resolutions):**

| Situation | Resolution |
|-----------|------------|
| The plan collapsed to 1 phase | Degrade to a regular single-phase pipeline WITHOUT confirmation |
| All phases of the same type | NOT multi-phase → SUPERCOMPLEX or one pipeline |
| One of the phases is a plan/research deliverable | OUT OF SCOPE entirely (T0 scope-guard) |
| Auto-DOCS hook inside multi-phase | The hook fires PER PHASE (after each BUGFIX/DEV phase), as per-pipeline today |
| `requires_docs_update` from P1 while the plan has a DOCS phase P3 | The hook is NOT duplicated (dedup by type): docs work goes to the explicit DOCS phase; P1's envelope carries `docs_deferred_to: "P3"`, the DOCS phase's Task prompt receives it verbatim |
| Phase FAILED, user: «продолжи с P2» | Resume: prefer a NEW session (blockerStop is cumulative — Enforcement gates); the orchestrator reads `PHASE_STATE.md` (classification read), restores the envelopes, starts from P2 without re-confirmation if the plan is unchanged; plugin: a legal phase transition resets blockerStop (MP-5) |
| Skipping a phase mid-flight | Only cancelling the remainder of the chain («стоп»); NO waiting point between phases (the barrier is structural, not a dialog point) |
| The chain ENDS with a DEVOPS phase | The trailing PHASE_STATE.md section is not written (DEVOPS has no utility) — MVP limitation; the final summary lists all phase results as text |

**Cyclic dependencies.** Phases are numbered; `depends_on` may reference ONLY smaller ids (cycles are syntactically inexpressible; MVP: exactly `[previous id]`, P1 → `[]`). Pseudo-cycles («fix → feature → if broken, fix again») = in-phase rework or a repeated type (two BUGFIX phases) — not a cycle. Data-dependent cross-phase cycles are FORBIDDEN (bounded iteration lives inside a phase only).

**Stage 2 backlog (NOT in MVP):** `continue_on_error` per phase; resume from an arbitrary phase as first-class; explicit DAG `depends_on`; phase limit 4; session-length telemetry (candidate: summarizer between phases); advisor behavior on phase boundaries (NIT_ONLY_MODE window).

### DEV SIMPLE

DEV SIMPLE has two variants depending on whether a plan exists:

| Variant | Flow | When to Use |
|---------|------|-------------|
| DEV SIMPLE (without plan) | `worker → utility` | plan_exists=false — direct implementation and validation |
| DEV SIMPLE (with plan) | `worker → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility` | plan_exists=true — plan-validated implementation with rework loop |

**Decision rule:** If plan_exists=true, use the "with plan" variant. Otherwise, use the "without plan" variant.

**PLAN EXISTS OVERRIDE:** if a plan file exists and the task is NOT SUPERCOMPLEX (>3 steps + huge volume), DEV is ALWAYS SIMPLE (with-plan variant) — an existing plan replaces in-pipeline planning; never reclassify a planned ≤3-step task as COMPLEX.

**Rework loop:** If consistency-checker finds critical issues, task returns to worker for fixes, then consistency-checker validates again. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV COMPLEX

```
dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

**Rework is conditional:** `rework` is NOT in the base pipeline. It is inserted dynamically ONLY if dev-reviewer or consistency-checker reports issues (severity: concern/blocker). If no issues found → skip rework entirely.

**Precondition:** DEV COMPLEX implies `plan_exists: false` — no plan file exists at classification time; `dev-planner` creates `dev_plan.md` in-pipeline. If a plan file DOES already exist, the task is either SIMPLE (with-plan variant, ≤3 steps — Q2a) or SUPERCOMPLEX (>3 steps + huge volume — Q2), never COMPLEX. Unplanned multi-step DEV tasks are NOT out of scope for the orchestrator — the Q3 decomposition path applies (see "DEV Complexity Classification" above).

**Rework loop:** `rework` is NOT in the base pipeline. If dev-reviewer or consistency-checker reports issues (severity: concern/blocker), `rework` is inserted at the current position, then consistency-checker validates again. If no issues found → skip rework entirely. Loop repeats up to 3 iterations.

**Advisor step (v5, OMP Advisor Watchdog analog — step-boundary):** `advisor` (tencent/Hy4, strictly read-only: read/grep/glob + read-only serena) observes the implementation result between pipeline steps and returns severity-tagged notes (`nit|concern|blocker`, contract — §3 Reviewer Severity Field). Mid-turn intervention is NOT possible (our agents are atomic within a step) — advisor fires only at step boundaries. Safeguards: emission guard (max 4 non-blocker notes per run, session dedup, empty-phrase filter — plugin v5 + advisor prompt), immuneTurns analog (`NIT_ONLY_MODE` for 3 pipeline steps after a consumed blocker — concern/blocker notes downgrade to nit), separate cost accounting (advisor ≈ 1 extra model call per step; logged in plugin + orchestrator acks). Advisor never re-orders the pipeline; blocker → ⚠️ ack + notes to dev-reviewer/rework; persistence after 3rd rework iteration → failure report.

### DEV SUPERCOMPLEX

```
PER PLAN STEP (repeated for each step in the step list):
  dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → [rework loop: rework → consistency-checker, max 3] → utility
```

**🚨 CRITICAL: SUPERCOMPLEX executes the FULL pipeline for EACH plan step.**

The pipeline `dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → [rework loop] → utility` is executed **SEPARATELY for every step** of the plan.

**Example:** If the plan has 8 steps, the orchestrator executes the full pipeline 8 times:
- Step 1: dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → utility
- Step 2: dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → utility
- ...
- Step 8: dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker → utility

**Never** execute the pipeline once for the entire task. **Always** iterate over each plan step.

Super-complex development tasks with a large plan (>3 steps — pre-existing OR produced by DECOMPOSITION) or huge volume of work. The orchestrator executes the full review/consistency/syntax chain **for every step** of the plan — never one pass over the whole task.

**Trigger conditions:**
- Explicit user request (e.g. "use SUPERcomplex", "run the super-complex pipeline") — if no step list exists, `dev-planner` `MODE: DECOMPOSITION` runs first and the classification STAYS SUPERCOMPLEX regardless of step count (explicit request wins), OR
- A plan exists with more than 3 steps AND a huge volume of work, OR
- No plan exists but the task appears to have >3 steps AND huge volume — determined via `dev-planner` `MODE: DECOMPOSITION` BEFORE final classification (Q3)

DECOMPOSITION paths set `plan_exists: true`, `plan_source: "DECOMPOSITION"`. **🚫 CRITICAL RULE:** `complexity: SUPERCOMPLEX` with `plan_exists: false` is INVALID (see "DEV Complexity Classification" above).

**Step list determination (once, before the first pipeline step; strict priority):**
1. **User listed the steps explicitly** (e.g. "Implement P0-1, then P0-2, then P0-3") → the steps are used verbatim.
2. **The plan/research file has a clear step structure** — headings like `## P0-1`, `## Phase 1`, `## Шаг 1`, `### P0-1` → the orchestrator extracts the steps via its ONE allowed classification `read` of the plan file, or — if it has not read the file — via a single `mcp-read` Task call listing the step headings (`mcp-read` is the orchestrator's whitelisted file-reading agent; `devops-readonly` is NOT callable by orchestrator — it belongs to plankestrator's routing table).
3. **No step list anywhere** → ONE `dev-planner` call in DECOMPOSITION mode (`MODE: DECOMPOSITION` in the Task prompt): dev-planner analyzes the research file and returns JSON `{"decomposition": true, "steps": [{"id": "...", "title": "...", "description": "..."}, ...]}` WITHOUT writing `dev_plan.md`.

**Per-step chain:** For each step, `dev-planner` writes the detailed plan for THIS step to `dev_plan.md`, `dev-professor` reads the plan file, critically reviews it, then implements the step, `advisor` observes the implementation result at the step boundary (see "Advisor step" under DEV COMPLEX), `dev-reviewer` reviews the code, `consistency-checker` validates architecture (`rework` inserted only if a reviewer reported issues), then `utility` runs the syntax check before the orchestrator advances to the next step.

**Rework loop:** If dev-reviewer or consistency-checker reports issues within a step (severity: concern/blocker), `rework` is inserted into the pipeline at the current position for fixes, then consistency-checker validates again. If no issues found → skip rework entirely. Loop repeats up to 3 iterations per step. If a step passes, the orchestrator advances to the next plan step and repeats the chain.

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
            → consistency-checker
           → [rework loop: rework → consistency-checker, max 3]
           → utility
```

### Auto-DOCS Hook (BUGFIX / DEV pipelines)

After the final `utility` step of BUGFIX/DEV pipelines, check the JSON output of the implementation agent (execute-bug, dev-professor, worker).

**Trigger:** call `docs-writer → utility` if implementation agent's JSON output has `requires_docs_update: true`.

**Orchestrator-side parse (mandatory):** the orchestrator MUST parse the `requires_docs_update` field from the arriving implementation agent's JSON. This is a mechanical field read — an explicit exception to the orchestrator's "advance, don't analyze" turn rule (mirrored in `agents/orchestrator.md` TURN ALGORITHM).

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

**Multi-phase dedup:** within a MULTI_PHASE session the hook fires PER PHASE (after each BUGFIX/DEV phase's final `utility`), same as per-pipeline today. Exception: if the confirmed plan already contains a LATER DOCS phase covering the docs work, the hook is SUPPRESSED for the earlier phase — the implementation agent's `requires_docs_update: true` is carried into the phase result envelope as `docs_deferred_to: "<DOCS phase id>"`, and the DOCS phase's first Task prompt receives the envelope verbatim. Dedup key = phase type DOCS present downstream in `phases[]` (mechanical check, not analysis).

### Direct docs-writer Call (in-flight, BUGFIX/DEV)

Implementation agents (worker, dev-professor, execute-bug) hold `task.docs-writer: allow` (opencode.json) and MAY call docs-writer directly DURING their step when user-facing documentation is needed (user instructions, portal guides). Rules: at most ONE call per task; the Task prompt must be self-contained (`docs_plan.md` is NOT written for direct calls); a direct call does NOT replace the `requires_docs_update` flag — the Auto-DOCS hook stays independent. Depth: primary(0) → implementation agent(1) → docs-writer(2) — within `subagent_depth: 3`.

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

### PLAN vs RESEARCH Boundary (plankestrator)

Selects the TYPE (PLAN / RESEARCH / RESEARCH+PLAN / null) from the REQUEST TEXT ONLY, applied IN ORDER. `agents/plankestrator.md` mirrors this section — any change must land in both files in the same commit.

| # | Question | YES → | NO → |
|---|----------|-------|------|
| P1 | Identity test / small talk / meta question? | `type: null` — brief answer after the JSON, no Task call | P2 |
| P2 | Deliverable IS implementation: fix / implement / deploy / run tests / write code / npm install / git commit / docs? | `type: null` + OUT OF SCOPE (switch to orchestrator), no Task call | P3 |
| P3 | BOTH research and plan requested (either order)? | RESEARCH+PLAN → row 6, ALWAYS COMPLEX | P4 |
| P4 | Deliverable = knowledge: исследуй / изучи / сравни / узнай / разберись / проанализируй варианты / research / compare / find out? | RESEARCH (row 3/4 by complexity) | P5 |
| P5 | Deliverable = plan/design of future work: спланируй / разработай план / спроектируй / архитектура / plan / design / how should we build? | PLAN (row 1/2 by complexity) | Re-check P2 |

**PLAN vs RESEARCH boundary (deliverable test):** decisions / a plan of future work → PLAN. Knowledge / answer / comparison → RESEARCH. Both explicitly → RESEARCH+PLAN (row 6). «Сравни и выбери» = RESEARCH (the verdict IS knowledge); «…и спланируй внедрение» = RESEARCH+PLAN.

**Deliverable test (P2 — golden boundary):** «исправь баг» → OUT OF SCOPE (deliverable = fixed code). «Спланируй исправление бага» → PLAN (deliverable = a plan document; the bug topic does not make it implementation). Keywords never decide alone — the requested deliverable does.

**Complexity default:** ambiguous complexity → COMPLEX (a stronger writer/reviewer chain is the safe side).

**Edge cases (deterministic resolutions):**

| Situation | Resolution |
|-----------|------------|
| «исследуй, почему сборка медленная» | RESEARCH (knowledge deliverable, verb «исследуй»). «Почини сборку» → OUT OF SCOPE (orchestrator) |
| «спланируй фикс бага X» | PLAN — the deliverable is a plan document, not a fix (P2 deliverable test) |
| «напиши документацию» | OUT OF SCOPE — docs writing = orchestrator's DOCS. «Спланируй структуру документации» → PLAN |
| «сравни A и B» (2 objects) | RESEARCH COMPLEX (row 4) — comparison of 2+ objects is COMPLEX per CLASSIFICATION RULES |
| «узнай лимит API X» (one question) | RESEARCH SIMPLE (row 3) |
| Request references an image needed to classify | view-image as its OWN separate turn BEFORE the classification turn (TURN ALGORITHM item 3) |
| «дополни существующий PLAN.md» | PLAN; pass the file reference in the Task prompt verbatim; complexity by the augmentation's scope |
| Writer/reviewer result hints «теперь можно внедрять» | Pipeline FROZEN; mention in the COMPLETE summary (max 3 lines), never Task an orchestrator agent |

### Wave → Barrier → Synthesis Pattern

A **barrier** is a synchronization point: the next stage starts only after ALL results of a parallel wave have arrived. In this architecture the barrier is NOT a separate agent — it is a structural property of the Task tool (all parallel Task calls issued in one message return before the agent's next turn) plus an explicit prompt-level step of the writer agent.

Implementation (research-writer-complex): wave results → rank by relevance/reliability → internal brief (key facts, contradictions, gaps) → synthesis from the brief on the strong model. "Pointer, not transcript": the report references sources and the output file, raw scout transcripts never leave the writer's context.

**Decision record (2026-09-19):** a separate `summarizer` barrier agent (Option A) was DEFERRED — parallel Task calls already provide a free structural barrier, a summarizer hop would require passing raw wave transcripts in its prompt (violates pointer-not-transcript), and ranking is inseparable from synthesis, which must run on the strong model. Escalation path if pilots show context overflow: grant `"summarizer": "allow"` in research-writer-complex task permissions and pass waves via a file pointer.

### Cross-Routing Prevention

Cross-routing (a primary agent calling a specialist that belongs to the other primary) is prevented by three layers:

| Layer | Where | Behavior |
|-------|-------|----------|
| 1. Prompt prevention | `CROSS-ROUTING BOUNDARY` sections in agents/orchestrator.md and agents/plankestrator.md | Explicit closed lists of the other primary's agents + "OUT OF SCOPE message = the exact standard phrase, no foreign agent names" + "pipeline frozen" |
| 2. Plugin: forbidden vocabulary | workflow-enforcement.ts (FORBIDDEN_VOCAB / FORBIDDEN_IDENTITY_TOKENS) | Foreign terminology in a message is detected and logged; IDENTITY-claim tokens (e.g. "I am plankestrator" in an orchestrator message) escalate to a deferred THROW at the next tool call (v6); agent-name tokens stay log-only (legitimate cross-references) |
| 3. Plugin: routing table | workflow-enforcement.ts:1042–1053 | A Task call to an agent outside `ROUTING_TABLES[currentAgent]` → throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT` |

Rules:
1. Closed lists of the other primary's agents are stated explicitly in both prompts — the model must not derive them from the routing table.
2. The OUT OF SCOPE message is ONLY the standard phrase (agents/orchestrator.md type=null rule / agents/plankestrator.md type=null rule), never naming foreign specialists — this reduces forbidden-vocab log noise (layer 2) and eliminates the temptation of "partial" cross-routing.
3. Subagent results suggesting work of the other primary's scope NEVER change the pipeline — the pipeline is frozen; the recommendation goes into the final summary only.
4. "Planning-flavored DEV" stays with the orchestrator (Q3 DECOMPOSITION; superseded rule 2026-09-22) — the main source of false cross-routing is eliminated by the deliverable test (T2 vs T6 / P2).

#### Enforcement gates (v6, workflow-enforcement.ts Part II)

| Violation | Detection point | Delivery | Blocks |
|-----------|-----------------|----------|--------|
| identity missing (first message) | message.updated | deferred flag → unified gate in tool.execute.before | any tool call of the primary |
| pipeline mismatch (PIPELINE TABLE / variants) | message.updated | deferred flag → gate | any tool call |
| next_agent mismatch (real step tracking; whitelists: loopback, nit-skip, Auto-DOCS hook, SUPERCOMPLEX-exempt) | message.updated | deferred flag → gate | any tool call |
| invalid JSON / invalid severity in primary JSON | message.updated | deferred flag → gate | any tool call |
| forbidden IDENTITY claim (identity tokens only; agent-name tokens stay log-only) | message.updated | deferred flag → gate | any tool call |
| identity drift under identity lock | message.updated | DIRECT throw from the event hook (caveat: may be swallowed by the runtime) | remaining handler for that event |
| pipeline changed after Turn 1 (exceptions: provisional classification, BUGFIX continuation, DECOMPOSITION Turn B, nit-skip, Auto-DOCS hook, SUPERCOMPLEX per-plan-step re-emission, MULTI_PHASE phase refinement (null→resolved, once per phase), MULTI_PHASE in-phase Auto-DOCS hook, MULTI_PHASE legal phase transition (+1, phases stable)) | message.updated | deferred flag → gate | any tool call |
| second Task call in the same turn | tool.execute.before | DIRECT throw | the Task call |
| parallel Task from the primary while a subagent runs (sessionID attribution) | tool.execute.before depth-bypass | DIRECT throw (before depth increment) | the Task call |
| 4th rework dispatch per rework-loop | tool.execute.before Task section | DIRECT throw | the Task call |
| 3rd reviewer blocker per rework-loop | message.updated (subagent branch) | deferred flag (cumulative, no recovery) → gate | any tool call until rework-loop end |
| orchestrator self-work markers in message text | message.updated | selfWorkDetected → inspection block | read/grep/glob (Task calls are NOT blocked — delegation is the correction) |
| ack format drift (6 legal variants) | message.updated | warn-only log | nothing (audit) |
| unknown type/complexity/plan_exists combination | validatePipeline | fail-closed → pipeline flag → gate | any tool call |
| Task call while `state: "AWAITING_CONFIRMATION"` (same turn, before user reply) | tool.execute.before | DIRECT throw (confirmation gate) | the Task call |
| illegal phase transition (skip / phases tampering / wrong chain for the phase) | message.updated | deferred flag (pipelineImmutable) → gate | any tool call |
| MULTI_PHASE schema violation (phases 2–3, unique ids, depends_on ⊆ earlier, ≤1 SUPERCOMPLEX, AWAITING/CANCELLED shapes) | message.updated (validateJSONOutput/validatePipeline) | deferred flag (invalidJSON / pipelineMismatch) → gate | any tool call |

Deferred-violation pattern: a throw inside an event hook cannot retract an already-sent message, so message.updated sets a flag and the unified gate in tool.execute.before throws at the primary's NEXT tool call (consume-once; a clean valid message clears message-derived flags — latest-message-wins against streaming artifacts). All v6 state resets in the unconditional session.created reset block AFTER the parentID guard (child sessions never wipe parent state).

**Terminal-turn exemption (v7 clarification):** the shape-based terminal exemption in validatePipeline (`pipeline: []` + `next_agent: null` → valid without further checks) would make an AWAITING_CONFIRMATION turn indistinguishable from a final turn. Therefore `state: "AWAITING_CONFIRMATION"` is validated by an EXPLICIT MULTI_PHASE branch of validatePipeline placed BEFORE the terminal exemption (research §7.5 row 4; plugin `workflow-enforcement.ts`, Phase 3 step 3.4).

## 3. JSON Validation Fields

### orchestrator Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"orchestrator"` |
| `type` | string \| null | `"BUGFIX"`, `"DEVOPS"`, `"DEV"`, `"DOCS"`, `"MULTI_PHASE"`, `null` |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `"DEEP"`, `"SUPERCOMPLEX"`, `null` |
| `plan_exists` | boolean \| null | `true`, `false`, `null` |
| `plan_source` | string \| null | description or `null` |
| `goal` | string | one sentence description |
| `next_agent` | string \| null | agent name from whitelist or `null` |
| `pipeline` | string[] | array of agent names (each from the primary's whitelist — see §2 Pipeline Notation) or `[]` |

**Conditional fields (MULTI_PHASE only):** `state`, `phases`, `current_phase` — REQUIRED when `type: "MULTI_PHASE"`, ABSENT otherwise (backward compatible; the plugin enforces conditionally in validateJSONOutput).

### Multi-Phase Fields (orchestrator)

Conditional on `type: "MULTI_PHASE"` — absent in all other turns (backward compatible).

| Field | Type | Valid Values |
|-------|------|--------------|
| `state` | string \| null | `"AWAITING_CONFIRMATION"` (plan shown, Task forbidden), `"CANCELLED"` (user rejected), `null`/absent (executing / final summary) |
| `phases` | array | 2–3 objects: `{id: "P<n>" unique, type: BUGFIX\|DEVOPS\|DEV\|DOCS, complexity: SIMPLE\|COMPLEX\|DEEP\|SUPERCOMPLEX\|null, plan_exists: bool\|null, goal: string, depends_on: [ids of EARLIER phases only; MVP: exactly [previous id], P1 → []]}` |
| `current_phase` | string \| null | id from `phases[]`, or `null` iff `state ∈ {AWAITING_CONFIRMATION, CANCELLED}` |

**Rules:**
- Exactly ONE start phase: `depends_on: []` = `phases[0]`.
- ≤1 SUPERCOMPLEX phase per plan; SUPERCOMPLEX ⇒ `plan_exists: true` (enforced on executing turns; on the AWAITING turn `null` is allowed until the in-phase DECOMPOSITION resolves it).
- Phase refinement: a phase's `complexity`/`plan_exists` may be refined `null → value` ONCE, for the CURRENT phase only; all other fields and all other phases are FROZEN.
- Shapes: `state ∈ {AWAITING_CONFIRMATION, CANCELLED}` ⇒ `pipeline: []` + `next_agent: null` + `current_phase: null`.

**Phase Result envelope (canonical JSON spec — duplicated from §2 Multi-Phase Pipelines; NOT part of the orchestrator JSON: it travels inside Task prompts and PHASE_STATE.md):**

```json
{
  "phase_id": "P1",
  "phase_type": "BUGFIX",
  "status": "SUCCESS | FAILED | SKIPPED",
  "summary": "≤3 sentences",
  "artifacts": ["src/auth/middleware.ts", "bug_plan.md"],
  "facts": { "tests": "green", "files_changed": 3, "public_api_changed": false },
  "blockers": [],
  "docs_deferred_to": "P3 | null"
}
```

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

Reviewer subagents (`dev-reviewer`, `consistency-checker`, `advisor` — см. §2 Advisor Step) tag their final JSON with a mandatory `severity` field. Source: OMP Advisor Watchdog severity semantics (nit = aside, concern = steer, blocker = triggered turn).

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
- Same-pattern fixed-name file pointers in orchestrator pipelines (passed via Task prompts, not JSON fields): `bug_plan.md` (plan-bug → execute-bug), `dev_plan.md` (dev-planner → dev-professor), `docs_plan.md` (docs-planner → docs-writer), `PHASE_STATE.md` (orchestrator → utility-scribe → next phase / resume; append-only multi-phase journal — §2 Multi-Phase Pipelines).

## 4. MCP Servers

All MCP servers are configured in `opencode.json` under the `mcp` section. Three Z.AI servers and the media server are proxied through Bifrost LiteLLM.

| Server Name | MCP Tool Prefix | Purpose |
|-------------|-----------------|---------|
| zai_zread | `zai_zread_` | GitHub repository reading: `zai_zread_search_doc`, `zai_zread_get_repo_structure`, `zai_zread_read_file` |
| zai_web_search | `zai_web_search_` | Web search: `zai_web_search_web_search_prime` |
| zai_web_reader | `zai_web_reader_` | URL content reading: `zai_web_reader_webReader` |
| serena | `serena_` | Code symbol operations: `find_symbol`, `rename_symbol`, etc. |
| unity-mcp | `unity-mcp.*` | Unity Editor operations: `manage_gameobject`, `manage_scene`, etc. |
| media | `media_` | Media generation (remote via Bifrost, 9 tools): `media_media-generate_image`, `media_media-edit_image`, `media_media-generate_video`, `media_media-video_status`, `media_media-synthesize_speech`, `media_media-clone_speech`, `media_media-register_voice_clone`, `media_media-transcribe_audio`, `media_media-list_media_models` — consumed by image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber. Role split: voice-clone owns cloning (zero-shot `clone_speech` + persistent `register_voice_clone`); voice-synthesizer owns all synthesis incl. registered clones via `voice_id` |

### Usage Rules

- Use `zai_web_search` for all web searches — do NOT use `webfetch`
- Use `zai_web_reader` for reading URL content — do NOT use `webfetch`
- Use `zai_zread` tools for GitHub repositories — do NOT use `webfetch` or manual browsing
- Use `media` MCP tools for image/video/audio generation and transcription — media agents: image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber (all return hosted URLs, TTL 24 h — never base64 in context)
- Image ANALYSIS is NOT an MCP tool: delegate to the `view-image` agent via Task tool (`subagent_type: "view-image"`); do NOT use MCP servers or other means for analyzing screenshots, diagrams, error images

### MCP Proxy Architecture

All three Z.AI MCP servers (`zai_zread`, `zai_web_search`, `zai_web_reader`) are routed through Bifrost LiteLLM at `https://hcbifrost.herocraft.com/litellm/`. Authentication uses a single `LITELLM_API_KEY` environment variable shared with the LLM provider. The `media` server is likewise remote via Bifrost (`https://hcbifrost.herocraft.com/litellm/media/mcp`) with the same `LITELLM_API_KEY`.

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

### ALL Agents Have unity-mcp Access (exceptions: scout, codebase-analyzer, advisor, view-image, git-commit, voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone)

unity-mcp is available for ALL agents, not just orchestrator and plankestrator.

**Deny is explicit, never implicit.** Unlisted MCP tools default to `allow` in opencode, so every exception below carries an explicit `unity-mcp.*: deny` in BOTH the agent frontmatter and the `opencode.json` agent entry — absence of the key is NOT a deny and MUST NOT be documented as one.

| Agent Category | unity-mcp Permission | Reason |
|----------------|---------------------|--------|
| Primary agents (orchestrator, plankestrator) | no explicit entry (opencode default `allow`) — runtime-blocked | They are not given an explicit `unity-mcp.*` rule, so opencode's default (`allow`) would apply; however the `workflow-enforcement.ts` plugin gate `PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}` blocks ALL other tool calls (including unity-mcp) once identity is locked. The real gate is the plugin, not the frontmatter/opencode.json declaration. |
| Implementation agents | `unity-mcp.*: allow` | worker, bugfix, execute-bug, rework implement Unity changes |
| Development agents | `unity-mcp.*: allow` | dev-professor, dev-reviewer, dev-planner guide Unity development |
| Validation agents | `unity-mcp.*: allow` | consistency-checker, utility, docs-writer validate Unity code |
| DevOps agents | `unity-mcp.*: allow` | devops-agent, devops-reviewer, bugfix-triage, plan-bug manage Unity builds |
| MCP agents | `unity-mcp.*: allow` | mcp-github, mcp-read, mcp-search, summarizer read Unity content |
| Planning agents | `unity-mcp.*: allow` | plan-writer-*, plan-reviewer-*, research-writer-*, research-reviewer plan Unity features |
| Read-only agents | `unity-mcp.*: allow` | devops-readonly reads Unity DevOps info |
| Read-only recon agents | ❌ `unity-mcp.*: deny` | scout, codebase-analyzer — local filesystem recon only (read/glob/grep); unity-mcp is mutating — explicit deny in frontmatter + opencode.json |
| Advisory agent | ❌ `unity-mcp.*: deny` | advisor is strictly read-only (read/grep/glob + read-only serena); unity-mcp tools are mutating — explicit deny in frontmatter + opencode.json |
| Vision / git-utility agents | ❌ `unity-mcp.*: deny` | view-image (vision analysis only) and git-commit (git operations only) never touch Unity — explicit deny in frontmatter + opencode.json |
| Media agents | ❌ `unity-mcp.*: deny` | image-creator, video-generator, voice-synthesizer, voice-clone, voice-transcriber work exclusively through the media MCP server — unity-mcp and all other MCP servers are denied in their frontmatter and opencode.json entries |

### unity-mcp Tools Available

All agents EXCEPT the explicit deny-exceptions above can use these unity-mcp tools:
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

1. **Session start** — `workflow-enforcement.ts` reads the agent from session metadata. On opencode 1.18.34 the authoritative agent arrives in the **`session.updated`** event (`info.agent`); `session.created` fires BEFORE the agent is bound and may carry no `agent` field, so it is kept for legacy compatibility only. Priority order: `session.updated.info.agent` → `session.created.info.agent` → alternate field names (`parent_agent` / `primary_agent` / `agentName`) → title → description. If it identifies `orchestrator` or `plankestrator`, it sets `identityLocked = true` and records `lockedAgentName`. The lock is established once and idempotent — repeated events carrying the same agent do not re-bind it (guard `!identityLocked || lockedAgentName !== suDetected`), so the agent cannot be re-bound after this point.
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
| `generate-image` / `generate-image-gpt` | REMOVE | Use `image-creator` (media MCP) |
| `audio-synthesize` / `audio-transcribe` skills | REMOVE | Use media MCP tools via voice-synthesizer / voice-clone / voice-transcriber |
| `image-gen` skill | REMOVE | Use `media_media-generate_image` / `media_media-edit_image` |

## 7. Primary Agent Roles

| Agent | Handles | Workflows |
|-------|---------|-----------|
| orchestrator | Operational and execution tasks | BUGFIX, DEVOPS, DEV, DOCS |
| plankestrator | Planning and research tasks | PLAN, RESEARCH, RESEARCH+PLAN |

Agents do NOT call each other — the user must manually switch between them.

## 8. File Locations

### Live (runtime, единственное место правок)
`C:\Users\Admin\.config\opencode\`
- `opencode.json` — конфиг (провайдеры, модели, permissions)
- `agents/*.md` — 41 определений агентов (frontmatter + промпт)
- `plugins/workflow-enforcement.ts` — enforcement-плагин
- `skills/git-commit/` — юзер-скилл
- `AGENTS.md` — глобальные инструкции (lean)
- `REVIEW_CONTEXT.md` — user-level контекст ревьюеров (намеренно отличается от проектного)

### Repo (коммит-снапшот live)
`P:\Programming\Рефакторинг\`
- `agents/` — зеркало live agents/ (41 .md)
- `opencode.json` — зеркало
- `plugins/workflow-enforcement.ts` — зеркало
- `skills/git-commit/` — зеркало
- `AGENTS.global.md` — зеркало live AGENTS.md (имя ≠ AGENTS.md → opencode не грузит)
- `.opencode/skills/` — 11 ПРОЕКТНЫХ скиллов (правятся здесь, НЕ синхронизируются)
- `ARCHITECTURE.md` — канон проекта (этот файл; в live НЕ копируется)
- `REVIEW_CONTEXT.md` — проектный контекст ревьюеров
- `CHANGELOG.md`

### Sync-механика (5 пар)
| # | Live | Repo |
|---|------|------|
| 1 | `agents/*.md` | `agents/*.md` |
| 2 | `opencode.json` | `opencode.json` |
| 3 | `plugins/workflow-enforcement.ts` | `plugins/workflow-enforcement.ts` |
| 4 | `skills/git-commit/*` | `skills/git-commit/*` |
| 5 | `AGENTS.md` | `AGENTS.global.md` |

**Направления:**
- `save` (live → repo) — основной режим: правки делаются в live, перед коммитом снапшотим. Выполняется: config-sync `--save`, или механически consistency-checker'ом при обнаружении drift
- `restore` (repo → live) — ТОЛЬКО явный аварийный откат: `config-sync --restore`. Никогда не выполняется автоматически

### Data Storage

| Item | Path | Format |
|------|------|--------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | JSON |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Various |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | JSON |
| Logs | `~/.local/share/opencode/log/` | `.log` files |

### Per-Audience Context Files (v5, OMP WATCHDOG.md analog)

Конвенция: инструкции для конкретного класса агентов хранятся ОТДЕЛЬНО от общего AGENTS.md и подключаются только в промпты этого класса. Действующие файлы: `REVIEW_CONTEXT.md` (reviewer-агенты; два уровня — project root и user-level `~/.config/opencode/`). Будущие кандидаты: `PLAN_CONTEXT.md` (planner-агенты) — вне текущего объёма. Правило: «every loaded instruction consumes context» — файл ≤150 строк.

## 9. Plugin Hooks

The workflow-enforcement plugin implements the following lifecycle hooks (event-shape compatible with opencode 1.18.34+):

| Hook | When | Purpose |
|------|------|---------|
| `tool.execute.before` | Before any tool call | Routing table enforcement; JSON-before-Task gate (no grace for locked agents, v4); inspection budget & post-pipeline inspection ban for plankestrator (v4); suppressed while a Task subagent runs (`activeTaskDepth > 0`, v4); unified deferred-violation gate (v6); max ONE Task per turn + parallel-Task block from primary (v6); rework max 3 per rework-loop (v6); orchestrator self-work inspection block (v6); confirmation gate — Task blocked while AWAITING_CONFIRMATION in the same turn (v7) |
| `tool.execute.after` | After tool completes | Logs tool completion |
| `message.part.updated` | Text part updated | Text transport (v7.1): buffers cumulative text parts (`part.type === "text"`); reasoning parts ignored so JSON extraction stays clean |
| `message.part.delta` | Text delta streamed | Text transport (v7.1): accumulates incremental deltas, but only for parts already known to be `type === "text"` (reasoning-delta filter) |
| `message.updated` | Message finalized | Finalization-gated (v7.1): validates JSON output format ONLY once the message is finalized (`finish="stop"` or `time.completed`); text is assembled from the `message.part.*` buffers (INVALID JSON logged as error, v4); detects identity drift (identity-lock v3 — a locked agent claiming a different identity is rejected, L492); detects forbidden vocabulary and self-work content markers (v4); skipped while a Task subagent runs; deferred-violation flags escalate log-only checks to a THROW at the next tool call (v6); pipeline step tracking + immutability after Turn 1 (v6); blocker counter with BLOCKER STOP after 3 (v6); primary severity validation (v6); ack format audit (v6, warn-only); identity drift under lock throws directly (v6); multi-phase per-phase pipeline validation (key = phase's type-complexity-plan_exists); confirmation-gate tracking (AWAITING set / user-reply clear); phase-transition mutation whitelist; blockerStop reset on legal phase transition (v7) |
| `session.created` | New session starts | Legacy compatibility: detects which agent is running when `session.created` carries the agent; CHILD (subagent) sessions preserve the parent's identity-lock state (parentID guard, v4) |
| `session.updated` | Session metadata updated | P0 (v7.1): detects + locks the agent from `info.agent` (authoritative on opencode 1.18.34, where `session.created` fires before the agent is bound); re-checks built-in Plan mode; CHILD sessions skipped (parentID guard) |
| `session.idle` | Session ends | Logs workflow summary |

**Event shape compatibility (opencode 1.18.34+):**
Плагин поддерживает два формата событий:
- **Новый (1.18.34+):** `properties.info` + `message.part.updated`/`message.part.delta` + `session.updated`
- **Legacy:** `properties.message` + `properties.session` + `session.created`

Нормализация: `resolveSessionData()` и `resolveMessage()` хелперы обеспечивают единый интерфейс.

Note: the session lifecycle events (`session.created`, `session.updated`, `session.idle`, `message.part.updated`, `message.part.delta`, `message.updated`) are dispatched inside the plugin's single `event` hook. The `session.updated` branch detects + locks the agent from `info.agent` (opencode 1.18.34); `message.part.updated`/`message.part.delta` buffer text parts (reasoning-filtered); `message.updated` finalizes and validates (only on `finish="stop"` || `time.completed`). Identity-drift detection still lives in the `message.updated` branch.

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

## Infrastructure Export (on-demand)

Инфраструктурная документация (MCP_SETUP-подобные мануалы для развёртывания на другой машине) НЕ поддерживается в репо. Генерируется с нуля по запросу из актуальных конфигов (opencode.json, agents/, plugins/, skills/). Не синхронизировать, не чинить консистентность.
