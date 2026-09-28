# Implementation Plan — Auto-DOCS fix, direct docs-writer, scout→M3.1, codebase-analyzer, sync, verify, commit

> План составлен 2026-09-28 по результатам двух волн recon + прямой верификации якорей.
> Все line numbers проверены прямым чтением на момент составления. Перед каждой string-replace
> правкой проверять уникальность якоря: `rg -c "<pattern>" <file>` → 1 (per project convention).

## Goal

7 задач (пользовательские №1–7):
1. Починить Auto-DOCS hook в `orchestrator.md` (строка 112 «don't analyze» против строки 61 — hook никогда не срабатывает, т.к. orchestrator не парсит JSON исполнителя).
2. Разрешить dev-агентам (worker, dev-professor, execute-bug) прямой вызов `docs-writer` через Task для пользовательской документации.
3. Мигрировать `scout` на `bifrost-litellm/MiniMax-M3.1-Flash-Preview`.
4. Создать агента `codebase-analyzer` на `bifrost-litellm/Kimi K2.8` (read-only анализ кодовых баз); вызывается из orchestrator (routing table), dev-planner, plan-bug.
5. Синхронизация live → repo.
6. Верификация: `config-sync --plan` + `integrity-check`.
7. Коммит через агента `git-commit` (Task tool). НИКАКИХ прямых `git commit`.

## ⚠️ Discrepancies с исходным описанием задач (verified facts)

| # | В задаче сказано | Фактическое состояние | Вывод |
|---|---|---|---|
| D1 | «scout.md: заменить MiniMax-M3 → M3.1» | `scout.md` line 4: `model: bifrost-litellm/mimo-v2.5` | Цель та же: заменить ТЕКУЩУЮ модель на `bifrost-litellm/MiniMax-M3.1-Flash-Preview` |
| D2 | Задача 5: `deploy-package\*`, `opencode-config\ARCHITECTURE.md` | **Каталогов не существует** (удалены при реструктуризации, см. CHANGELOG [Unreleased] line 12). Синхронизация = skill `config-sync` (5 пар live↔repo). `ARCHITECTURE.md` — ЕДИНСТВЕННАЯ копия в корне репо (line 3: «exists ONLY here… NOT copied to the live config») | Задача 5 заменяется на `config-sync --save`; копирование ARCHITECTURE.md не нужно |
| D3 | Задача 4: «добавить в task permissions» | integrity-check Check #3 требует: live agents count == repo count == **opencode.json `agent` entries count** → нужен ПОЛНЫЙ agent-блок `codebase-analyzer` в opencode.json, а не только task-разрешения | Блок создаёт skill `agent-add` (см. Phase 4) |
| D4 | Задача 4: файлы — только .md/json/plugin/ARCH | `orchestrator.md` line 26 содержит зеркало `OPENCODE_ROUTING_TABLE = [...]` — должно совпадать с whitelist | Skill `agent-add` правит его автоматически (Update target #4) |
| D5 | Первая волна recon давала opencode.json = 2089 строк | Прямое чтение: live и repo = **2119 строк** (идентичны), plugin live и repo = **1421** | Все якоря в этом плане — из прямого чтения (валидны). После вставки нового agent-блока скиллом номера строк СЪЕДУТ — далее только текстовые якоря |

## Architecture (подход и ключевые решения)

**Live-first:** все рантайм-правки — в `C:\Users\Admin\.config\opencode\` (единственное место правок, ARCHITECTURE.md §8 line 826). Repo `P:\Programming\Рефакторинг\` — зеркало (agents/, opencode.json, plugins/) + канонические ARCHITECTURE.md/CHANGELOG.md. Зеркало обновляется ТОЛЬКО `config-sync --save` (hard rule скиллов: «Never edit the repo agents/ mirror directly»).

**Permission Authority (ARCHITECTURE.md lines 229–261):** frontmatter .md мержится ПОСЛЕ opencode.json (mergeDeep, frontmatter wins on shared keys); `task`-allowlists живут в opencode.json (line 252: «JSON keeps task allowlist»). worker/dev-professor/execute-bug НЕ имеют `task` в frontmatter → для задачи 2 достаточно правки opencode.json. dev-planner/plan-bug имеют `task` в frontmatter (прецедент scout — в обоих местах) → для задачи 4 правим оба места.

**Стандартные скиллы проекта** (`.opencode\skills\`, запуск из корня репо):
- `agent-add` — end-to-end добавление субагента (5 целей: live .md, live opencode.json (agent-блок + task allow primary), live plugin ROUTING_TABLES, live orchestrator.md OPENCODE_ROUTING_TABLE, ARCHITECTURE.md (whitelist+counters+Subagent Models+Model Roles)). All-or-nothing, fail-closed counter cross-check.
- `config-sync` (`sync.ps1 -Save/-Plan`), `integrity-check` (`check.ps1`), `backup-snapshot` (`snapshot.ps1`).
- `agent-model-migrate` для задачи 3 НЕ используем (обоснование в Phase 3) — правки ручные, якоря известны.

**Порядок фаз:** backup → pre-check drift → задачи 1–3 (не трогают counters) → задача 4 (skill: counter cross-check gate требует согласованных счётчиков ДО запуска; ручные opencode.json task-правки для dev-planner/plan-bug делаем ДО скилла, т.к. скилл вставляет новый agent-блок в начало секции `"agent"` и сдвигает номера строк) → CHANGELOG → JSON-валидация → sync --save → verify → git-commit.

**Ключевые тексты для правок** — в Implementation Details (byte-exact old → new).

## Files to Modify

### Live (`C:\Users\Admin\.config\opencode\`)
1. `agents\orchestrator.md` (191 строк) — задача 1: replace line 112; задача 4: line 26 routing mirror (skill) + guidance в line 101
2. `agents\worker.md` (54) — задача 2: новая секция перед «Output Specification» (line 36)
3. `agents\dev-professor.md` (67) — задача 2: новая секция перед «Output Specification» (line 49)
4. `agents\execute-bug.md` (67) — задача 2: новая секция перед «Output Specification» (line 46)
5. `agents\docs-writer.md` (61) — задача 2: append к Trigger-line 13
6. `agents\scout.md` (68) — задача 3: line 4 model
7. `agents\dev-planner.md` (114) — задача 3: lines 31, 34 (mimo-v2.5 mentions); задача 4: frontmatter task + section point 5
8. `agents\plan-bug.md` (51) — задача 3: line 32; задача 4: frontmatter task + section point 4
9. `agents\plan-writer-complex.md` — задача 3: line 30 (mimo-v2.5 mention)
10. `agents\research-writer-simple.md` — задача 3: line 41 (mimo-v2.5 mention)
11. `agents\codebase-analyzer.md` — задача 4: **CREATE** (skill agent-add, body из temp-файла)
12. `opencode.json` (2119) — задача 2: task-блоки worker (1431–1434), dev-professor (1604–1607), execute-bug (2014–2017); задача 4: task-блоки dev-planner (1342–1346), plan-bug (1543–1547) + новый agent-блок и orchestrator task allow (skill)
13. `plugins\workflow-enforcement.ts` (1421) — задача 4: ROUTING_TABLES.orchestrator += "codebase-analyzer" (skill)

### Repo (`P:\Programming\Рефакторинг\`)
14. `ARCHITECTURE.md` (937) — задачи 1,2,3,4: см. Implementation Details (часть правок делает skill)
15. `CHANGELOG.md` (370) — записи [Unreleased]
16. Зеркала `agents\*`, `opencode.json`, `plugins\workflow-enforcement.ts` — ТОЛЬКО через `config-sync --save` (Phase 6)

### Temp (gitignored)
17. `output\codebase-analyzer-body.md` — body-файл для `-BodyFile` (output/ в .gitignore line 20)

---

## Implementation Details

### Phase 0 — Backup + pre-checks

```powershell
# из корня репо P:\Programming\Рефакторинг
& ".opencode\skills\backup-snapshot\scripts\snapshot.ps1" -Full -Label "before_docs_hook_analyzer"
# pre-check: ожидаем ОТСУТСТВИЕ drift (live 2119 == repo 2119, plugin 1421 == 1421 — уже проверено)
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan
```
Если `-Plan` показывает PRE-EXISTING drift, не относящийся к нашим правкам, — зафиксировать список в отчёте (он будет втянут в repo при `--save`; это штатная семантика снапшота, но пользователь должен знать).

### Phase 1 — Задача 1: Auto-DOCS hook (orchestrator.md)

**1.1** `agents\orchestrator.md` line 112. Якорь уникален (`rg -c "advance, don't analyze" → 1`).

OLD (exact):
```
A subagent result arriving is your next turn — advance, don't analyze it.
```
NEW:
```
A subagent result arriving is your next turn — advance, don't analyze it. Mechanical field reads are NOT analysis: when an implementation agent (dev-professor / execute-bug / worker) returns JSON, parse its `requires_docs_update` field — if `true`, run `["docs-writer", "utility"]` after the final `utility` (Auto-DOCS hook). The same applies to the other fields this algorithm consumes mechanically: `TRIAGE_RESULT` (BUGFIX continuation), `severity` / `escalate_to` (SEVERITY RULES), `plan_gap`, `steps` (DECOMPOSITION).
```
(Покрывает и SUPERCOMPLEX-вариант hook'а line 95: флаг трекается между шагами тем же механическим чтением.)

**1.2** Канон `ARCHITECTURE.md` §Auto-DOCS Hook (lines 493–513) — вставить ПОСЛЕ line 497 (`**Trigger:** call … requires_docs_update: true.`):
```
**Orchestrator-side parse (mandatory):** the orchestrator MUST parse the `requires_docs_update` field from the arriving implementation agent's JSON. This is a mechanical field read — an explicit exception to the orchestrator's "advance, don't analyze" turn rule (mirrored in `agents/orchestrator.md` TURN ALGORITHM).
```

**1.3** Верификация флага у implementation-агентов — **УЖЕ ПРОВЕРЕНА, правок не требует**:
- `worker.md` line 43 (`"requires_docs_update": true,`) + правила lines 48–54
- `dev-professor.md` line 56 + правила lines 61–67
- `execute-bug.md` line 53 + правила lines 59–65
- Плагин валидирует тип поля: `workflow-enforcement.ts` lines 1364–1385, `DOCS_UPDATE_AGENTS = ["execute-bug", "dev-professor", "worker", "docs-writer"]` (line 1366) — boolean|null + enum docs_update_reason.
В план-отчёт внести: «проверено, все три агента выставляют флаг, плагинная валидация присутствует».

### Phase 2 — Задача 2: прямой вызов docs-writer

**2.1** `opencode.json` — три task-блока (паттерн `"task": {\n "*": "deny",\n "view-image": "allow"\n }` ПОВТОРЯЕТСЯ у десятков агентов → якорь ОБЯЗАН включать ключ агента; использовать regex-mode `serena_replace_content` с non-greedy `.*?`):

- worker (блок line 1418, task 1431–1434): regex `"worker": \{.*?"task": \{\s*"\*": "deny",\s*"view-image": "allow"` → в repl после `"view-image": "allow"` добавить `,\n          "docs-writer": "allow"` (отступ записей task = 10 пробелов).
- dev-professor (блок line 1591, task 1604–1607): regex `"dev-professor": \{.*?"task": \{\s*"\*": "deny",\s*"view-image": "allow"` → аналогично.
- execute-bug (блок line 2001, task 2014–2017): regex `"execute-bug": \{.*?"task": \{\s*"\*": "deny",\s*"view-image": "allow"` → аналогично.

Каждый regex перед применением: убедиться что находит РОВНО 1 вхождение (non-greedy останавливается на первом `"view-image": "allow"` внутри своего блока — проверено структурой). Frontmatter этих агентов `task` НЕ содержит (worker.md lines 6–11: только edit/bash) → merge сохранит JSON-allowlist (Permission Authority line 252). Frontmatter не правим.

**2.2** Промпты — вставить НОВУЮ секцию перед строкой `Output Specification (required for orchestrator auto-DOCS hook):` в трёх файлах (worker.md перед line 36; dev-professor.md перед line 49; execute-bug.md перед line 46). Текст одинаковый:

```markdown
## Direct docs-writer call (user-facing documentation)

If DURING your work you realize that user-facing documentation is needed (instructions for users, portal guides, usage how-tos), call `docs-writer` directly via the Task tool (`subagent_type: "docs-writer"`):
- Pass a SELF-CONTAINED prompt: what to document, which files/APIs/flows changed, target audience, language of the existing docs
- docs-writer reads the code and writes the documentation itself — do NOT write user docs personally
- This does NOT replace the `requires_docs_update` flag: set it in your final JSON per the Output Specification rules regardless of any direct docs-writer call
- At most ONE docs-writer call per task, and ONLY for user-facing docs — code comments/docstrings remain your own job
```

**2.3** `docs-writer.md` line 13 — append к Trigger-предложению (после «…code comments, docstrings.»):
```
 May also be called DIRECTLY by an implementation agent (worker / dev-professor / execute-bug) mid-task for user-facing docs — then the Task prompt is your full spec (no docs_plan.md, no DOCS pipeline).
```

**2.4** `ARCHITECTURE.md` — новая под-секция в конце §Auto-DOCS Hook: вставить ПОСЛЕ line 512 (`- PLAN, RESEARCH (out of orchestrator's scope)`), ПЕРЕД `### PLAN` (line 514):

```markdown
### Direct docs-writer Call (in-flight, BUGFIX/DEV)

Implementation agents (worker, dev-professor, execute-bug) hold `task.docs-writer: allow` (opencode.json) and MAY call docs-writer directly DURING their step when user-facing documentation is needed (user instructions, portal guides). Rules: at most ONE call per task; the Task prompt must be self-contained (`docs_plan.md` is NOT written for direct calls); a direct call does NOT replace the `requires_docs_update` flag — the Auto-DOCS hook stays independent. Depth: primary(0) → implementation agent(1) → docs-writer(2) — within `subagent_depth: 3`.
```

**2.5** Depth-список ARCHITECTURE line 315 — правится ОДИН раз в Phase 4.5 (добавляет сразу docs-writer и codebase-analyzer).

### Phase 3 — Задача 3: scout → MiniMax-M3.1-Flash-Preview

**Обоснование ручного пути (вместо agent-model-migrate):** модель `MiniMax-M3.1-Flash-Preview` не имеет строки в Model Roles; skill с `-Role micro -Tier low` создал бы ВТОРУЮ строку `micro` (дубль) и оставил старую `micro | mimo-v2.5` с нулём агентов (WARN «role row left with zero agents») → ручная доочистка неизбежна. scout — ЕДИНСТВЕННЫЙ occupant роли `micro`, поэтому модель в строке роли меняется IN PLACE (Model Roles rule 2: «смена модели = правка таблицы ролей + frontmatter + Subagent Models — 2 синхронных места»). Скилл также не правит текстовые упоминания модели в промптах вызывающих агентов (5 мест ниже) — они вне его scope.

**3.1** `agents\scout.md` line 4:
- OLD: `model: bifrost-litellm/mimo-v2.5`
- NEW: `model: bifrost-litellm/MiniMax-M3.1-Flash-Preview`

**3.2** `ARCHITECTURE.md` line 109 (Subagent Models):
- OLD: `| scout | bifrost-litellm/mimo-v2.5 |`
- NEW: `| scout | bifrost-litellm/MiniMax-M3.1-Flash-Preview |`

**3.3** `ARCHITECTURE.md` line 153 (Model Roles, роль micro — model cell in place):
- OLD: `| micro | bifrost-litellm/mimo-v2.5 | low | scout |`
- NEW: `| micro | bifrost-litellm/MiniMax-M3.1-Flash-Preview | low | scout |`

**3.4** Устаревшие упоминания модели scout в промптах вызывающих агентов (verified grep, 4 файла / 5 мест; media-модели `voice/xiaomi/mimo-v2.5-*` в voice-*.md НЕ трогать):
- `dev-planner.md` line 31: `(runs on mimo-v2.5; glob/grep/read only)` → `(runs on MiniMax-M3.1-Flash-Preview; glob/grep/read only)`
- `dev-planner.md` line 34: `scout runs on a cheap model (mimo-v2.5)` → `scout runs on a cheap model (MiniMax-M3.1-Flash-Preview)`
- `plan-bug.md` line 32: `(runs on mimo-v2.5; glob/grep/read only)` → `(runs on MiniMax-M3.1-Flash-Preview; glob/grep/read only)`
- `plan-writer-complex.md` line 30: `(runs on mimo-v2.5; glob/grep/read only)` → `(runs on MiniMax-M3.1-Flash-Preview; glob/grep/read only)`
- `research-writer-simple.md` line 41: `scout is cheaper (mimo-v2.5)` → `scout is cheaper (MiniMax-M3.1-Flash-Preview)`

**3.5** Post-check: `rg -n "mimo-v2\.5" C:\Users\Admin\.config\opencode\agents\` → остаются ТОЛЬКО voice-* media models (`voice/xiaomi/mimo-v2.5-*`) и НИ одного `bifrost-litellm/mimo-v2.5`. Ключ модели существует в provider: `opencode.json` → `provider.bifrost-litellm.models."MiniMax-M3.1-Flash-Preview"` (подтверждено recon; перепроверить `rg -c '"MiniMax-M3.1-Flash-Preview"' opencode.json` ≥ 1).

### Phase 4 — Задача 4: codebase-analyzer (Kimi K2.8)

**4.1** Body-файл для скилла: создать `P:\Programming\Рефакторинг\output\codebase-analyzer-body.md` (output/ gitignored) с телом промпта (без frontmatter — его генерирует skill):

```markdown
You are Codebase Analyzer — a deep codebase analysis agent on a strong model (Kimi K2.8).

Trigger: called via Task by orchestrator (classification-level structure questions), dev-planner or plan-bug when cheap recon (scout) is not enough: dependency analysis, architecture understanding, refactoring impact, cross-module coupling, blast-radius assessment.

Your role:
1. Receive a focused analysis question about the codebase
2. Explore with read / glob / grep ONLY
3. Return a structured analysis report: direct answer + evidence pointers + dependency/impact assessment

## Difference from scout

- scout = cheap file/line reconnaissance ("where is X") — pointers, NO analysis
- codebase-analyzer = structural analysis ("how does X depend on Y", "what breaks if Z changes") — conclusions ARE your deliverable

## Response Format (ALWAYS)

1. **Answer** — direct answer to the question (2-5 sentences)
2. **Evidence** — `path/to/file:LINE` pointers, each with a ≤3-line verbatim excerpt
3. **Dependencies** — modules/symbols involved, coupling direction, call chains
4. **Impact & Risks** — what a change would touch: hidden coupling, edge cases, contract violations

Close every report with:
- **Not found / Not analyzed** — what was searched and deliberately skipped (negative results are facts too)
- **Coverage** — the globs/greps/reads performed, so the caller never repeats them

## HARD PROHIBITIONS

- NO modifications of any kind: edit / write / patch / bash / webfetch / todowrite / question / task are ALL denied by permissions — do not attempt them
- NO invented paths, line numbers, or quotes — every pointer must come from an actual tool result in this session
- NO implementation work beyond the asked question — you analyze, the CALLER decides and implements
- NO dumping file contents beyond the excerpt limit — evidence stays "pointer, not transcript"

## Working Style

- Batch independent glob/grep calls in ONE message (parallel tool calls)
- Start from entry points (public API, composition root, DI/config), follow the dependency direction
- Prefer narrow reads around grep hits over whole-file reads
- Stay on the QUESTION: exhaustive coverage of the question, not of the codebase

## Output Discipline

- Compact report: target ≤80 lines no matter how much you read
- Facts and reasoned conclusions clearly separated (Evidence vs Impact)
```

**4.2** Ручные task-allow правки в `opencode.json` ДО запуска скилла (скилл вставит новый agent-блок ПЕРВЫМ после `"agent": {` и сдвинет номера строк — поэтому сначала эти, якоря текстовые):
- dev-planner (блок line 1325, task 1342–1346): regex `"dev-planner": \{.*?"scout": "allow"` → repl: `"codebase-analyzer": "allow"` новой строкой ПОСЛЕ `"scout": "allow"` (через запятую, 10 пробелов отступа). Т.е. old-fragment `"view-image": "allow",\n          "scout": "allow"` (внутри блока dev-planner) → new `"view-image": "allow",\n          "scout": "allow",\n          "codebase-analyzer": "allow"`.
- plan-bug (блок line 1529, task 1543–1547): аналогично, regex-якорь `"plan-bug": \{.*?"scout": "allow"`.

**4.3** Skill `agent-add` — PlanOnly, затем Apply:

```powershell
& ".opencode\skills\agent-add\scripts\add.ps1" -Agent "codebase-analyzer" -Model "bifrost-litellm/Kimi K2.8" -Description "Codebase analysis agent. Deep structural analysis of dependencies, architecture, and refactoring impact. Read-only (read/glob/grep). Kimi K2.8." -Primary orchestrator -PermTemplate scout -Role "analyzer" -Tier "mid" -BodyFile ".\output\codebase-analyzer-body.md" -Temperature 0.1 -PlanOnly
# изучить PLAN:/WARN:/DIFF: строки; если counter cross-check BLOCK (DIFF:) — СТОП, разобраться
& ".opencode\skills\agent-add\scripts\add.ps1" ... те же параметры ... -Apply
```

Параметры и почему:
- `-PermTemplate scout` — копирует permission-блоки scout: read/grep/glob allow; edit/write/bash/webfetch/patch/todowrite/question deny; task `{"*": "deny"}` — ТОЧНО spec пользователя «read/glob/grep allow, всё остальное deny» (JSON-блок scout lines 1878–1897 проверен).
- `-Role "analyzer" -Tier "mid"` — Kimi K2.8 маппится на 0 role-строк → gate требует -Role; -Tier создаёт новую строку `| analyzer | bifrost-litellm/Kimi K2.8 | mid | codebase-analyzer |`. Tier=mid: не превышает tier вызывающих planner'ов (plan-bug = plan-flash/mid, dev-planner = plan-strong/top) — prewalk-инверсии нет; codebase-analyzer не входит в planner→executor пары rule 1. Обоснование НОВОЙ роли (rule 3, line 160) — записью в CHANGELOG (Phase 5).
- `-Description` — без `": "` (YAML-грабля), ASCII-only.
- **БЕЗ `-Commit`/`-Push`** — коммит ТОЛЬКО через агента git-commit (HARD RULE global).

Skill выполнит (Update targets 1–5): live `agents\codebase-analyzer.md` (CREATE, LF/UTF-8 no BOM); opencode.json — agent-блок (первым после `"agent": {`) + `"codebase-analyzer": "allow"` в orchestrator task-блоке (после `"voice-clone": "allow"`, line ~1760); plugin `ROUTING_TABLES.orchestrator` += `"codebase-analyzer"` (29 записей); `orchestrator.md` line 26 OPENCODE_ROUTING_TABLE += `"codebase-analyzer"`; ARCHITECTURE.md — whitelist header `(28 agents)`→`(29 agents)` + строка `| 29 | codebase-analyzer | <Description> |`, Agent Count Summary (28→29, 29→30, Grand Total **38**→**39**, **40**→**41**), Note line 65 counters, Subagent Models + Model Roles строки, intro line 132 «40 агентам»→41, Kontrol summy line 155 «38 subagents = 40»→«39 = 41».

**4.4** Post-skill ручные правки (скилл их НЕ покрывает):

(a) `orchestrator.md` line 101, Turn 1 step 2 — append в конец пункта (после «…find a root cause.»):
```
 If scope assessment needs code-structure understanding (dependencies, blast radius), you MAY delegate ONE `codebase-analyzer` Task call before finalizing classification — one extra turn pair, same status as the DECOMPOSITION PROTOCOL exception; its findings inform classification ONLY.
```
(Без этого orchestrator — детерминированный автомат «No improvisation» — никогда не вызовет нового агента. Совместимо с PROHIBITIONS: line 190 «ONE Task call per turn» — вызов и есть единственный Task того хода; line 188 «No read/glob/grep during Turns 2..N» не затрагивается — инспекция только в Turn 1.)

(b) `dev-planner.md` — frontmatter task-блок (после `    "scout": "allow"`, line 14) добавить строку `    "codebase-analyzer": "allow"`; и в секцию `## CODEBASE RECONNAISSANCE — SCOUT WAVES` (lines 29–37) добавить пункт 5 после пункта 4:
```
5. When a recon question needs STRUCTURAL ANALYSIS (dependency chains, architecture understanding, refactoring impact — beyond "locate files/lines"), call `codebase-analyzer` (read-only, strong model) instead of scout: scout locates, codebase-analyzer analyzes; you synthesize the plan from both
```

(c) `plan-bug.md` — frontmatter task-блок (после `    "scout": "allow"`, line 17) добавить `    "codebase-analyzer": "allow"`; в секцию `## BUG INVESTIGATION — SCOUT WAVES` (lines 30–37) добавить пункт 4:
```
4. For STRUCTURAL questions (call chains, coupling, blast radius of a candidate fix) call `codebase-analyzer` (read-only, strong model) — scout locates, codebase-analyzer analyzes; the root-cause conclusion stays YOUR job
```

(d) `ARCHITECTURE.md` line 315 (depth level-2 — ОДНА правка на задачи 2+4):
- OLD: `Уровень 2 (depth 2): scout / mcp-search / mcp-read / mcp-github / devops-readonly`
- NEW: `Уровень 2 (depth 2): scout / codebase-analyzer / mcp-search / mcp-read / mcp-github / devops-readonly / docs-writer (прямой вызов из worker/dev-professor/execute-bug)`

(e) `ARCHITECTURE.md` line 712 (unity-mcp exceptions — codebase-analyzer без unity-mcp, как scout/advisor):
- OLD: `### ALL Agents Have unity-mcp Access (exceptions: scout, advisor, voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone)`
- NEW: `### ALL Agents Have unity-mcp Access (exceptions: scout, codebase-analyzer, advisor, voice-synthesizer, image-creator, video-generator, voice-transcriber, voice-clone)`

(f) `ARCHITECTURE.md` §8 File Locations (скилл не трогает эти счётчики):
- line 829: `- \`agents/*.md\` — 40 определений агентов (frontmatter + промпт)` → `41 определений`
- line 837: `- \`agents/\` — зеркало live agents/ (40 .md)` → `(41 .md)`

(g) Проверить результат скилла в ARCHITECTURE.md: строка whitelist #29 содержит внятную Role-ячейку; Note line 65 — счётчики 39/38/39/41 согласованы; если skill оставил арифметику Note неконсистентной (fail-closed gate это исключает, но проверить) — поправить вручную.

**4.5** Post-checks:
- `rg -c "codebase-analyzer" plugins\workflow-enforcement.ts` → 1; `rg -c "codebase-analyzer" agents\orchestrator.md` → ≥2 (line 26 + guidance); в opencode.json: agent-блок + 4 task-allow (orchestrator, dev-planner, plan-bug) → `rg -c '"codebase-analyzer"' opencode.json` = 4 (3 allow в task + 1 ключ блока… ВНИМАНИЕ: ключ блока `"codebase-analyzer": {` + orchestrator allow + dev-planner allow + plan-bug allow = 4 вхождения).
- Frontmatter нового файла: `model: bifrost-litellm/Kimi K2.8` байт-в-байт (пробел в имени!), description без YAML-ловушек.

### Phase 5 — CHANGELOG.md ([Unreleased], line 8)

- В `### Added` (line 26, по формату существующих записей `- **Bold title** (details)`):
```
- **codebase-analyzer agent** (bifrost-litellm/Kimi K2.8; orchestrator whitelist #29; also callable by dev-planner/plan-bug via task allowlists; read-only preset from scout template; NEW Model Roles row `analyzer`/mid — justification per §Model Roles rule 3: deep structural analysis requires a strong reasoning model absent from existing roles)
- **Direct docs-writer calls from implementation agents** (worker/dev-professor/execute-bug get `task.docs-writer: allow`) for in-flight user-facing documentation; Auto-DOCS hook semantics unchanged; ARCHITECTURE §Direct docs-writer Call documents depth-2 chain
```
- В `### Changed` (line 10):
```
- **scout model migration**: bifrost-litellm/mimo-v2.5 → bifrost-litellm/MiniMax-M3.1-Flash-Preview (Model Roles `micro` row updated in place — scout is the sole occupant; caller prompts updated: dev-planner, plan-bug, plan-writer-complex, research-writer-simple)
```
- Добавить подсекцию `### Fixed` в [Unreleased] (после блока Added, формат как у `### Fixed` line 220 в старых релизах):
```
### Fixed

- **orchestrator Auto-DOCS hook never fired**: TURN ALGORITHM line "advance, don't analyze it" contradicted the hook (PIPELINE TABLE) — added explicit `requires_docs_update` mechanical-parse exception to orchestrator.md and ARCHITECTURE §Auto-DOCS Hook
```

### Phase 6 — Задача 5: Синхронизация (live → repo)

D2: `deploy-package\*` и `opencode-config\*` из формулировки задачи НЕ существуют — полный эквивалент:

```powershell
& ".opencode\skills\config-sync\scripts\sync.ps1" -Save
```
Покрывает пары: `agents\*.md` (7 изменённых + 1 новый codebase-analyzer.md), `opencode.json`, `plugins\workflow-enforcement.ts` (+ skills/git-commit и AGENTS.md — не изменялись, останутся OK). Ожидание: `SYNCED:` строки для изменённых файлов, `SUMMARY:mode=save ... failed=0`, `STATUS:SUCCESS`. EXTRA-файлы не удаляются (never delete). ARCHITECTURE.md и CHANGELOG.md — repo-native, правятся на месте, синхронизация не нужна (line 843: «в live НЕ копируется»).

### Phase 7 — Задача 6: Верификация

```powershell
# 1. JSON validity (live)
powershell -NoProfile -Command "Get-Content 'C:\Users\Admin\.config\opencode\opencode.json' -Raw | ConvertFrom-Json | Out-Null; 'JSON OK'"
# 2. drift отсутствует
& ".opencode\skills\config-sync\scripts\sync.ps1" -Plan   # ожидаем exit 0, ни одной DRIFT: строки
# 3. целостность
& ".opencode\skills\integrity-check\scripts\check.ps1"    # ожидаем exit 0
```
Ожидаемые производные счётчики integrity-check после всех фаз:
- Check #3: live agents 41 == repo agents 41 == opencode.json agent entries 41 (имена совпадают)
- Check #4 orchestrator: plugin ROUTING_TABLES 29 == opencode.json task allow-count 29 == ARCHITECTURE header `(29 agents)` == 29 строк таблицы; plankestrator: 10 (не менялся)
- Check #5: `bifrost-litellm/Kimi K2.8` и `bifrost-litellm/MiniMax-M3.1-Flash-Preview` резолвятся в `provider.bifrost-litellm.models`
Любой FAIL → исправить (live-first) → повторно `--save` → повторить checks.

Дополнительно (не блокирующе): `fc /b` для 3–4 ключевых пар live↔repo (orchestrator.md, opencode.json, workflow-enforcement.ts) → «FC: no differences encountered».

⚠️ Runtime-грабля: конфиг читается на старте сессии — изменения (новая модель scout, codebase-analyzer, task-разрешения) подхватятся ТОЛЬКО в НОВОЙ сессии opencode. Скриптовая верификация выше от сессии не зависит.

### Phase 8 — Задача 7: Коммит

ТОЛЬКО делегированием агенту `git-commit` (Task tool, `subagent_type: "git-commit"`). Прямые `git commit`/`git push` запрещены (HARD RULE). Push НЕ передавать (пользователь не просил).

Ожидаемый набор файлов в коммите: `agents/` (8 .md: orchestrator, worker, dev-professor, execute-bug, docs-writer, scout, dev-planner, plan-bug, plan-writer-complex, research-writer-simple + новый codebase-analyzer.md — итого 11), `opencode.json`, `plugins/workflow-enforcement.ts`, `ARCHITECTURE.md`, `CHANGELOG.md`, опционально `dev_plan.md`.

Подсказка для conventional-commit (агент сформирует сам): `feat(agents): add codebase-analyzer (Kimi K2.8), direct docs-writer calls, fix auto-DOCS hook, migrate scout to MiniMax-M3.1-Flash-Preview`.

---

## Edge Cases

1. **Повторяющиеся task-блоки в opencode.json** — `"*": "deny", "view-image": "allow"` встречается у десятков агентов; КАЖДЫЙ regex-якорь обязан начинаться с уникального ключа агента (`"worker": \{`, `"dev-professor": \{`, …) и быть non-greedy. Проверять 1 вхождение до замены.
2. **Сдвиг номеров строк после agent-add** — скилл вставляет agent-блок первым после `"agent": {` → все правки opencode.json (Phase 2.1, 4.2) выполнять ДО скилла; после — только текстовые якоря.
3. **Имена моделей байт-в-байт** — `Kimi K2.8` содержит ПРОБЕЛ (frontmatter + Model Roles + JSON-ключ provider'а); `MiniMax-M3.1-Flash-Preview` — точный регистр. В regex — экранировать `.` и `/`.
4. **YAML-грабля description** — «`: `» в незакавыченном description ломает парсинг frontmatter; в `-Description` и в new agent .md не использовать «: » (skill auto-wraps + WARN, но лучше чисто).
5. **Двойной docs-writer (direct + hook)** — агент может вызвать docs-writer напрямую И orchestrator позже запустит hook (т.к. `*.md` изменён → `requires_docs_update: true`). Приемлемо: разный scope (user docs vs project docs); промпт прямо говорит «does NOT replace the flag». docs-writer идемпотентен по контенту (пишет по фактическому коду).
6. **Depth-лимит** — `subagent_depth: 3` (opencode.json line 3): primary(0)→worker(1)→docs-writer(2) — в лимите; вложенный Task из docs-writer на depth 2 → depth 3 БУДЕТ ОТКЛОНЁН ядром (не нужно: docs-writer ничего не вызывает; в промпте прямой вызов «at most ONE call»). dev-planner(1)→codebase-analyzer(2) — в лимите.
7. **Counter cross-check gate (agent-add) fail-closed** — если источники счётчиков рассогласованы ДО запуска (BLOCK + DIFF: строки) — не обходить, разобраться; наши Phase 1–3 счётчики не трогают, так что запуск после них безопасен.
8. **`micro` роль после миграции** — строка роли остаётся единственной (model cell in place); НЕ создавать вторую `micro`; не оставлять строк с 0 агентов.
9. **Не трогать media-модели** — `voice/xiaomi/mimo-v2.5-tts|-asr|-voiceclone|-voicedesign` в voice-*.md и ARCHITECTURE §Voice media models — это НЕ модель scout'а.
10. **Plugin-валидация requires_docs_update уже есть** (DOCS_UPDATE_AGENTS lines 1364–1385) — менять workflow-enforcement.ts для задач 1–2 НЕ нужно (единственная правка плагина — ROUTING_TABLES, делает скилл).
11. **`bugfix`-агент** вне DOCS_UPDATE_AGENTS и вне pipeline-строк — не расширять scope (задача 1 говорит только о dev-professor/execute-bug/worker).
12. **Repo-зеркала не редактировать напрямую** — только `config-sync --save`; `fc /b` как контроль.
13. **git-commit только через Task-агента**; скилловые флаги `-Commit`/`-Push` у agent-add НЕ использовать (прямой git в обход HARD RULE).
14. **Новая сессия** — рантайм подхватит конфиги только в новой сессии; пилот-проверка (опционально): `opencode --agent orchestrator`, DEV SIMPLE задача с изменением .md → ожидать срабатывание Auto-DOCS hook (`→ docs-writer` после финального utility).
15. **dev_plan.md** не в .gitignore — решение о включении в коммит оставить git-commit агенту (упомянуть в его промпте).

## Dependencies (что проверить перед стартом)

- [ ] `backup-snapshot -Full` выполнен, `backup\<date>_before_docs_hook_analyzer\` создан
- [ ] `config-sync -Plan` pre-check: drift отсутствует (или зафиксирован pre-existing)
- [ ] `rg -c '"MiniMax-M3.1-Flash-Preview"' opencode.json` ≥ 1 и `rg -c '"Kimi K2.8"' opencode.json` ≥ 1 (ключи в provider.bifrost-litellm.models — recon подтвердил, перепроверить)
- [ ] `rg -c "codebase-analyzer"` = 0 везде (live + repo) — gate «Agent already exists»
- [ ] Счётчики orchestrator согласованы ДО agent-add: plugin array 28 == orchestrator task allows 28 == ARCH header `(28 agents)` == 28 rows == OPENCODE_ROUTING_TABLE (line 26) 28 — скилл проверит сам (counter cross-check), но пред-проверка экономит цикл
- [ ] Все якоря из этого плана уникальны (`rg -c` → 1) в момент правки (файлы могли измениться — перечитать окно перед edit)
- [ ] PowerShell-скрипты скиллов запускаются из корня репо (`P:\Programming\Рефакторинг`)

## Quick reference — сводка правок по задачам

| Задача | Live-файлы | Repo-файлы | Инструмент |
|---|---|---|---|
| 1 Auto-DOCS | orchestrator.md L112 | ARCHITECTURE.md §Auto-DOCS (+L497 insert) | manual edit |
| 2 docs-writer direct | opencode.json ×3 task-блока; worker/dev-professor/execute-bug .md (+секция); docs-writer.md L13 | ARCHITECTURE.md §Direct docs-writer Call (+L512 insert) | manual edit |
| 3 scout model | scout.md L4; dev-planner L31,L34; plan-bug L32; plan-writer-complex L30; research-writer-simple L41 | ARCHITECTURE.md L109, L153 | manual edit (skill не подходит — dубль role row) |
| 4 codebase-analyzer | НОВЫЙ agents\codebase-analyzer.md; opencode.json (agent-блок + orchestrator/dev-planner/plan-bug task); plugin ROUTING_TABLES; orchestrator.md L26+L101; dev-planner/plan-bug frontmatter+секции | ARCHITECTURE.md (whitelist/counts/tables — skill; L315/L712/L829/L837 — manual) | **agent-add skill** (-PermTemplate scout, -Role analyzer -Tier mid) + manual |
| 5 sync | — | agents/, opencode.json, plugins/ (зеркала) | config-sync --save |
| 6 verify | — | — | JSON one-liner + sync --plan + integrity-check |
| 7 commit | — | все изменённые repo-файлы | Task → git-commit агент |
