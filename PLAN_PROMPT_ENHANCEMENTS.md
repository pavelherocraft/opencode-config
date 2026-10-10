# Prompt Enhancements for Primary Agents (orchestrator + plankestrator)

## Goal

Усилить промпты `orchestrator.md` и `plankestrator.md` для улучшения классификации задач:

1. **Описания пайплайнов** — для каждой строки PIPELINE TABLE: что делает, когда использовать, агенты и роли, ожидаемый результат.
2. **Примеры** — для каждого пайплайна: запрос → классификация → пайплайн → объяснение (включая негативные примеры).
3. **Усиленные правила** — decision tree для ВСЕХ типов (не только DEV), edge cases, чёткие границы, cross-routing prevention.
4. **Часть II (Phase 9–17)** — plugin-enforcement: реализовать исправления P0/P1 из `RESEARCH_PIPELINE_ENHANCEMENTS.md` (2026-09-29) в `workflow-enforcement.ts`: эскалация log-only проверок в THROW (P0-1), трекинг шага пайплайна вместо TODO-заглушки (P0-2), fail-closed `validatePipeline` (P0-3), SELF_WORK_MARKERS для orchestrator (P1-4), max ONE Task per turn (P1-5), rework max 3 + blocker stop (P1-6), severity-гейт primary (P1-7), строгий ack-формат (P1-8), иммутабельность pipeline (P1-9).

**Ключевой принцип:** PIPELINE TABLE не изменяется ни на байт (плагин `workflow-enforcement.ts` валидирует пайплайны против таблицы; `ROUTING_TABLES` на :56–57 плагина остаются в силе). Все добавления — описательные/уточняющие секции. Новые СЕМАНТИЧЕСКИЕ правила (decision trees, приоритеты смешанных запросов, границы) зеркалятся в `ARCHITECTURE.md` §2 в том же коммите (требование ARCHITECTURE.md:393 и :403).

**Языковая конвенция:** текст вставок в промпты — английский (консистентно с существующими секциями); пользовательские запросы в примерах — русские (консистентно с существующим EXAMPLES в plankestrator.md:112). Вставки в ARCHITECTURE.md — английские.

## Текущее состояние (факты из recon)

| Файл | Строк | Что есть | Чего нет |
|------|-------|----------|----------|
| `C:\Users\Admin\.config\opencode\agents\orchestrator.md` | 205 | PIPELINE TABLE (:43–52), BUGFIX continuation (:54–57), SUPERCOMPLEX stages (:63–96), TURN ALGORITHM (:98–113), SEVERITY/ADVISOR rules (:132–148), CLASSIFICATION RULES с DEV decision tree Q1–Q5 (:150–181), PROHIBITIONS (:183–194), PLUGIN ENFORCEMENT (:196–205) | Описаний пайплайнов, примеров (0 шт.), decision tree для выбора TYPE (T-уровень), edge cases, явного cross-routing раздела |
| `C:\Users\Admin\.config\opencode\agents\plankestrator.md` | 174 | PIPELINE TABLE (:43–52), TURN ALGORITHM (:54–77), CLASSIFICATION RULES (:95–108), ОДИН пример (:110–149), PROHIBITIONS (:151–164), PLUGIN ENFORCEMENT (:166–174) | Описаний пайплайнов, примеров на 5 из 6 строк, decision tree выбора TYPE, edge cases, cross-routing раздела |
| `P:\Programming\Рефакторинг\ARCHITECTURE.md` | 951 | §2 Pipelines (:353–550): флоу всех пайплайнов, DEV Complexity Classification (:401–421), правило single source of truth (:393), mirror-правило same-commit (:403) | Type Selection tree, PLAN vs RESEARCH boundary, Cross-Routing Prevention |
| `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | 1584 | Forbidden-vocab check (:617–646, **log-only, не бросает**), routing-table enforcement (:1042–1053, **бросает**), FORBIDDEN_VOCAB (:142–153), TODO-заглушка currentStep (:573), fail-open validatePipeline (:1429–1431) | **Часть I (Phase 1–8): изменений НЕ ТРЕБУЕТ. Часть II (Phase 9–17): изменяется** — эскалация log-only в THROW, трекинг шага, fail-closed, счётчики (см. Часть II ниже) |

**Найденные рассогласования (чинятся попутно, см. Phase 3/6):**
- `plankestrator.md:156` — «counting steps in plan files (SUPERCOMPLEX classification)»: SUPERCOMPLEX не существует в scope plankestrator (copy-paste из orchestrator).
- `orchestrator.md:188` — запрещает read/grep/glob «кроме подсчёта шагов», но :102 (TURN ALGORITHM) разрешает glob/grep «to confirm scope» в Turn 1. Противоречие.

## Files и карта вставок (точные якоря)

| # | Файл | Операция | Якорь (стабильный, до вставки) |
|---|------|----------|-------------------------------|
| F1 | `agents/orchestrator.md` | INSERT секции `## PIPELINE GUIDE` | после строки 61 (`**Auto-DOCS hook (BUGFIX/DEV rows only):** …`), перед `## SUPERCOMPLEX PIPELINE` (:63) |
| F2 | `agents/orchestrator.md` | INSERT секций `## TYPE SELECTION — DECISION TREE`, `## EDGE CASES`, `## CROSS-ROUTING BOUNDARY`, `## CLASSIFICATION EXAMPLES` | после строки 181 (`**complexity — DOCS:** …`), перед `## PROHIBITIONS` (:183). Порядок сборки: TYPE SELECTION → EDGE CASES → CROSS-ROUTING → EXAMPLES → (существующие) PROHIBITIONS → PLUGIN ENFORCEMENT — запреты остаются ПОСЛЕДНИМИ (recency effect) |
| F3 | `agents/orchestrator.md` | EDIT строки :188 | тех-исправление (Phase 3, п. 3.4) |
| F4 | `agents/plankestrator.md` | INSERT секции `## PIPELINE GUIDE` | после строки 52 (`Reviewers are MANDATORY pipeline elements…`), перед `## TURN ALGORITHM` (:54) |
| F5 | `agents/plankestrator.md` | INSERT секций `## TYPE SELECTION — DECISION TREE`, `## EDGE CASES`, `## CROSS-ROUTING BOUNDARY` | после строки 108 (`- RESEARCH+PLAN: ALWAYS COMPLEX …`), перед `## EXAMPLES` (:110) |
| F6 | `agents/plankestrator.md` | RESTRUCTURE `## EXAMPLES — WHAT A CORRECT TURN LOOKS LIKE` (:110) | переименовать в `## CLASSIFICATION EXAMPLES`; добавить подраздел `### Per-pipeline quick examples` ПЕРЕД существующим примером; существующий пример (:112–149) сохранить дословно под подзаголовком `### Full turn format — WHAT A CORRECT TURN LOOKS LIKE` |
| F7 | `agents/plankestrator.md` | EDIT строки :156 | тех-исправление (Phase 6, п. 6.4) |
| F8 | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | 4 вставки в §2 | Phase 8 (якоря :393, :421→:423, :542→:544, :550→:552) |
| F9 | `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | **Часть II (Phase 9–17):** ~15 вставок/замен (state-блок после :135, гейт в tool.execute.before после :727, флаги в message.updated, whitelist в validatePipeline) | Точные якоря — «Карта верифицированных якорей» в Части II (снимок 2026-09-29); OLD-блоки процитированы дословно в каждой фазе |

**Бюджет строк:** orchestrator.md ≤ 380 строк после вставок (~+170); plankestrator.md ≤ 300 (~+110). Превышение → сокращать объяснения в примерах, НЕ правила.

## Dependencies

- Внешние библиотеки/API: не нужны. Часть I — markdown-only; Часть II — TypeScript-правки существующего плагина (без новых зависимостей).
- **Часть I (Phase 1–8):** плагин `workflow-enforcement.ts` НЕ изменяется; вставки должны проходить его валидацию (примеры обязаны точно соответствовать PIPELINE TABLE и ROUTING_TABLES :56–57). Коммит №1: orchestrator.md + plankestrator.md + ARCHITECTURE.md (mirror-правило ARCHITECTURE.md:403).
- **Часть II (Phase 9–17):** изменяется `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (единственный файл). Зависимости между фазами: Phase 9.0 (единый механизм флагов) — предусловие для 9.1–9.5, 10.3, 14.3, 15.1, 17.2; Phase 10.1–10.2 (pipelineState) — предусловие для 10.3 и 17.2. Выполнять ПОСЛЕ коммита №1 (промпты уже заявляют hard-enforcement — Часть II делает заявление правдой; порядок обратный создаст окно, где промпт обещает блокировку, которой нет). Коммит №2: плагин + точечная правка ARCHITECTURE.md (формулировка слоя 2 в A4: identity-токены → HARD; описание новых гейтов) в том же коммите (mirror-правило :403 распространяется на семантические изменения enforcement).
- Коммиты: только через агента `git-commit` (глобальное правило).

---

## Phase 1: Orchestrator — описания пайплайнов

**Операция F1.** Вставить после строки 61, перед `## SUPERCOMPLEX PIPELINE`:

```markdown
## PIPELINE GUIDE — WHAT EACH ROW DOES (reference only; CLASSIFICATION RULES win on conflict)

### Row 1 — BUGFIX: `["bugfix-triage"]` → one-time continuation
- **Description:** two-stage bug pipeline. bugfix-triage investigates (reads code, reproduces, finds root cause) and returns `TRIAGE_RESULT: SIMPLE|DEEP`. SIMPLE → worker fixes, utility syntax-checks. DEEP → plan-bug writes a SELF-CONTAINED bug_plan.md → execute-bug implements it mechanically (escape hatch: `plan_gap: true`) → advisor → dev-reviewer → rework → consistency-checker (loop max 3) → utility.
- **When to use:** error message / stack trace / failing test / crash / "not working" / "broken" / regression ("worked before, stopped now") / "why is X broken?". Any question about broken behavior is BUGFIX — triage investigates, not you.
- **JSON:** `complexity: null`, `plan_exists: null` — you NEVER guess SIMPLE vs DEEP yourself.
- **Agents & roles:** bugfix-triage (verdict) · worker (simple fix) · plan-bug (bug_plan.md) · execute-bug (mechanical executor) · advisor (severity notes at step boundaries) · dev-reviewer (review + direct fixes) · rework (applies reviewer fixes) · consistency-checker (ARCHITECTURE.md checks, `escalate_to`) · utility (syntax check).
- **Expected outcome:** fixed bug + validated code; `requires_docs_update: true` → Auto-DOCS hook.

### Row 2 — DEVOPS: `["devops-agent", "devops-reviewer"]`
- **Description:** devops-agent executes external tools / CLI / builds / deployments / test runs / git operations; devops-reviewer validates exit codes, output logs, created files.
- **When to use:** build / deploy / CI-CD / run tests / lint / format / env setup / dependency install / git commit-push-PR / agent-model migration. The request EXECUTES an operation and writes no code.
- **Boundary:** "run the tests" = DEVOPS; "tests are failing, fix them" = BUGFIX (row 1).
- **Agents & roles:** devops-agent (execution) · devops-reviewer (validation).
- **Expected outcome:** executed operation + validation report. No utility step, no Auto-DOCS hook.

### Row 3 — DEV SIMPLE (no plan): `["worker", "utility"]`
- **Description:** worker implements one focused change; utility syntax-checks.
- **When to use:** single logical step, no architectural decisions (Q5). Multi-file ≠ multi-step: "rename a variable across 5 files" is SIMPLE.
- **Agents & roles:** worker (implementation) · utility (syntax).
- **Expected outcome:** implemented change + syntax-clean code; Auto-DOCS hook applies.

### Row 4 — DEV SIMPLE (with plan): `["worker", "consistency-checker", "utility"]`
- **Description:** worker implements per the EXISTING plan; consistency-checker validates against plan/ARCHITECTURE.md; rework loop with `escalate_to: worker` (max 3); utility.
- **When to use:** `plan_exists=true` AND not SUPERCOMPLEX (Q2a PLAN EXISTS OVERRIDE) — a plan with ≤3 steps. NEVER reclassify a planned ≤3-step task as COMPLEX.
- **Agents & roles:** worker (implementation) · consistency-checker (plan/architecture validation) · utility (syntax).
- **Expected outcome:** plan-conformant implementation + consistency verdict.

### Row 5 — DEV COMPLEX: `["dev-planner", "dev-professor", "advisor", "dev-reviewer", "rework", "consistency-checker", "utility"]`
- **Description:** dev-planner writes dev_plan.md IN-PIPELINE → dev-professor critically reviews the plan, then implements → advisor observes at the step boundary → dev-reviewer reviews + fixes → rework → consistency-checker (loop max 3) → utility. Prewalk pattern: expensive planner model → strong executor model.
- **When to use:** 2–3 logical steps OR architectural decisions OR multi-file changes with dependencies OR cross-cutting concerns (Q4); also the default for ambiguous DEV (Q5 NO branch). REQUIRES `plan_exists=false` — DEV COMPLEX always implies no pre-existing plan.
- **Agents & roles:** dev-planner (dev_plan.md) · dev-professor (implementation) · advisor (watchdog notes) · dev-reviewer (review) · rework (fixes) · consistency-checker (architecture) · utility (syntax).
- **Expected outcome:** dev_plan.md + reviewed implementation; Auto-DOCS hook applies.

### Row 6 — DEV SUPERCOMPLEX: full chain PER PLAN STEP
- **Description:** NOT one pass over the task. Determine the step list ONCE (priority: user steps > plan headings > dev-planner DECOMPOSITION), then run dev-planner → dev-professor → advisor → dev-reviewer → consistency-checker (rework loop max 3) → utility for EACH step. See SUPERCOMPLEX PIPELINE section for the three stages.
- **When to use:** explicit user request (Q1) / plan with >3 steps + huge volume (Q2) / DECOMPOSITION outcome (Q3). ALWAYS `plan_exists=true` (CRITICAL RULE: SUPERCOMPLEX + plan_exists=false is INVALID).
- **Agents & roles:** same as row 5, iterated per step; mcp-read may list plan headings (Stage 1, priority 2).
- **Expected outcome:** all N steps implemented; final JSON `next_agent: null` + `SUPERCOMPLEX complete: N/N steps implemented`; Auto-DOCS hook if ANY step flagged `requires_docs_update: true`.

### Row 7 — DOCS SIMPLE: `["docs-writer", "utility"]`
- **Description:** docs-writer produces the documentation directly; utility checks. No reviewer, no rework loop.
- **When to use:** 1–2 files, <50 lines total: README section, docstrings, changelog entry.
- **Agents & roles:** docs-writer (any doc type) · utility (check).
- **Expected outcome:** markdown/text-only change; never logic.

### Row 8 — DOCS DEEP: `["docs-planner", "docs-writer", "dev-reviewer", "rework", "consistency-checker", "utility"]`
- **Description:** docs-planner writes docs_plan.md (section structure, scope, code sources) → docs-writer reads docs_plan.md and writes the docs → dev-reviewer → rework → consistency-checker (loop max 3) → utility.
- **When to use:** >2 files OR >50 lines OR multi-document work: API reference, ARCHITECTURE, tutorial, migration guide.
- **Agents & roles:** docs-planner (docs_plan.md) · docs-writer (content) · dev-reviewer (quality) · rework · consistency-checker · utility.
- **Expected outcome:** docs_plan.md + complete reviewed documentation.

### type=null — OUT OF SCOPE (no row, no Task call)
- PLAN / RESEARCH / RESEARCH+PLAN requests → null JSON + the exact standard message: "⚠️ OUT OF SCOPE: This is a planning/research task. Please switch to plankestrator." Never name plankestrator's specialist agents in your message text (plugin forbidden-vocabulary check).
```

**Проверка фазы:** ни один массив `pipeline` в GUIDE не отличается от :43–52; row 6 описан БЕЗ `rework` в базовом массиве (rework — только в loop), как в таблице и ARCHITECTURE.md:454.

---

## Phase 2: Orchestrator — примеры

**Операция F2 (часть 4/4).** Вставить ПЕРЕД `## PROHIBITIONS` (после блоков Phase 3 — порядок сборки: TYPE SELECTION → EDGE CASES → CROSS-ROUTING → EXAMPLES):

```markdown
## CLASSIFICATION EXAMPLES (illustrate the rules; on conflict, CLASSIFICATION RULES + TYPE SELECTION win)

Format: request → JSON fields → why. All examples are Turn 1 unless stated otherwise.

### Example 1 — BUGFIX (row 1)
- **Request:** «При сохранении профиля падает NullReferenceException, вот стектрейс: …»
- **JSON:** `type: "BUGFIX"`, `complexity: null`, `plan_exists: null`, `next_agent: "bugfix-triage"`, `pipeline: ["bugfix-triage"]`
- **Why:** stack trace + crash (T3). You never guess SIMPLE vs DEEP. After `TRIAGE_RESULT: SIMPLE` the pipeline extends ONCE to `["bugfix-triage","worker","utility"]`; after `DEEP` → `["bugfix-triage","plan-bug","execute-bug","advisor","dev-reviewer","rework","consistency-checker","utility"]`.

### Example 2 — DEVOPS (row 2)
- **Request:** «Запусти сборку и прогони тесты»
- **JSON:** `type: "DEVOPS"`, `complexity: null`, `plan_exists: null`, `next_agent: "devops-agent"`, `pipeline: ["devops-agent","devops-reviewer"]`
- **Why:** running operations, no code writing (T4). Contrast: «тесты падают после мержа» → BUGFIX (row 1).

### Example 3 — DEV SIMPLE, no plan (row 3)
- **Request:** «Переименуй getUserData в fetchUserProfile во всех файлах»
- **JSON:** `type: "DEV"`, `complexity: "SIMPLE"`, `plan_exists: false`, `next_agent: "worker"`, `pipeline: ["worker","utility"]`
- **Why:** ONE logical step (Q5) despite touching many files — count steps, not files.

### Example 4 — DEV SIMPLE, with plan (row 4)
- **Request:** «Реализуй план из PLAN.md выше» (plankestrator finished with `state: "COMPLETE"`; the plan has 2 steps)
- **JSON:** `type: "DEV"`, `complexity: "SIMPLE"`, `plan_exists: true`, `plan_source: "PLAN.md (plankestrator COMPLETE)"`, `next_agent: "worker"`, `pipeline: ["worker","consistency-checker","utility"]`
- **Why:** PLAN EXISTS OVERRIDE (Q2a) — a planned ≤3-step task is ALWAYS row 4, never COMPLEX.

### Example 5 — DEV COMPLEX (row 5)
- **Request:** «Добавь JWT-аутентификацию: middleware, выдача токенов, refresh-логика»
- **JSON:** `type: "DEV"`, `complexity: "COMPLEX"`, `plan_exists: false`, `next_agent: "dev-planner"`, `pipeline: ["dev-planner","dev-professor","advisor","dev-reviewer","rework","consistency-checker","utility"]`
- **Why:** 3 logical steps + architectural decisions (Q4). dev-planner writes dev_plan.md in-pipeline.

### Example 6 — DEV SUPERCOMPLEX (row 6)
- **Request:** «Внедри шаги P0-1…P0-5 из RESEARCH.md» (the file has `## P0-1` … `## P0-5` headings)
- **JSON:** `type: "DEV"`, `complexity: "SUPERCOMPLEX"`, `plan_exists: true`, `plan_source: "RESEARCH.md headings"`, `next_agent: "dev-planner"`, `pipeline:` row-6 chain
- **Why:** plan with >3 steps (Q2). Step list = headings in file order (Stage 1, priority 2); the full chain runs for EACH step; per-step ack `→ STEP i/5 (<id>): DELEGATED to <agent>`.

### Example 7 — Q3 DECOMPOSITION (two turns; no plan, >3 steps)
- **Request:** «Проведи полный рефакторинг платёжного модуля»
- **Turn A:** `type: "DEV"`, `complexity: null`, `plan_exists: false`, `next_agent: "dev-planner"`, `pipeline: ["dev-planner"]`; Task prompt: "MODE: DECOMPOSITION. Analyze <task> and return a step list as JSON … Do NOT write dev_plan.md."
- **Turn B (verdict):** >3 steps + huge volume → SUPERCOMPLEX row 6 (`plan_exists: true`, `plan_source: "DECOMPOSITION"`); 2–3 steps → COMPLEX row 5; 1 step → row 3 (no arch decisions) or row 5 (arch decisions). From Turn B the pipeline is frozen.
- **Why:** Q3 forbids immediate classification and forbids SUPERCOMPLEX + plan_exists=false.

### Example 8 — DOCS SIMPLE (row 7)
- **Request:** «Добавь секцию "Установка" в README»
- **JSON:** `type: "DOCS"`, `complexity: "SIMPLE"`, `plan_exists: null`, `next_agent: "docs-writer"`, `pipeline: ["docs-writer","utility"]`
- **Why:** 1 file, <50 lines, markdown only (T5).

### Example 9 — DOCS DEEP (row 8)
- **Request:** «Напиши полный API reference для всех модулей проекта»
- **JSON:** `type: "DOCS"`, `complexity: "DEEP"`, `plan_exists: null`, `next_agent: "docs-planner"`, `pipeline: ["docs-planner","docs-writer","dev-reviewer","rework","consistency-checker","utility"]`
- **Why:** multi-document, >50 lines → docs-planner writes docs_plan.md first; its Task prompt includes "Write the plan to docs_plan.md".

### Example 10 — OUT OF SCOPE (type=null)
- **Request:** «Исследуй, какую библиотеку кэширования нам выбрать»
- **JSON:** all classification fields `null`, `next_agent: null`, `pipeline: []` + the exact message «⚠️ OUT OF SCOPE: This is a planning/research task. Please switch to plankestrator.»
- **Why:** the deliverable is a research document (T2). NO Task call; do not name plankestrator's agents (CROSS-ROUTING BOUNDARY #2).

### Example 11 — mixed intent (edge)
- **Request:** «Исправь баг с авторизацией и обнови README»
- **JSON:** `type: "BUGFIX"`, `complexity: null`, `plan_exists: null`, `next_agent: "bugfix-triage"`, `pipeline: ["bugfix-triage"]`; the goal mentions both parts
- **Why:** BUGFIX wins the mixed-intent priority (T3 before T5). The README update is NOT a second pipeline — it rides the Auto-DOCS hook if the implementation agent sets `requires_docs_update: true`.

### Example 12 — negative (cross-routing violation)
- **Request:** «Составь план миграции на новую ORM»
- ❌ WRONG: `pipeline: ["dev-planner"]` (DECOMPOSITION) — DECOMPOSITION serves complexity classification of DEV requests ONLY; here the deliverable is a PLAN DOCUMENT.
- ✅ CORRECT: `type: null` + OUT OF SCOPE message (T2, deliverable test).
```

**Проверка фазы:** 12 примеров покрывают все 8 строк + continuation (Ex1) + DECOMPOSITION (Ex7) + null (Ex10, 12) + mixed (Ex11); каждый `pipeline` сверен с :43–52.

---

## Phase 3: Orchestrator — усиленные правила

**Операция F2 (части 1–3).** Вставить после строки 181 (`**complexity — DOCS:** …`), перед `## PROHIBITIONS`:

### 3.1. Секция `## TYPE SELECTION — DECISION TREE`

```markdown
## TYPE SELECTION — DECISION TREE (apply IN ORDER, BEFORE complexity rules; keyword sources: CLASSIFICATION RULES above)

| # | Question | YES → | NO → |
|---|----------|-------|------|
| T1 | Identity test / small talk / meta question ("what did we do", "status")? | `type: null` — brief answer after the JSON, no Task call | T2 |
| T2 | Deliverable IS a plan/research document, no implementation requested ("plan", "research", "investigate options", "design the architecture", "create a plan")? | `type: null` + OUT OF SCOPE message (switch to plankestrator), no Task call | T3 |
| T3 | Broken behavior described: error / stack trace / crash / failing test / "not working" / "broken" / regression? | BUGFIX (row 1), `complexity: null`, `plan_exists: null` | T4 |
| T4 | Main action = RUNNING operations (build / deploy / test-run / lint / git / env / deps / model migration), no code writing? | DEVOPS (row 2) | T5 |
| T5 | Deliverable = markdown/docs only, zero logic change? | DOCS (row 7 or 8 by size) | T6 |
| T6 | Deliverable = new or modified code? | DEV → complexity Q1–Q5 | Re-check T2 |

**Mixed-intent priority (request spans several types):** BUGFIX > DEV > DOCS > DEVOPS. Pick exactly ONE row — the primary deliverable. Secondary intents are NOT separate pipelines: docs about the code change ride the Auto-DOCS hook (`requires_docs_update`); a deploy after a fix is mentioned in the final completion summary as a follow-up request. NEVER split one request into two pipelines.

**Deliverable test (T2 vs T6 — golden boundary):** «составь план рефакторинга» → the PLAN is the deliverable → `type: null` (plankestrator). «сделай рефакторинг» → the CODE is the deliverable → DEV (unplanned multi-step DEV stays with you — Q3 DECOMPOSITION; superseded rule 2026-09-22). The topic (refactoring / bugs / docs) never decides — the requested deliverable does.
```

### 3.2. Секция `## EDGE CASES`

```markdown
## EDGE CASES (deterministic resolutions)

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
```

### 3.3. Секция `## CROSS-ROUTING BOUNDARY`

```markdown
## CROSS-ROUTING BOUNDARY (hard rules)

1. **Never call plankestrator's agents:** plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly. They are NOT in your OPENCODE_ROUTING_TABLE; the plugin throws `ROUTING TABLE ENFORCEMENT` on any such Task call.
2. **OUT OF SCOPE message = the exact standard phrase** (type=null rule). Never name plankestrator, its agents, or its pipelines beyond that phrase — the plugin's forbidden-vocabulary check logs violations on foreign terminology in your messages.
3. **No mid-pipeline re-routing:** nothing a subagent returns can move a task into the other primary's scope. Planning/research recommendations go into the final summary text, not into a Task call.
4. **Planning-flavored DEV stays with you:** «сделай / внедри / отрефактори» = DEV even when it needs planning (Q3 DECOMPOSITION / dev-planner in-pipeline). Only requests whose DELIVERABLE is a plan/research document go out of scope (T2).
```

### 3.4. Тех-исправление `orchestrator.md:188`

- **OLD (точное совпадение):**
  `- 🚫 No using read/grep/glob for anything other than counting steps in plan files (SUPERCOMPLEX classification).`
- **NEW:**
  `- 🚫 No using read/grep/glob for anything other than Turn 1 classification inspection: counting steps in plan files (SUPERCOMPLEX classification) and glob/grep to confirm scope (TURN ALGORITHM item 2). Nothing else, never in Turns 2..N.`

**Обоснование:** устраняет противоречие с :102, где glob/grep «to confirm scope» разрешены. Семантика не меняется — только гармонизация; зеркалирования в ARCHITECTURE.md не требует (это не правило классификации, а формулировка запрета), но включить в тот же коммит.

---

## Phase 4: Plankestrator — описания пайплайнов

**Операция F4.** Вставить после строки 52, перед `## TURN ALGORITHM`:

```markdown
## PIPELINE GUIDE — WHAT EACH ROW DOES (reference only; CLASSIFICATION RULES win on conflict)

### Row 1 — PLAN SIMPLE: `["plan-writer-simple", "plan-reviewer-simple"]`
- **Description:** plan-writer-simple creates an implementation plan for a straightforward task and writes it to PLAN.md (reports `plan_file` / `plan_written` JSON fields — ARCHITECTURE.md §3 "File-Pointer Fields"); plan-reviewer-simple reads the plan file and reviews completeness and correctness.
- **When to use:** ONE topic / object, no comparative analysis, no architectural decisions, a straightforward answer is expected.
- **Agents & roles:** plan-writer-simple (writes PLAN.md) · plan-reviewer-simple (review verdict; mandatory, never skipped).
- **Expected outcome:** reviewed PLAN.md + reviewer JSON with the `plan_file` pointer.

### Row 2 — PLAN COMPLEX: `["plan-writer-complex", "plan-reviewer-complex"]`
- **Description:** plan-writer-complex creates a detailed plan with architecture decisions; plan-reviewer-complex reviews architecture, security, completeness.
- **When to use:** 2+ topics/objects, architectural decisions, external integrations, non-obvious approach, request spans multiple subsystems or a whole codebase.
- **Agents & roles:** plan-writer-complex (detailed PLAN.md) · plan-reviewer-complex (deep review; mandatory).
- **Expected outcome:** reviewed detailed PLAN.md.

### Row 3 — RESEARCH SIMPLE: `["research-writer-simple", "research-reviewer"]`
- **Description:** research-writer-simple gathers information from single sources via MCP tools and writes RESEARCH.md; research-reviewer validates accuracy, completeness, source quality.
- **When to use:** ONE question, no comparative analysis.
- **Agents & roles:** research-writer-simple (RESEARCH.md) · research-reviewer (validation; mandatory).
- **Expected outcome:** reviewed RESEARCH.md.

### Row 4 — RESEARCH COMPLEX: `["research-writer-complex", "research-reviewer"]`
- **Description:** research-writer-complex conducts multi-source research: decomposes internally, dispatches ONE parallel scout wave (mcp-search ∥ mcp-read ∥ mcp-github ∥ devops-readonly ∥ scout), barrier, then synthesizes on a strong model → RESEARCH.md. The fan-out happens INSIDE the writer — your top-level pipeline stays LINEAR.
- **When to use:** 2+ questions/topics, 2+ objects to compare, comparative analysis requested, cross-subsystem or whole-codebase span.
- **Agents & roles:** research-writer-complex (wave → barrier → synthesis) · research-reviewer (validation; mandatory).
- **Expected outcome:** synthesized reviewed RESEARCH.md with source references ("pointer, not transcript").

### Row 5 — RESEARCH+PLAN SIMPLE (defensive fallback — NEVER choose deliberately)
- RESEARCH+PLAN is ALWAYS COMPLEX (row 6): two work products, 4-stage pipeline. Row 5 exists for validation completeness only.

### Row 6 — RESEARCH+PLAN COMPLEX: `["research-writer-complex", "research-reviewer", "plan-writer-complex", "plan-reviewer-complex"]`
- **Description:** full 4-stage chain: research → research review → plan built on the research (PLAN.md) → plan review. Each stage is a separate turn; reviewers are never skipped.
- **When to use:** BOTH research and plan requested, in either order («исследуй X и спланируй внедрение», "research X and plan how to use it").
- **Agents & roles:** research-writer-complex (RESEARCH.md) · research-reviewer (validation) · plan-writer-complex (PLAN.md based on RESEARCH.md) · plan-reviewer-complex (review).
- **Expected outcome:** reviewed RESEARCH.md + reviewed PLAN.md.
```

**Проверка фазы:** массивы пайплайнов идентичны :43–50; internal fan-out row 4 согласован с ARCHITECTURE.md:535–542.

---

## Phase 5: Plankestrator — примеры

**Операция F6.** Заголовок :110 `## EXAMPLES — WHAT A CORRECT TURN LOOKS LIKE` → `## CLASSIFICATION EXAMPLES`; сразу под ним вставить подраздел quick-примеров; существующий пример (:112–149, «Исследуй, почему сборка медленная…») сохранить ДОСЛОВНО под подзаголовком `### Full turn format — WHAT A CORRECT TURN LOOKS LIKE`.

Вставляемый подраздел:

```markdown
### Per-pipeline quick examples (request → JSON fields → why)

#### Example 1 — PLAN SIMPLE (row 1)
- **Request:** «Составь план обновления проекта с .NET 8 до .NET 9»
- **JSON:** `type: "PLAN"`, `complexity: "SIMPLE"`, `state: "CLASSIFY"`, `next_agent: "plan-writer-simple"`, `pipeline: ["plan-writer-simple","plan-reviewer-simple"]`
- **Why:** one object, no architectural decisions. Task prompt = request verbatim + "Write the plan to PLAN.md".

#### Example 2 — PLAN COMPLEX (row 2)
- **Request:** «Разработай план перехода с REST на GraphQL для пяти сервисов»
- **JSON:** `type: "PLAN"`, `complexity: "COMPLEX"`, `next_agent: "plan-writer-complex"`, `pipeline: ["plan-writer-complex","plan-reviewer-complex"]`
- **Why:** 5 objects + architectural decisions → COMPLEX.

#### Example 3 — RESEARCH SIMPLE (row 3)
- **Request:** «Узнай, поддерживает ли библиотека X streaming-ответы»
- **JSON:** `type: "RESEARCH"`, `complexity: "SIMPLE"`, `next_agent: "research-writer-simple"`, `pipeline: ["research-writer-simple","research-reviewer"]`
- **Why:** one question, single source. Task prompt + "Write the research to RESEARCH.md".

#### Example 4 — RESEARCH COMPLEX (row 4)
- **Request:** «Исследуй, почему сборка медленная, и сравни трёх CI-провайдеров»
- **JSON:** `type: "RESEARCH"`, `complexity: "COMPLEX"`, `next_agent: "research-writer-complex"`, `pipeline: ["research-writer-complex","research-reviewer"]`
- **Why:** 2 topics + comparison of 3 objects. Full turn format: see the worked example below.

#### Example 5 — RESEARCH+PLAN (row 6 — ALWAYS COMPLEX)
- **Request:** «Исследуй три очереди сообщений и спланируй внедрение лучшей»
- **JSON:** `type: "RESEARCH+PLAN"`, `complexity: "COMPLEX"`, `next_agent: "research-writer-complex"`, `pipeline: ["research-writer-complex","research-reviewer","plan-writer-complex","plan-reviewer-complex"]`
- **Why:** both deliverables requested → row 6; row 5 must never be chosen deliberately.

#### Example 6 — OUT OF SCOPE (type=null)
- **Request:** «Исправь ошибку авторизации в auth.ts»
- **JSON:** classification fields `null`, `next_agent: null`, `pipeline: []` + the exact message «⚠️ OUT OF SCOPE: This is an implementation task. Please switch to orchestrator for: BUGFIX, DEVOPS, DEV, DOCS tasks.»
- **Why:** the deliverable is fixed code (P2). No Task call; never name orchestrator's agents (CROSS-ROUTING BOUNDARY #2).

#### Example 7 — edge: «спроектируй» = PLAN
- **Request:** «Спроектируй архитектуру модуля уведомлений»
- **JSON:** `type: "PLAN"`, `complexity: "COMPLEX"`, row 2
- **Why:** «спроектируй / архитектура» = PLAN keywords; the deliverable is design decisions, not gathered knowledge — so NOT RESEARCH.

#### Example 8 — edge: RESEARCH vs RESEARCH+PLAN
- «Сравни PostgreSQL и MySQL для нашего проекта» → RESEARCH COMPLEX (row 4): comparison only; the verdict IS knowledge.
- «Сравни PostgreSQL и MySQL и спланируй миграцию» → RESEARCH+PLAN (row 6): a plan deliverable was added.

#### Example 9 — negative (cross-routing violation)
- **Request:** «Почему тесты падают?»
- ❌ WRONG: `pipeline: ["research-writer-simple"]` — failing tests with fix intent = orchestrator's BUGFIX; research-writer is NOT a bugfix-triage substitute.
- ✅ CORRECT: `type: null` + OUT OF SCOPE message (switch to orchestrator). Only an explicit knowledge request («исследуй причины падений») classifies as RESEARCH.
```

**Проверка фазы:** quick-пример 4 и существующий full-turn пример (:112–149) используют ОДИН запрос — это намеренно (quick-форма + полная форма одного кейса); противоречий нет.

---

## Phase 6: Plankestrator — усиленные правила

**Операция F5.** Вставить после строки 108, перед `## EXAMPLES` (переименованным в Phase 5):

### 6.1. Секция `## TYPE SELECTION — DECISION TREE`

```markdown
## TYPE SELECTION — DECISION TREE (apply IN ORDER, from the REQUEST TEXT ONLY)

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
```

### 6.2. Секция `## EDGE CASES`

```markdown
## EDGE CASES (deterministic resolutions)

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
```

### 6.3. Секция `## CROSS-ROUTING BOUNDARY`

```markdown
## CROSS-ROUTING BOUNDARY (hard rules)

1. **Never call orchestrator's agents:** worker, utility, dev-planner, dev-professor, advisor, dev-reviewer, rework, consistency-checker, bugfix-triage, plan-bug, execute-bug, bugfix, devops-agent, devops-reviewer, docs-writer, docs-planner, codebase-analyzer, summarizer, git-commit, image-creator, video-generator, voice-*, mcp-*. They are NOT in your OPENCODE_ROUTING_TABLE; the plugin throws `ROUTING TABLE ENFORCEMENT`. Your callable set is EXACTLY: plan-writer-*, plan-reviewer-*, research-writer-*, research-reviewer, devops-readonly, view-image, plankestrator-identity-probe.
2. **OUT OF SCOPE message = the exact standard phrase** (type=null rule). Never name orchestrator or its agents beyond that phrase — the plugin's forbidden-vocabulary check logs violations on foreign terminology in your messages.
3. **No mid-pipeline re-routing:** implementation hints in writer/reviewer results never spawn Task calls to orchestrator's agents — the recommendation goes into the COMPLETE summary text.
4. **Scout fan-out is NOT yours:** mcp-search / mcp-read / mcp-github waves belong to research-writer-complex's INTERNAL DAG (ARCHITECTURE.md §2). You never call them directly.
```

### 6.4. Тех-исправление `plankestrator.md:156`

- **OLD (точное совпадение):**
  `- 🚫 No using read/grep/glob for anything other than counting steps in plan files (SUPERCOMPLEX classification).`
- **NEW:**
  `- 🚫 No using read/grep/glob for anything other than Turn 1 classification inspection within the 2-call budget (TURN ALGORITHM item 2).`

**Обоснование:** SUPERCOMPLEX отсутствует в scope plankestrator (copy-paste из orchestrator); корректное правило — бюджет 2 инспекций из :58/:161.

---

## Phase 7: Cross-routing prevention (сводно)

Содержательные блоки уже определены в Phase 3.3 (orchestrator) и Phase 6.3 (plankestrator) + негативные примеры (orchestrator Ex12, plankestrator Ex9). Сводка механизма — три слоя защиты:

| Слой | Где | Поведение | Изменяется? |
|------|-----|-----------|-------------|
| 1. Промпт-превенция | Новые секции `CROSS-ROUTING BOUNDARY` в обоих файлах | Явные списки запрещённых агентов + правило «стандартная фраза OUT OF SCOPE без имён чужих агентов» + «pipeline frozen» | **ДА (этот план)** |
| 2. Плагин: forbidden vocabulary | `workflow-enforcement.ts:617–646` | Обнаружение чужой терминологии в сообщении → **log-only, не бросает** (:641–644: «let downstream checks catch the actual violation») | Часть I: нет. **Часть II Phase 9.5: ДА** — identity-токены («I am plankestrator» и т.п.) эскалируются в THROW (отложенный флаг); имена агентов остаются log-only |
| 3. Плагин: routing table | `workflow-enforcement.ts:1042–1053` | Task-вызов агента вне `ROUTING_TABLES[currentAgent]` → **throw** `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT` | Нет |

**Правила, которые добавляют слой 1:**
1. Закрытые списки чужих агентов (перечислены явно — модель не должна выводить их из routing table).
2. OUT OF SCOPE сообщение — ТОЛЬКО стандартная фраза (orchestrator.md:160 / plankestrator.md:103), без имён чужих специалистов: это уменьшает шум forbidden-vocab логов (слой 2) и исключает соблазн «частичного» cross-routing.
3. Результаты субагентов, предлагающие работу чужого scope, НЕ меняют пайплайн — пайплайн заморожен; рекомендация попадает только в финальное summary.
4. «Planning-flavored DEV» остаётся у orchestrator (Q3 DECOMPOSITION; superseded-правило 2026-09-22, ARCHITECTURE.md:421) — главнейший источник ложного cross-routing устраняется deliverable-тестом (T2 vs T6 / P2).

**Изменений плагина в Части I НЕ требуется:** слои 2–3 уже работают; новые промпт-секции — превентивный слой до plugin-бэкстопа. (Часть II Phase 9–17 усиливает plugin-бэкстоп отдельно — см. ниже.)

---

## Phase 8: Синхронизация ARCHITECTURE.md (обязательна, тот же коммит)

Основание: ARCHITECTURE.md:393 («Each table must stay identical to the corresponding section in this file») и :403 («any change here must land there in the same commit»). PIPELINE TABLE не меняются → идентичность таблиц сохраняется автоматически. НО новые семантические правила обязаны появиться в §2:

| # | Якорь в ARCHITECTURE.md | Вставка |
|---|------------------------|---------|
| A1 | После :393 (single-source абзац) | Одно предложение: «Prompt-local reference sections (`PIPELINE GUIDE`, `CLASSIFICATION EXAMPLES`) in agents/*.md are illustrative and are NOT mirrored here; on conflict, the PIPELINE TABLE + CLASSIFICATION RULES + this file win.» |
| A2 | После :421 (Superseded note), перед `### DEV SIMPLE` (:423) | Новый подраздел `### Type Selection Decision Tree (orchestrator)` — таблица T1–T6 + Mixed-intent priority + Deliverable test + таблица EDGE CASES (только rule-bearing строки) из Phase 3.1–3.2, с mirror-примечанием: «agents/orchestrator.md mirrors this section — any change must land in both files in the same commit.» |
| A3 | После :542 (конец Internal fan-out), перед `### Wave → Barrier → Synthesis Pattern` (:544) | Новый подраздел `### PLAN vs RESEARCH Boundary (plankestrator)` — таблица P1–P5 + boundary/deliverable тесты + complexity default + EDGE CASES строки из Phase 6.1–6.2, с тем же mirror-примечанием для agents/plankestrator.md |
| A4 | После :550 (Decision record), перед `## 3. JSON Validation Fields` (:552) | Новый подраздел `### Cross-Routing Prevention` — сводная таблица трёх слоёв из Phase 7 (промпт-превенция / forbidden-vocab log :617–644 / routing-table throw :1042–1053) + 4 правила |

**Что НЕ зеркалируется (prompt-local):** PIPELINE GUIDE (описания дублируют флоу §2 — дубль запрещён во избежание дрейфа), примеры, тех-исправления :188/:156 (формулировки запретов, не правила классификации).

---

# ЧАСТЬ II — Plugin Enforcement (Phase 9–17)

**Основание:** `RESEARCH_PIPELINE_ENHANCEMENTS.md` (2026-09-29) — пункты P0-1…P0-3 (Phase 9–11) и P1-4…P1-9 (Phase 12–17).
**Файл:** `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1584 строки, снимок 2026-09-29).
**Язык кода/комментариев вставок:** английский (консистентно с файлом); комментарии допустимы русские там, где существующие v4/v5-комментарии русские (:122–128, :352–359).

**Правило дрейфа якорей:** все номера строк даны по снимку ДО правок. Phase 9–17 последовательно изменяют ОДИН файл — после каждой фазы перевычислять якоря grep'ом по процитированному OLD-тексту (текст OLD-блоков стабилен).

## Карта верифицированных якорей (снимок 2026-09-29, сверено с кодом)

| Якорь | Строки | Содержимое |
|-------|--------|------------|
| Блок state-переменных | :129–135 | `INSPECTION_BUDGET` (:129), `selfWorkDetected` (:131), `activeTaskDepth` (:133), `primaryAgentFirstTaskCall` (:135) — точка вставки нового state |
| `FORBIDDEN_VOCAB` | :142–153 | orchestrator: 3 identity-фразы + «## PLAN», «# Implementation Plan» + 4 имени агентов; plankestrator: 5 identity-фраз + 4 имени |
| `SELF_WORK_MARKERS` | :165–171 | только ключ `plankestrator` |
| `session.created` | :196 | старт хендлера; **parentID-guard :210–220** (дочерние сессии → early return); **безусловный reset-блок :234–241** (`currentAgent = null` … `primaryAgentFirstTaskCall.clear()`) — единственная корректная точка сброса нового state |
| `message.updated` | :351 | **сабагент-ветка (activeTaskDepth>0) :355–407** (severity-валидация SEVERITY_AGENTS :363–404, blocker-лог :375–379, `return` :406); `message` определён на :409–412; primary-ветка далее |
| Identity missing (log-only) | :438–449 | `PRIMARY AGENT MISSING IDENTITY` |
| Identity drift при `identityLocked` (log-only) | :509–525 | `IDENTITY DRIFT REJECTED`; комментарий :523–525 |
| Primary JSON-блок | :546–615 | guard `if (jsonContent && currentAgent)` :546; primary-guard :548; pipeline-валидация :556–568; next_agent-валидация :571–585 (**TODO `const currentStep = 0` :573**); INVALID JSON :590–602; **else-ветка (валидный JSON) :603–614** (`hasOutputtedJSON.set(currentAgent, true)` :604) |
| Forbidden-vocab check | :621–646 | log :628–640; комментарий «DO NOT throw» :641–644 |
| Self-work check | :661–682 | `selfWorkDetected = true` :667 |
| `tool.execute.before` | :689 | **depth-bypass :697–710** (warn «TASK CALL WHILE SUBAGENT ACTIVE» :700–707, `return` :709); plan-mode bypass :716–727; first-Task tracking :730–732; read-lock throw :735–750; action-tool gate :759–802; **INSPECTION GATE — plankestrator-only :812–907** (guard `lockedAgentName === "plankestrator"` :814); потребление `selfWorkDetected` :854–875 |
| Task-секция | :995–1053 | `targetAgent` определён к :1008; JSON-before-Task throw :1008–1023; builtin bypass (explore/general) :1028–1040; routing-table throw :1053 |
| `validatePipeline` | :1392–1441 | `PIPELINES` map :1393–1412 (orchestrator: 8 ключей, «BUGFIX-null-null» → только `["bugfix-triage"]`; DOCS через «any» :1419–1421); fail-open :1425 (unknown agent) и **:1429–1431 (unknown combination → `valid: true`)** |
| `validateNextAgent` | :1446–1464 | `expected = pipeline[currentStep]`; `nextAgent === null` → valid (:1447–1448) |
| Severity-таксономия | :86–87 | `SEVERITY_AGENTS`, `VALID_SEVERITIES = ["nit","concern","blocker"]` |
| `VALID_VALUES` | :60–72 | orchestrator/plankestrator — поля, проверяемые `validateJSONOutput` (:1470, :1483–1488) |

## Механизм throw — ЕДИНЫЙ паттерн (предусловие Phase 9, 10, 14, 15, 17)

Throw в event-хуке (`message.updated`) НЕ отменяет уже сгенерированное сообщение (плагин сам отмечает :357–359; RESEARCH_PIPELINE_ENHANCEMENTS.md :43). Рабочий паттерн — `selfWorkDetected`: флаг ставится в message.updated (:667), THROW потребляется в `tool.execute.before` (:854). **НО** потребление :854 находится внутри plankestrator-only INSPECTION GATE (:812–816) и блокирует только read/grep/glob — напрямую переиспользовать нельзя. Вводится единый отложенный гейт:

**9.0(а) — State.** Вставить после :135 (`const primaryAgentFirstTaskCall = new Map<string, boolean>()`):

```typescript
// ============================================================
// v6 (Part II) — deferred violation flags (паттерн selfWorkDetected :667→:854).
// Флаг ставится в message.updated (throw там инертен — сообщение уже отправлено),
// THROW потребляется в tool.execute.before (гейт 9.0в).
// Consume-once: флаги сбрасываются после throw ИЛИ когда новое сообщение
// primary проходит все проверки чисто (latest-message-wins — защита от
// streaming-артефактов: message.updated fires на каждый chunk, ранние chunk'и
// могут не содержать identity/JSON целиком).
// ============================================================
let identityMissing = false      // Phase 9.1
let pipelineMismatch = false     // Phase 9.2
let nextAgentMismatch = false    // Phase 9.3
let invalidJSON = false          // Phase 9.4
let forbiddenIdentity = false    // Phase 9.5
let pipelineImmutable = false    // Phase 17.2
let blockerStop = false          // Phase 14.3 (НЕ сбрасывается recovery — кумулятивный)
let violationDetail = ""         // текст для THROW-сообщения
```

**9.0(б) — MessageID-дедупликация** (критично: `message.updated` срабатывает на КАЖДЫЙ streaming-chunk одного сообщения; НЕидемпотентные операции — `currentStep++`, счётчики, ack-warn — выполнять РАЗ на сообщение). Там же, после :135:

```typescript
// v6: dedup не-идемпотентных операций по messageID (streaming re-fires)
const processedMessageIDs = new Set<string>()
```

**9.0(в) — Потребление (единый violation gate).** Новый блок в `tool.execute.before` ПОСЛЕ plan-mode bypass (:727, конец блока `return`) и ПЕРЕД first-Task tracking (:730). Depth-bypass (:697–710) выше гарантирует: сюда доходят только вызовы при `activeTaskDepth === 0` → атрибуция primary корректна (tool-вызовы сабагентов не блокируются за нарушения primary).

```typescript
// v6 (Phase 9.0в): unified deferred-violation gate — consume flags set in message.updated
if (currentAgent && (identityMissing || pipelineMismatch || nextAgentMismatch ||
    invalidJSON || forbiddenIdentity || pipelineImmutable || blockerStop)) {
  const code = identityMissing ? "IDENTITY MISSING"
    : pipelineMismatch ? "PIPELINE VALIDATION FAILED"
    : nextAgentMismatch ? "NEXT_AGENT MISMATCH"
    : invalidJSON ? "INVALID JSON OUTPUT"
    : forbiddenIdentity ? "FORBIDDEN IDENTITY CLAIM"
    : pipelineImmutable ? "PIPELINE IMMUTABLE"
    : "BLOCKER STOP AFTER 3"
  await client.app.log({ body: { service: "workflow-enforcement", level: "error",
    message: `DEFERRED VIOLATION ENFORCED — ${code}`,
    extra: { agent: currentAgent, detail: violationDetail, attemptedTool: input.tool } } })
  const detail = violationDetail
  identityMissing = pipelineMismatch = nextAgentMismatch = invalidJSON =
    forbiddenIdentity = pipelineImmutable = blockerStop = false
  violationDetail = ""
  throw new Error(`
⛔ WORKFLOW VIOLATION — ${code}

${detail}

Your previous message violated plugin validation and was REJECTED before any tool
could run. Fix: re-issue a corrected message in the required order:
1. "IDENTITY VERIFIED: I am ${currentAgent}..."
2. Valid JSON block (all required fields, pipeline per PIPELINE TABLE)
3. THEN the Task call.
  `)
}
```

**9.0(г) — Recovery (latest-message-wins).** В message.updated: (1) при обнаружении `identityText` (ветка :452 и далее — любое место, где identity подтверждён) → `identityMissing = false`; (2) в else-ветке валидного JSON (:603, после `hasOutputtedJSON.set(currentAgent, true)` :604), ЕСЛИ в данном прогоне не установлено новых флагов → `pipelineMismatch = nextAgentMismatch = invalidJSON = forbiddenIdentity = pipelineImmutable = false; violationDetail = ""`. `blockerStop` recovery НЕ сбрасывается (кумулятивное состояние сессии).

**9.0(д) — Сброс на session.created.** В БЕЗУСЛОВНЫЙ reset-блок :234–241 (после `primaryAgentFirstTaskCall.clear()` :241). ⚠️ **НЕ на :196** (старт хендлера): сброс ОБЯЗАН быть после parentID-guard (:210–220) — иначе дочерняя сессия (Task-субагент) сотрёт состояние родителя, ровно тот баг, который guard описывает (:197–203).

```typescript
// v6 (Part II): reset deferred-violation state + pipeline tracking
identityMissing = pipelineMismatch = nextAgentMismatch = invalidJSON =
  forbiddenIdentity = pipelineImmutable = blockerStop = false
violationDetail = ""
pipelineState.clear()          // Phase 10.4
taskCallsPerTurn.clear()       // Phase 13
lastTurnMessageID.clear()      // Phase 13.3
reworkCount.clear()            // Phase 14.4
blockerEscalations.clear()     // Phase 14.4
processedMessageIDs.clear()    // 9.0(б)
```

---

## Phase 9: Plugin P0 — Эскалация log-only в THROW

Все подпункты (кроме 9.6) реализуются через механизм 9.0: флаг в message.updated → THROW в tool.execute.before. Существующие логи СОХРАНИТЬ (аудит), флаг добавляется рядом.

### 9.1. Identity validation → throw (:438–449)

- **OLD:** `await client.app.log({ ... level: "error", message: \`PRIMARY AGENT MISSING IDENTITY — ...\` })` — log-only.
- **NEW:** внутри `if` (:438–440), после лога (:448):

```typescript
identityMissing = true
violationDetail = `PRIMARY AGENT MISSING IDENTITY — ${currentAgent} did not start with "IDENTITY VERIFIED: I am ${currentAgent}"`
```

- **Эффект:** следующий tool-вызов primary (включая Task) блокируется гейтом 9.0(в). Recovery 9.0(г): сообщение с identity-строкой снимает флаг.

### 9.2. Pipeline validation → throw (:556–568)

- **OLD:** `if (!pipelineValidation.valid)` → log `PIPELINE VALIDATION FAILED` (:559–566).
- **NEW:** после лога, внутри того же `if`:

```typescript
pipelineMismatch = true
violationDetail = `PIPELINE VALIDATION FAILED — ${pipelineValidation.error}`
```

- **Синергия с Phase 11:** fail-closed `validatePipeline` расширяет множество детектируемых нарушений; эскалация делает их блокирующими (обещание промпта «You cannot override plugin validation», orchestrator.md:205, становится правдой).

### 9.3. next_agent validation → throw (:571–585)

- **OLD:** `if (!nextAgentValidation.valid)` → log `NEXT_AGENT VALIDATION FAILED` (:576–583).
- **NEW:** после лога, внутри того же `if` (с учётом исключений Phase 10.3 — флаг ставится ТОЛЬКО если нарушение не whitelisted):

```typescript
nextAgentMismatch = true
violationDetail = `NEXT_AGENT VALIDATION FAILED — ${nextAgentValidation.error}`
```

- **Взаимосвязь:** до Phase 10.3 проверка работает с `currentStep = 0` (TODO :573) — эскалировать ОБЯЗАТЕЛЬНО вместе с Phase 10.3 (иначе флаг ставится на легальных ходах Turn 2+: expected всегда pipeline[0]). **Порядок реализации: 10.3 и 9.3 — один коммит-атом.**

### 9.4. Invalid JSON → throw (:590–602)

- **OLD:** `if (!validation.valid)` → log `INVALID JSON OUTPUT` (:591–601).
- **NEW:** после лога, внутри того же `if`:

```typescript
invalidJSON = true
violationDetail = `INVALID JSON OUTPUT — errors: ${validation.errors.join("; ")}, missing: ${validation.missingFields.join(", ")}`
```

- **Примечание:** сейчас нарушение блокирует Task лишь КОСВЕННО (`hasOutputtedJSON` не выставляется :604 → гейт :1008). Флаг делает блок прямым и распространяет его на read/grep/glob тоже.

### 9.5. FORBIDDEN_VOCAB → throw ВЫБОРОЧНО (:621–646)

Эскалируются ТОЛЬКО identity-токены («I am plankestrator» и т.п.), НЕ имена агентов и не заголовки: комментарий :641–644 остаётся в силе для имён (легальные перекрёстные упоминания, напр. «plan-writer-» в пояснениях).

- **NEW-1:** константа после `FORBIDDEN_VOCAB` (:153):

```typescript
// v6 (Phase 9.5): identity-subset of FORBIDDEN_VOCAB — these ESCALATE to deferred
// THROW (gate 9.0в). Agent-name tokens stay log-only (:641–644 rationale holds:
// legitimate cross-references, e.g. orchestrator quoting "plan-writer-" in prose).
const FORBIDDEN_IDENTITY_TOKENS: Record<string, string[]> = {
  orchestrator: ["I am plankestrator", "I'm plankestrator", "I am the Plankestrator"],
  plankestrator: ["I am orchestrator", "I'm orchestrator", "I am the Conductor",
                   "I am the Task classifier", "Task classifier and router"]
}
```

- **NEW-2:** в блоке `if (violations.length > 0)` (:627), после лога (:640), ПЕРЕД комментарием :641:

```typescript
const identityViolations = violations.filter(t =>
  (FORBIDDEN_IDENTITY_TOKENS[lockedAgentName] || []).includes(t))
if (identityViolations.length > 0) {
  forbiddenIdentity = true
  violationDetail = `FORBIDDEN IDENTITY CLAIM — ${lockedAgentName} message claims foreign identity: ${identityViolations.join(", ")}`
}
```

- **NEW-3:** комментарий :641–644 уточнить: «we DO NOT throw here» → «we do not throw for AGENT-NAME tokens; identity tokens escalate via forbiddenIdentity flag (Phase 9.5)».
- **Проверка на false-positive:** собственные identity-строки («I am orchestrator» у orchestrator) НЕ входят в свой forbidden-список; фраза «I am NOT plankestrator» (промпт :36) не содержит токен «I am plankestrator» как подстроку — безопасно.

### 9.6. Identity drift при identityLocked → throw напрямую (:509–525)

По spec заказчика — ПРЯМОЙ throw в event-хуке (без флага):

- **OLD:** `if (identityLocked) { await client.app.log({... "IDENTITY DRIFT REJECTED" ...}) /* :511–522 */ // Hard-error: log and let the message through... :523–525 }`
- **NEW:** после лога (:522), вместо комментария :523–525:

```typescript
// v6 (Phase 9.6): escalate — drift under identity lock is a terminal violation.
// currentAgent is NOT updated (locked identity preserved); the throw aborts the
// remaining message.updated processing for this event.
throw new Error(`
⛔ IDENTITY DRIFT REJECTED — session is LOCKED to ${lockedAgentName}.
Claimed identity: ${String(jsonContent.agent)}. Identity cannot be changed mid-session.
`)
```

- ⚠️ **Caveat (задокументировать в коде):** throw в event-хуке не отзывает сообщение и может быть проглочен opencode-рантаймом (эффект = error-лог + прерывание остатка обработчика). Если smoke-тест (Verification 11) покажет, что поток продолжается без последствий — деградировать до флага `identityDrift` через гейт 9.0 (решение принимается по итогам теста, код флага уже готов в 9.0(а) — добавить при необходимости).

---

## Phase 10: Plugin P0 — Трекинг шага пайплайна

### 10.1. State-переменные (после :135, в блоке 9.0)

```typescript
// v6 (Phase 10): pipeline step tracking — заменяет TODO-заглушку :573.
// Ключ = имя primary-агента (паттерн hasOutputtedJSON / primaryAgentFirstTaskCall).
// Семантика currentStep: индекс ПОСЛЕДНЕГО ДИСПЕТЧЕННОГО агента;
// ожидаемый next_agent = pipeline[currentStep + 1].
// Специальные значения: 0 после Turn 1 (pipeline[0] диспетчнен);
// -1 после DECOMPOSITION Turn B (chain[0] диспетчится повторно).
const pipelineState = new Map<string, { pipeline: string[]; currentStep: number }>()
```

### 10.2. Извлечь pipeline из первого JSON + 17.2 иммутабельность — ЕДИНЫЙ state-блок

⚠️ **Верифицированные корректировки spec:** (1) вставка БЕЗ guard'а `!pipelineState.has(...)` перезатирает `currentStep` на каждом streaming-chunk (message.updated fires многократно на одно сообщение) — guard обязателен («first JSON wins» = Phase 17.1); (2) установка state, иммутабельность-проверка (17.2) и продвижение шага сводятся в ОДИН блок в else-ветке :603–614 (после `hasOutputtedJSON.set(currentAgent, true)` :604) с messageID-дедупом — порядок существен: state должен обновляться ПОСЛЕ валидаций (:556–585) и только для ВАЛИДНОГО JSON, иначе невалидный ход продвинет шаг.

Вставить в else-ветку (:603) после :604:

```typescript
// v6 (Phases 10.2 + 10.3-increment + 17.2): pipeline state — ONCE per message
const msgId = String((message as any).id || (message as any).info?.id || "")
if (msgId && !processedMessageIDs.has(msgId)) {
  processedMessageIDs.add(msgId)
  const prev = pipelineState.get(currentAgent)
  const newPipeline = Array.isArray(jsonContent.pipeline) ? jsonContent.pipeline as string[] : null
  if (newPipeline) {
    const nextIdx = jsonContent.next_agent ? newPipeline.indexOf(String(jsonContent.next_agent)) : -1
    if (!prev) {
      // Turn 1 — зафиксировать pipeline (Phase 17.1)
      pipelineState.set(currentAgent, {
        pipeline: newPipeline,
        currentStep: nextIdx >= 0 ? nextIdx : 0
      })
    } else if (JSON.stringify(newPipeline) !== JSON.stringify(prev.pipeline)) {
      // Phase 17.2 — pipeline изменён после Turn 1
      const isException =
        jsonContent.type === "BUGFIX" ||                 // BUGFIX continuation (orchestrator.md:54–57)
        jsonContent.plan_source === "DECOMPOSITION" ||   // DECOMPOSITION Turn B (Q3)
        jsonContent.severity === "nit"                   // nit-skip
      if (isException) {
        prev.pipeline = newPipeline
        // DECOMPOSITION: chain[0] диспетчится повторно → currentStep = -1;
        // BUGFIX continuation: bugfix-triage уже выполнен → indexOf(next_agent) - 1
        prev.currentStep = nextIdx >= 0 ? nextIdx - 1 : prev.currentStep
      } else {
        pipelineImmutable = true
        violationDetail = `PIPELINE IMMUTABLE: pipeline changed after Turn 1 — [${prev.pipeline.join(", ")}] → [${newPipeline.join(", ")}] (exceptions: BUGFIX continuation, DECOMPOSITION, nit-skip)`
      }
    } else if (nextIdx >= 0) {
      // pipeline неизменен — продвинуть шаг на фактический next_agent
      // (единое правило покрывает forward, rework-loopback и nit-skip)
      prev.currentStep = nextIdx
    }
  }
}
```

### 10.3. Валидировать next_agent — заменить TODO-заглушку (:571–585)

- **OLD (весь блок :571–585):** `const currentStep = 0 // TODO: track step counter properly` + `validateNextAgent(nextAgent, pipeline, currentStep)` + log-only.
- **NEW:**

```typescript
// Validate next_agent (v6 Phase 10.3 — real step tracking instead of TODO)
if (nextAgent !== undefined && pipeline && Array.isArray(pipeline)) {
  const state = pipelineState.get(currentAgent)
  // Turn 1: state ещё не установлен (10.2 выполняется ниже, в :603) → effectiveStep = 0
  const effectiveStep = state ? state.currentStep + 1 : 0
  const nextAgentValidation = validateNextAgent(nextAgent, pipeline, effectiveStep)
  if (!nextAgentValidation.valid) {
    const expected = pipeline[effectiveStep]
    // Whitelist-исключения (orchestrator.md:190; RESEARCH P0-2):
    const isLoopback = nextAgent !== null &&
      pipeline.slice(0, effectiveStep).includes(String(nextAgent)) // rework-loop / escalate_to / DECOMPOSITION re-dispatch
    const isReworkSkip = expected === "rework" &&
      nextAgent === pipeline[effectiveStep + 1]                    // severity-nit skip over rework
    if (!(isLoopback || isReworkSkip)) {
      nextAgentMismatch = true  // Phase 9.3 → THROW через гейт 9.0(в)
      violationDetail = `NEXT_AGENT MISMATCH: expected ${expected}, got ${String(nextAgent)} (step ${effectiveStep})`
    }
    await client.app.log({ body: { service: "workflow-enforcement", level: "error",
      message: `NEXT_AGENT VALIDATION FAILED — ${nextAgentValidation.error}`,
      extra: { agent: currentAgent, nextAgent, pipeline, effectiveStep, whitelisted: isLoopback || isReworkSkip } } })
  }
}
```

- ⚠️ **Корректировки spec:** (1) прямой `throw new Error(\`NEXT_AGENT MISMATCH...\`)` из spec заменён на флаг `nextAgentMismatch` — throw в message.updated инертен (механизм 9.0; текст сохранён в `violationDetail`); (2) `next_agent === null` НЕ требует отдельной проверки — `validateNextAgent` уже возвращает valid для null (:1447–1448, pipeline complete); (3) BUGFIX continuation и DECOMPOSITION Turn B покрыты `isLoopback` (валидация идёт по НОВОМУ массиву `pipeline` из текущего JSON: для continuation `effectiveStep=1` → `expanded[1]` = «worker» ✓; для DECOMPOSITION next_agent=«dev-planner» ∈ completed-prefix ✓) — отдельные ветки не нужны; (4) продвижение `currentStep` — НЕ здесь, а в едином state-блоке 10.2 (иначе двойной инкремент на streaming re-fires).
- **Результат для примеров Части I:** DEV COMPLEX — dev-planner(0)→dev-professor(1)→advisor(2)→dev-reviewer(3)→rework(4)→consistency-checker(5)→utility(6); nit у dev-reviewer → next=consistency-checker при expected=rework → `isReworkSkip` (pipeline[4]="rework", pipeline[5]="consistency-checker") ✓; concern → rework(4) → loopback к dev-reviewer/worker ∈ prefix ✓ (лимит — Phase 14.2).

### 10.4. Сброс на session.created

⚠️ **Корректировка якоря:** не :196 (старт хендлера — ДО parentID-guard), а безусловный reset-блок :234–241: `pipelineState.clear()` входит в сводный сброс 9.0(д) (уже включает `processedMessageIDs.clear()`). Обоснование: сброс до guard'а :210–220 стирал бы состояние родителя при создании каждой дочерней Task-сессии.

---

## Phase 11: Plugin P0 — Fail-closed validatePipeline

### 11.1. Неизвестные комбинации → невалидно (:1429–1431) + ОБЯЗАТЕЛЬНЫЙ whitelist

- **OLD:**
```typescript
const expected = PIPELINES[agent]?.[key]
if (!expected) {
  return { valid: true } // Unknown combination, allow
}
```
- **NEW:**
```typescript
const expected = PIPELINES[agent]?.[key]
if (!expected) {
  return {
    valid: false,
    error: `Unknown type/complexity/plan_exists combination for ${agent}: "${key}" (fail-closed — Phase 11)`
  }
}
```

⚠️ **КРИТИЧНО — до flip'а default'а добавить whitelist легальных комбинаций, отсутствующих в `PIPELINES` (:1393–1412), иначе fail-closed сломает верифицированные флоу Части I:**

**(a) OUT OF SCOPE (type=null, pipeline=[])** — Example 10/12 (orchestrator), Example 6 (plankestrator). Вставить ПЕРЕД построением key (после :1413, до `let key: string` :1415):

```typescript
// v6 (Phase 11.1a): OUT OF SCOPE — type=null legitimate ONLY with empty pipeline
if (type === null || type === undefined) {
  return pipeline.length === 0
    ? { valid: true }
    : { valid: false, error: "type=null (OUT OF SCOPE) requires empty pipeline and next_agent=null" }
}
```

**(б) DECOMPOSITION Turn A** (Example 7: `type: "DEV"`, `complexity: null`, `plan_exists: false`, `pipeline: ["dev-planner"]`) — добавить ключ в `PIPELINES.orchestrator` (:1394–1403):

```typescript
"DEV-null-false": ["dev-planner"],  // Q3 DECOMPOSITION Turn A — complexity ещё не определена
```

**(в) BUGFIX continuation** — ключ «BUGFIX-null-null» ожидает только `["bugfix-triage"]`, но continuation-ходы (orchestrator.md:54–57) re-эмитируют расширенный массив при том же ключе. Добавить варианты после `PIPELINES` (:1412):

```typescript
// v6 (Phase 11.1в): легальные варианты для ключей с ветвлением/loop'ами
const PIPELINE_VARIANTS: Record<string, string[][]> = {
  "orchestrator:BUGFIX-null-null": [
    ["bugfix-triage"],  // Turn 1
    ["bugfix-triage", "worker", "utility"],  // TRIAGE_RESULT: SIMPLE
    ["bugfix-triage", "plan-bug", "execute-bug", "advisor", "dev-reviewer", "rework", "consistency-checker", "utility"]  // TRIAGE_RESULT: DEEP
  ]
}
```

Модифицировать сравнение (:1433–1438):

```typescript
const variants = PIPELINE_VARIANTS[`${agent}:${key}`]
const matches = variants
  ? variants.some(v => JSON.stringify(pipeline) === JSON.stringify(v))
  : JSON.stringify(pipeline) === JSON.stringify(expected)
if (!matches) {
  return {
    valid: false,
    error: `Pipeline mismatch for ${agent} ${key}. Expected: [${(variants ? variants.map(v => v.join(", ")).join("] | [") : expected!.join(", "))}], got: [${pipeline.join(", ")}]`
  }
}
return { valid: true }
```

- **Примечание:** fail-open :1425 (`Unknown agent, allow`) СОХРАНИТЬ — функция вызывается только для primaries (caller-guard :548), ветка мертва, но безопасна.

### 11.2. Кросс-валидация полей

⚠️ **Корректировка сигнатуры:** правила 2–3 используют `jsonContent.plan_source` — расширить сигнатуру (:1392) и вызов (:557):

```typescript
function validatePipeline(agent: string, type: string | null, complexity: string | null,
  planExists: boolean | null, pipeline: string[], jsonContent?: any): { valid: boolean; error?: string }
// вызов :557 → validatePipeline(currentAgent, type, complexity, planExists, pipeline, jsonContent)
```

Правила вставить после OUT OF SCOPE early-return (11.1a), ДО построения key:

```typescript
// v6 (Phase 11.2): cross-field validation (fail-closed)
// Rule 1: SUPERCOMPLEX требует plan_exists=true (orchestrator.md CRITICAL RULE, Example 6/Q2)
if (type === "DEV" && complexity === "SUPERCOMPLEX" && planExists === false) {
  return { valid: false, error: "SUPERCOMPLEX requires plan_exists=true" }
}
// Rule 2: plan_source только при plan_exists=true
if (jsonContent?.plan_source && !planExists) {
  return { valid: false, error: "plan_source requires plan_exists=true" }
}
// Rule 3 (orchestrator): complexity=null только для BUGFIX/DEVOPS.
// Исключение: DECOMPOSITION Turn A (DEV-null-false, whitelist 11.1б) —
// БЕЗ него правило ломает Example 7 (Q3 запрещает immediate classification).
if (agent === "orchestrator" && complexity === null &&
    !["BUGFIX", "DEVOPS"].includes(String(type)) &&
    !(type === "DEV" && planExists === false &&
      pipeline.length === 1 && pipeline[0] === "dev-planner")) {
  return { valid: false, error: "complexity=null only for BUGFIX/DEVOPS (exception: DECOMPOSITION Turn A)" }
}
```

- ⚠️ Rule 3 в формулировке spec («complexity=null только для BUGFIX/DEVOPS») БЕЗ исключения ломает: (1) DECOMPOSITION Turn A — покрытие выше; (2) OUT OF SCOPE (type=null, complexity=null) — покрыт early-return 11.1a. Guard `agent === "orchestrator"` обязателен: BUGFIX/DEVOPS — типы orchestrator; у plankestrator своя логика (ambiguous → COMPLEX, null допустим только в OUT OF SCOPE).
- Rule 2: в OUT OF SCOPE JSON `plan_source: null` → falsy → не срабатывает ✓.
- **Порядок реализации:** Phase 11 — ПОСЛЕДНЯЯ в Части II (flip default'а опасен; к моменту включения все легальные варианты уже выявлены smoke-прогонами Phase 10/17).

---

## Phase 12: Plugin P1 — SELF_WORK_MARKERS для orchestrator

### 12.1. Добавить ключ orchestrator (:165–171)

- **OLD:** `const SELF_WORK_MARKERS: Record<string, string[]> = { plankestrator: [ ...9 маркеров :166–170... ] }`
- **NEW:**

```typescript
const SELF_WORK_MARKERS: Record<string, string[]> = {
  // v6 (Phase 12): orchestrator self-work = пишет анализ/имплементацию сам
  // вместо делегирования (worker/dev-planner/bugfix-triage)
  orchestrator: ["## Findings", "## Analysis", "## Implementation", "## Root Cause"],
  plankestrator: [
    "## Findings", "## Research", "Executive Summary", "## Analysis",
    "### Root Cause", "## Recommendations", "## Overview",
    "## Выводы", "## Результаты исследования"
  ]
}
```

- Блок установки флага (:661–682) уже генерик (`SELF_WORK_MARKERS[lockedAgentName]`, guard'ы: assistant-role :662–663, depth>0 :355) — заработает без правок. Комментарий :156 «plan/research-работы» → «self-work (plan/research/implementation)».

### 12.2. (ОБЯЗАТЕЛЬНОЕ дополнение) Потребление для orchestrator

⚠️ Без 12.2 фаза 12.1 = log-only: потребление `selfWorkDetected` (:854–875) заперто внутри plankestrator-only INSPECTION GATE (guard :814). Добавить блок в `tool.execute.before` после read-lock (:750), зеркальный :854:

```typescript
// v6 (Phase 12.2): self-work consumption for orchestrator (mirror of :854–875).
// Блокируются ТОЛЬКО inspection-инструменты; Task-вызовы НЕ блокируются —
// делегирование и есть желаемая коррекция (семантика :653–655).
if (selfWorkDetected && lockedAgentName === "orchestrator" &&
    (input.tool === "read" || input.tool === "grep" || input.tool === "glob")) {
  await client.app.log({ body: { service: "workflow-enforcement", level: "error",
    message: `INSPECTION BLOCKED — self-work content detected in previous orchestrator message`,
    extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool } } })
  throw new Error(`
⛔ SELF-WORK CONTENT DETECTED IN YOUR PREVIOUS MESSAGE

You are running as: orchestrator (identity-locked).
Your last message contained analysis/implementation markers (e.g. "## Findings",
"## Analysis", "## Implementation", "## Root Cause"). Producing such CONTENT is
self-work — it belongs to worker / dev-planner / bugfix-triage / docs-writer, NOT to you.

Fix: Identity line → JSON block → ONE Task call with next_agent from your routing table → ack line.
`)
}
```

- **Примечание:** реальная добавленная стоимость — Turn 1 ДО первого Task (после первого Task инспекции уже заблокированы read-lock'ом :735–750). Флаг `selfWorkDetected` не сбрасывается до session.created (:238) — для orchestrator это безопасно: финальное summary с легальным «## Root Cause» в конце сессии блокирует только уже ненужные инспекции (см. R-Part II в Risks).

---

## Phase 13: Plugin P1 — Max ONE Task call per turn

### 13.1. State-переменные (после :135, в блоке 9.0)

```typescript
const taskCallsPerTurn = new Map<string, number>()   // agent → Task-вызовов в текущем turn
const lastTurnMessageID = new Map<string, string>()  // agent → messageID текущего turn (dedup сброса)
```

### 13.2. Считать Task-вызовы (tool.execute.before)

⚠️ **Две верифицированные корректировки spec:**
- **(а) Атрибуция.** Условие spec `input.tool === "task"` БЕЗ depth-guard'а сломает вложенные делегирования сабагентов: research-writer-complex легально диспетчит ПАРАЛЛЕЛЬНУЮ scout-wave (mcp-search ∥ mcp-read ∥ mcp-github ∥ devops-readonly ∥ scout — ARCHITECTURE.md §2, PIPELINE GUIDE row 4 plankestrator). Их tool-вызовы приходят при `activeTaskDepth > 0`. Считать только вызовы САМОГО primary: размещать ПОСЛЕ depth-bypass (:697–710, return при depth>0) — т.е. после plan-mode bypass (:727), рядом с гейтом 9.0(в).
- **(б) Дыра параллельного fan-out.** Два Task в ОДНОМ сообщении primary: первый вызов → depth=1; второй попадает в :697–709 (warn + return = ПРОПУЩЕН — существующий warn :704 прямо называет кейс «prohibited parallel Task from primary»). Без закрытия дыры правило «max ONE» обходится одним сообщением с двумя Task.

**NEW-1** (основной счётчик) — вставить после :727, перед :730:

```typescript
// v6 (Phase 13.2): max ONE Task call per turn (orchestrator.md:193 / plankestrator PROHIBITIONS).
// Только activeTaskDepth === 0 (depth-bypass :697 выше отфильтровал сабагентов).
if (input.tool === "task" &&
    (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {
  const count = taskCallsPerTurn.get(currentAgent) || 0
  if (count >= 1) {
    await client.app.log({ body: { service: "workflow-enforcement", level: "error",
      message: `SECOND TASK CALL IN SAME TURN — ${currentAgent} (count=${count})`,
      extra: { agent: currentAgent, count } } })
    throw new Error(`
⛔ MAX ONE TASK CALL PER TURN: already made 1 Task call in this turn.
Wait for the subagent result, then issue the NEXT message:
identity line → JSON → ONE Task call → ack.
`)
  }
  taskCallsPerTurn.set(currentAgent, count + 1)
}
```

**NEW-2** (закрытие дыры (б)) — в depth-bypass, в блок `if (input.tool === "task")` (:698–708), после warn-лога:

```typescript
// v6 (Phase 13.2б): caller = primary (top-level session) → parallel Task = violation.
// Caller = subagent (child session) → legitimate nested delegation, warn только.
const callerSessionID = (input as any).sessionID
if (topLevelSessionID && callerSessionID && callerSessionID === topLevelSessionID) {
  throw new Error(`
⛔ PARALLEL TASK CALL BLOCKED — a subagent is already running (depth=${activeTaskDepth}).
Primary agent dispatches EXACTLY ONE Task per turn and waits for the result.
`)
}
```

Для NEW-2: в блоке :234–241 (session.created, non-child) зафиксировать `topLevelSessionID`:

```typescript
let topLevelSessionID: string | null = null  // state-блок после :135
// в :234–241:
topLevelSessionID = String((event as any).properties?.session?.id
  || (event as any).sessionID || (event as any).properties?.sessionID || "") || null
```

⚠️ При реализации проверить фактическое имя поля sessionID в payload `session.created` и в `input` tool.execute.before (в коде используется несколько вариантов чтения, напр. :519, :718); если надёжной атрибуции нет — NEW-2 деградирует до существующего warn (NEW-1 продолжает работать для последовательных вызовов).

### 13.3. Сброс на message.updated — turn boundary

⚠️ **Корректировка якоря и логики:** spec-якорь :348 — ДО сабагент-ветки (:355) и ДО определения `message` (:409–412); безусловный `taskCallsPerTurn.set(currentAgent, 0)` на каждый message.updated обнуляет счётчик на КАЖДОМ streaming-chunk'е (в т.ч. между двумя tool-вызовами одного сообщения — части сообщения обновляются → событие fires) → гейт 13.2 не сработает НИКОГДА. Корректный anchor: primary-ветка, после :412 (`if (!message) return`), с messageID-дедупом:

```typescript
// v6 (Phase 13.3): turn boundary = НОВОЕ сообщение primary. Dedup по messageID:
// message.updated fires на каждый chunk — сброс только при смене сообщения.
const turnMsgId = String((message as any).id || (message as any).info?.id || "")
if (currentAgent && turnMsgId && lastTurnMessageID.get(currentAgent) !== turnMsgId) {
  lastTurnMessageID.set(currentAgent, turnMsgId)
  taskCallsPerTurn.set(currentAgent, 0)
}
```

- **Проверка семантики:** сообщение primary с Task#1 → chunk-события того же msgId не сбрасывают счётчик → Task#2 в том же сообщении блокируется ✓; следующее сообщение (новый msgId) → счётчик 0 ✓; сообщения сабагентов (depth>0) не доходят до :409 (return :406) → не сбрасывают ✓.

---

## Phase 14: Plugin P1 — Rework loop max 3 + BLOCKER STOP

### 14.1. State-переменные (после :135, в блоке 9.0)

```typescript
const reworkCount = new Map<string, number>()        // agent → rework-диспетчей за сессию (max 3)
const blockerEscalations = new Map<string, number>() // agent → severity=blocker за сессию (stop после 3-го)
```

### 14.2. Считать rework-вызовы (tool.execute.before)

⚠️ **Корректировка spec:** `input.subagent_type` не существует — в `tool.execute.before` аргументы читаются из `output.args` (существующий паттерн :718: `(output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type`); в Task-секции уже определена переменная `targetAgent` — использовать её. Якорь: Task-ветка, ПОСЛЕ определения `targetAgent`, ПЕРЕД JSON-before-Task гейтом (:1008). Throw здесь ПРЯМОЙ легитимен (tool.execute.before блокирует сам вызов).

```typescript
// v6 (Phase 14.2): rework loop max 3 (orchestrator.md:59, SEVERITY RULES :138)
if (targetAgent === "rework") {
  const count = reworkCount.get(currentAgent ?? "") || 0
  if (count >= 3) {
    await client.app.log({ body: { service: "workflow-enforcement", level: "error",
      message: `REWORK LOOP MAX 3 EXCEEDED — ${currentAgent} (count=${count})`,
      extra: { agent: currentAgent, count } } })
    throw new Error(`
⛔ REWORK LOOP MAX 3: rework already invoked 3 times in this session.
The blocker is persistent — STOP the loop and escalate to the user:
final summary with the unresolved findings (BLOCKER ack format per SEVERITY RULES).
`)
  }
  reworkCount.set(currentAgent ?? "", count + 1)
}
```

- ⚠️ **Порядок инкремента:** счётчик инкрементируется ДО нижележащих гейтов Task-секции (:1008 JSON-before-Task, :1053 routing-table) — если 4-й вызов rework будет заблокирован одним из них, `reworkCount` уже увеличен (ложный +1). Приёмлемо: rework-вызов без JSON или вне routing table — уже нарушение, сессия в любом случае в аварийном состоянии; точный счёт после него несуществен. При желании — перенести инкремент ПОСЛЕ routing-table throw (:1053).

### 14.3. Считать blocker-эскалации (message.updated)

⚠️ **Корректировка якоря:** JSON ревьюеров приходит в СООБЩЕНИЯХ САБАГЕНТОВ → первичная ветка message.updated их не видит (depth>0 → ветка :355–407, return :406). Anchor: внутри `activeTaskDepth > 0` ветки, в блоке `if (String(subJson.severity) === "blocker")` (:375–379), после существующего лога. Throw в event-хуке инертен → флаг `blockerStop` (потребление — гейт 9.0(в): блокирует СЛЕДУЮЩИЙ tool-вызов primary, принуждая к финальному summary вместо 4-й итерации). Дедуп по messageID обязателен (streaming re-fires):

```typescript
// v6 (Phase 14.3): BLOCKER STOP after 3 (orchestrator.md:138 — «escalate to user if persists»)
const blockerMsgId = String((subMessage as any).id || (subMessage as any).info?.id || "")
if (blockerMsgId && !processedMessageIDs.has(blockerMsgId + ":blocker")) {
  processedMessageIDs.add(blockerMsgId + ":blocker")
  const bCount = (blockerEscalations.get(currentAgent ?? "") || 0) + 1
  blockerEscalations.set(currentAgent ?? "", bCount)
  await client.app.log({ body: { service: "workflow-enforcement", level: "error",
    message: `BLOCKER ESCALATION COUNTED — ${bCount}/3 (${subAgent})`,
    extra: { agent: currentAgent, reviewer: subAgent, count: bCount } } })
  if (bCount >= 3) {
    blockerStop = true
    violationDetail = `BLOCKER STOP AFTER 3: blocker persisted after 3 rework iterations (${subAgent}). Escalate to the user in the final summary — do NOT dispatch another Task.`
  }
}
```

- `blockerStop` НЕ сбрасывается recovery 9.0(г) (кумулятивный) — разблокировка только через session.created (9.0(д)).
- Ключ счётчика — `currentAgent` (primary, module-level, сохранён при depth>0 ✓); `subJson`/`subAgent`/`subMessage` — переменные ветки :360–363.
- Условие spec `jsonContent?.severity === "blocker"` адаптировано к `subJson` ветки; placement внутри существующего `if (:375)` гарантирует, что считается только severity ревьюеров из SEVERITY_AGENTS (:86).

### 14.4. Сброс на session.created

⚠️ Корректировка якоря — как в 10.4: блок :234–241 (НЕ :196); `reworkCount.clear()` + `blockerEscalations.clear()` уже входят в сводный сброс 9.0(д).

---

## Phase 15: Plugin P1 — Severity-гейт для primary-сообщений

### 15.1. Проверять severity в JSON самого primary

⚠️ **Корректировка якоря:** не «после :529» (это внутри identity-drift ветки, unlocked-else :526–542), а primary JSON-блок :548 — вставить сразу после строки `if (jsonContent && (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {` (:548), ПЕРЕД pipeline-валидацией (:556):

```typescript
// v6 (Phase 15): severity в JSON PRIMARY — валидировать по таксономии (:87).
// Сейчас severity проверяется только у сабагентов (ветка :363–373);
// primary может вернуть severity (напр. при re-эмиссии в rework-loop) —
// невалидное значение = schema violation.
if (jsonContent.severity !== undefined && jsonContent.severity !== null &&
    !VALID_SEVERITIES.includes(String(jsonContent.severity))) {
  invalidJSON = true  // → THROW через гейт 9.0(в) (механизм Phase 9.4)
  violationDetail = `INVALID SEVERITY: ${String(jsonContent.severity)}, expected ${VALID_SEVERITIES.join("|")}`
  await client.app.log({ body: { service: "workflow-enforcement", level: "error",
    message: `PRIMARY SEVERITY INVALID — ${currentAgent}: ${violationDetail}`,
    extra: { agent: currentAgent, severity: String(jsonContent.severity) } } })
}
```

- Использовать существующую `VALID_SEVERITIES` (:87), НЕ дублировать литерал `["nit","concern","blocker"]` из spec.
- ⚠️ Throw из spec заменён на флаг `invalidJSON` (единый механизм 9.0; throw в message.updated инертен).
- **Альтернатива (zero-code, рекомендуется рассмотреть):** добавить `severity: [...VALID_SEVERITIES]` в `VALID_VALUES.orchestrator` и `VALID_VALUES.plankestrator` (:60–72) → `validateJSONOutput` (:1483–1488) проверит автоматически → эскалация уже покрыта Phase 9.4. Минус: менее специфичный текст ошибки. Выбрать один из двух вариантов, НЕ оба (двойной лог).

---

## Phase 16: Plugin P1 — Строгий формат ack (warn-only аудит)

### 16.1. Валидировать ack-формат

**Якорь:** else-ветка валидного JSON (:603–614), после единого state-блока 10.2. Условие: только delegation-ходы (`jsonContent.next_agent` truthy) — OUT OF SCOPE и финальные ходы (`next_agent: null`) ack НЕ требуют.

⚠️ **Корректировки spec:** (1) `\w+` НЕ матчит имена агентов с дефисами (`plan-writer-simple`, `bugfix-triage`) → `[\w-]+`; (2) учтена SUPERCOMPLEX-варианта ack `→ STEP i/N (<id>): DELEGATED to <agent>` (Example 6 Части I; orchestrator.md SUPERCOMPLEX PIPELINE) — перед реализацией СВЕРИТЬ точный формат per-step ack с orchestrator.md:63–96 (если «for:» в STEP-варианте отсутствует — использовать вторую альтернативу regex, отмечено ниже); (3) content читать по существующему паттерну :622 (`String(message.content || message.text || "")`); (4) дедуп по messageID — иначе warn спамится на каждый streaming-chunk; (5) `client.app.log` вызывается с обёрткой `body:` (паттерн всего файла), не плоским объектом из spec.

```typescript
// v6 (Phase 16): strict ack format audit (warn-only — не блокирует;
// назначение: измеримый сигнал дрейфа формата перед будущей эскалацией)
if (jsonContent.next_agent && msgId && !processedMessageIDs.has(msgId + ":ack")) {
  processedMessageIDs.add(msgId + ":ack")
  const ackContent = String(message.content || message.text || "")
  // Базовый формат: "→ DELEGATED to <agent> for: <goal>"
  // SUPERCOMPLEX per-step: "→ STEP i/N (<id>): DELEGATED to <agent> ..."
  const ackPattern = /^→ (STEP \d+\/\d+\s*(\([^)]*\))?\s*:\s*)?DELEGATED to [\w-]+( for: .+)?$/m
  if (!ackPattern.test(ackContent)) {
    await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
      message: `ACK FORMAT INVALID — ${currentAgent}: expected "→ DELEGATED to <agent> for: <goal>" (SUPERCOMPLEX: "→ STEP i/N (<id>): DELEGATED to <agent> ...")`,
      extra: { agent: currentAgent, excerpt: ackContent.slice(0, 200) } } })
  }
}
```

- Переменная `msgId` — из единого state-блока 10.2 (ввести один раз в начале else-ветки, переиспользовать).
- Пост-ack проза («no analysis after ack», orchestrator.md:189; RESEARCH P1.8 вторая половина) — ВНЕ scope этой фазы (follow-up; см. Risks R16).

---

## Phase 17: Plugin P1 — Иммутабельность pipeline после Turn 1

### 17.1. Фиксация pipeline из первого JSON

Реализована в Phase 10.2 (guard `!prev` → `pipelineState.set(...)` только на первом валидном JSON; first-wins защита от streaming-перезаписи).

### 17.2. Проверка иммутабельности

Реализована в едином state-блоке Phase 10.2 (ветка `JSON.stringify(newPipeline) !== JSON.stringify(prev.pipeline)`):
- исключения — дословно из spec: `jsonContent.type === "BUGFIX"` (continuation), `jsonContent.plan_source === "DECOMPOSITION"` (Turn B), `jsonContent.severity === "nit"` (nit-skip);
- при исключении — ЗАМЕНИТЬ `prev.pipeline` (иначе следующий ход снова увидит тот же diff и re-trigger'ит проверку); пересчёт `currentStep` — см. код 10.2;
- при нарушении — флаг `pipelineImmutable` → THROW через гейт 9.0(в) (⚠️ вместо прямого throw из spec — единый механизм; текст `PIPELINE IMMUTABLE: pipeline changed after Turn 1` сохранён в `violationDetail`);
- ⚠️ размещение в else-ветке :603 (после валидаций, только для валидного JSON, messageID-дедуп) вместо «после строки ~603» без условий — обоснование в 10.2.

---

## Сводка новых throw/гейтов Части II

| # | Нарушение | Детект (место) | Доставка | Блокирует |
|---|-----------|----------------|----------|-----------|
| 9.1 | identity missing | message.updated :438–449 | флаг → гейт 9.0(в) | любой tool-вызов primary |
| 9.2 | pipeline mismatch | message.updated :556–568 | флаг → гейт | любой tool-вызов |
| 9.3+10.3 | next_agent mismatch | message.updated :571–585 | флаг → гейт | любой tool-вызов |
| 9.4+15.1 | invalid JSON / severity | message.updated :590–602 / :548 | флаг → гейт | любой tool-вызов |
| 9.5 | forbidden identity claim | message.updated :627 | флаг → гейт | любой tool-вызов |
| 9.6 | identity drift (locked) | message.updated :510 | ПРЯМОЙ throw (caveat) | остаток event-обработчика |
| 12.2 | self-work orchestrator | message.updated :661–682 (существующий) | `selfWorkDetected` → новый блок после :750 | read/grep/glob |
| 13.2 | 2-й Task в turn | tool.execute.before после :727 | ПРЯМОЙ throw | Task-вызов |
| 13.2б | параллельный Task (depth>0, caller=primary) | tool.execute.before :698 | ПРЯМОЙ throw (по sessionID-атрибуции) | Task-вызов |
| 14.2 | 4-й rework | tool.execute.before, Task-ветка до :1008 | ПРЯМОЙ throw | Task-вызов |
| 14.3 | 3-й blocker | message.updated :375–379 (сабагент-ветка) | флаг `blockerStop` → гейт (без recovery) | любой tool-вызов до конца сессии |
| 16.1 | ack-формат | message.updated :603–614 | warn-only | ничего (аудит) |
| 17.2 | pipeline изменён | message.updated :603–614 | флаг → гейт | любой tool-вызов |
| 11.x | unknown combo / cross-field | validatePipeline :1392–1441 | через 9.2 (флаг → гейт) | любой tool-вызов |

**Порядок реализации Части II:** 9.0 (механизм) → 9.1–9.6 → 10 → 12 → 13 → 14 → 15 → 16 → 17 → **11 последней** (fail-closed flip — после прогона всех легальных вариантов). Каждая фаза = отдельная сессия smoke-тестов (Verification 10–15); коммит через git-commit после каждой фазы или логической группы (9+10 — атом, см. 9.3).

---

## Verification

1. **Статический diff таблиц:** строки PIPELINE TABLE (orchestrator.md :43–52, plankestrator.md :43–50) байт-в-байт идентичны до/после; секции TURN ALGORITHM / JSON FORMAT / SEVERITY RULES / ADVISOR STEP RULES / PROHIBITIONS / PLUGIN ENFORCEMENT не затронуты (кроме точечных правок :188 и :156).
2. **Example↔Table cross-check (чек-лист 21 пример):** каждый массив `pipeline` и `next_agent` в примерах точно соответствует своей строке таблицы и `next_agent = pipeline[0]`. Отдельно: row 6 в примерах БЕЗ `rework` в базовом массиве; row 5 plankestrator не встречается НИ в одном примере.
3. **Plugin-совместимость (Часть I):** `workflow-enforcement.ts` не изменён (правится только в Части II — проверки 10–16); все агенты из примеров ∈ OPENCODE_ROUTING_TABLE (:26 в обоих файлах); тексты OUT OF SCOPE в примерах = дословно стандартные фразы (:160 / :103) без имён чужих агентов.
4. **ARCHITECTURE.md mirror:** A2/A3/A4 семантически идентичны секциям промптов; A1 добавлен; §2 флоу не изменены.
5. **Поведенческие smoke-тесты (свежие сессии):**
   - orchestrator: Ex1 («NullReferenceException…»), Ex5 (JWT), Ex7 Turn A (рефакторинг платёжного модуля → DECOMPOSITION, не immediate classification), Ex10 (исследуй кэширование → null, НЕТ Task call), Ex11 (mixed → BUGFIX), Ex12 («составь план миграции» → null, НЕ dev-planner).
   - plankestrator: Ex2 (GraphQL → row 2), Ex5 (очереди+план → row 6), Ex6 («исправь ошибку» → null, НЕТ Task call), Ex9 («почему тесты падают» → null).
   - Golden boundary pairs: «составь план рефакторинга» (null) vs «сделай рефакторинг» (DEV Q3) — обе через orchestrator; «исправь баг» (null) vs «спланируй исправление бага» (PLAN) — обе через plankestrator.
   - Критерии каждого прогона: identity line → JSON → ≤1 Task call → ack; пайплайн в JSON = ожидаемая строка; ноль plugin-ошибок; ноль forbidden-vocab логов.
6. **Identity probes:** `orchestrator-identity-probe` и `plankestrator-identity-probe` по-прежнему вызываются (регресс routing table).
7. **Token-бюджет:** orchestrator.md ≤ 380 строк, plankestrator.md ≤ 300 строк. Превышение → сокращать «Why» в примерах, не правила.
8. **Consistency-checker:** прогнать по проекту после landing (он исполняет предписания ARCHITECTURE.md — проверит зеркальность).
9. **Коммит Части I:** делегировать агенту `git-commit` (глобальное правило); коммит №1: orchestrator.md + plankestrator.md + ARCHITECTURE.md.

### Verification Части II (Phase 9–17, plugin)

10. **Загрузка плагина:** после каждой фазы opencode стартует без ошибок; в логах — `Workflow enforcement plugin initialized` (:177–183); TypeScript-синтаксис валиден (плагин компилируется рантаймом opencode — ошибки видны в стартовом логе). Grep-ре-анкоринг: OLD-блоки каждой фазы найдены ровно один раз ДО правки.
11. **Механизм флагов (Phase 9) — smoke-матрица свежих сессий:**
    - Сообщение БЕЗ identity-строки → следующий tool-вызов → `⛔ WORKFLOW VIOLATION — IDENTITY MISSING`; корректирующее сообщение (identity + валидный JSON) → разблокировка (recovery 9.0(г) — latest-message-wins).
    - JSON с pipeline вне таблицы (напр. `["worker"]` для DEV-COMPLEX-false) → throw `PIPELINE VALIDATION FAILED` на Task-вызове.
    - Невалидный JSON (пропущено поле из REQUIRED_JSON_FIELDS :55–57) → throw `INVALID JSON OUTPUT` (+ существующий гейт :1008 по-прежнему работает).
    - Фраза «I am plankestrator» в сообщении orchestrator → throw `FORBIDDEN IDENTITY CLAIM`; упоминание «plan-writer-simple» в прозе → ТОЛЬКО лог (no throw, :641–644 сохранён для имён).
    - Identity drift при lock (JSON `agent` ≠ locked) → throw из event-хука (9.6); зафиксировать фактическое поведение рантайма: если throw проглочен и поток продолжился — деградировать до флага (решение по итогам теста, см. 9.6 caveat).
    - Каждый throw предваряется error-логом `DEFERRED VIOLATION ENFORCED — <code>` РОВНО ОДИН раз (consume-once); повторный корректный ход проходит.
12. **Трекинг шага + иммутабельность (Phase 10, 17):** полные прогоны без ложных срабатываний: DEV COMPLEX (row 5, все 7 шагов), DEV SIMPLE row 4 с rework-loop (concern → rework → worker → consistency-checker → utility — loopback whitelisted), nit-skip (dev-reviewer nit → next=consistency-checker через expected=rework — whitelisted), BUGFIX SIMPLE и DEEP (continuation проходит), DECOMPOSITION Turn A→B (re-dispatch dev-planner проходит), SUPERCOMPLEX per-step. Негатив: смена pipeline mid-flow (без исключений) → throw `PIPELINE IMMUTABLE`; next_agent вне порядка (skip вперёд не через rework) → throw `NEXT_AGENT MISMATCH`. Streaming-режим: одно сообщение не инкрементирует currentStep дважды (дедуп processedMessageIDs).
13. **Fail-closed (Phase 11):** НЕ блокируются: OUT OF SCOPE (type=null, pipeline=[]), DECOMPOSITION Turn A (DEV-null-false), BUGFIX continuation (все 3 варианта), все 8 строк PIPELINE TABLE обоих агентов (прогнать примеры Части I как fixtures). Блокируются: DEV+SUPERCOMPLEX+plan_exists=false; plan_source при plan_exists=false; неизвестный complexity (напр. «MEDIUM»); type=DOCS при complexity=null; произвольная неизвестная комбинация.
14. **Счётчики (Phase 13–14):** два Task-вызова в одном сообщении/turn → второй → throw `MAX ONE TASK CALL PER TURN`; параллельный Task при активном сабагенте от primary (sessionID = top-level) → throw `PARALLEL TASK CALL BLOCKED`; **research-writer-complex dispatches параллельную scout-wave (RESEARCH COMPLEX row 4 plankestrator) → НЕ блокируется** (атрибуция 13.2(а)/(б) — критическая регрессионная проверка); 4-й rework → throw `REWORK LOOP MAX 3`; 3-й blocker от ревьюеров → следующий tool-вызов primary → throw `BLOCKER STOP AFTER 3`, финальное summary проходит (текст не блокируется).
15. **Регрессии существующих механизмов:** все 8 throw'ов до правок (:746, :777, :839/:863/:886, :1009, :1053/:1085) работают как раньше; identity probes (`orchestrator-identity-probe`, `plankestrator-identity-probe`) вызываются; дочерние сессии (parentID) НЕ сбрасывают состояние родителя (guard :210–220 + новые сбросы строго в :234–241); built-in Plan mode bypass (:716–727) сохранён; severity-валидация сабагентов (:363–404) не изменена (кроме добавления 14.3 внутри blocker-ветки); inspection budget plankestrator (3) и read-lock после первого Task не затронуты; SELF_WORK планkestrator (:854) работает как раньше.
16. **Коммит Части II + mirror:** коммит №2 через агента `git-commit`: workflow-enforcement.ts + точечное обновление ARCHITECTURE.md (секция A4 из Phase 8: слой 2 «forbidden vocabulary» — переформулировать: identity-токены → HARD (throw), имена агентов → log-only; добавить строки о новых гейтах: deferred-violation gate, step tracking, fail-closed, Task/rework/blocker-счётчики) — same-commit (mirror-правило :403). PLUGIN ENFORCEMENT секции промптов (orchestrator.md:196–205, plankestrator.md:166–174) правки НЕ требуют: они уже заявляют hard-enforcement — Часть II делает заявления правдой.

## Risks

| # | Риск | Вероятность | Митигция |
|---|------|-------------|----------|
| R1 | **Prompt bloat → instruction dilution:** +170/+110 строк на QWEN3.7-plus (temp 0.1) могут ослабить соблюдение hard rules | Средняя | Жёсткий бюджет строк (Verification 7); компактный формат «поле — одна строка»; примеры ПОСЛЕ правил; PROHIBITIONS + PLUGIN ENFORCEMENT остаются последними секциями (recency) |
| R2 | **Пример «закрепит» неверный пайплайн** (если разойдётся с таблицей или plugin ROUTING_TABLES) — модель начнёт воспроизводить ошибку | Низкая | Verification 2–3: байтовый cross-check каждого примера с таблицей до landing |
| R3 | **Дрейф правил ARCHITECTURE.md ↔ промпты** (нарушение same-commit правила :403) | Средняя | Phase 8 в том же коммите; Verification 4 + consistency-checker (Verification 8) |
| R4 | **Overfitting на примеры:** модель матчит поверхностные слова примеров вместо применения правил | Средняя | Заголовок обоих пример-разделов: «on conflict, RULES win»; контрастные пары в каждой границе (запусти тесты/тесты падают; сравни/сравни+спланируй; составь план/сделай) |
| R5 | **Forbidden-vocab шум:** тексты примеров с именами чужих агентов в OUTPUT-сообщениях триггерят логи плагина (:623–632) | Низкая | В примерах OUT OF SCOPE — только стандартная фраза; CROSS-ROUTING BOUNDARY #2 запрещает имена явно. (Списки чужих агентов в самих ПРОМПТ-секциях безопасны — промпт уже содержит «I am NOT plankestrator» :36) |
| R6 | **Обнаруженный пробел: `git-commit`** есть в OPENCODE_ROUTING_TABLE orchestrator (:26), но отсутствует в любой строке PIPELINE TABLE; «git commit-push-PR» маршрутизируется в row 2 (devops-agent) | — | НЕ чинить в этом плане: добавление строки требует изменения plugin ROUTING_TABLES (выходит за scope prompt-enhancement). Задокументировать как follow-up; в примерах git-операции → row 2 |
| R7 | **Row 5 plankestrator (RESEARCH+PLAN SIMPLE) — ловушка:** строка существует, плагин её пропустит, но правило :108 запрещает выбирать её намеренно | Низкая | PIPELINE GUIDE row 5 с пометкой «NEVER choose deliberately»; ни одного примера с row 5; Ex5 демонстрирует только row 6 |
| R8 | **Вставка ломает якоря плагина** (если плагин парсит заголовки секций промпта) | Очень низкая | Recon: плагин валидирует СООБЩЕНИЯ (identity line, JSON, vocab), не структуру промпта; существующие заголовки не переименовываются, кроме EXAMPLES plankestrator (F6) — проверить grep'ом, что строка «EXAMPLES» не используется в workflow-enforcement.ts до правки |

### Risks Части II (Phase 9–17, plugin)

| # | Риск | Вероятность | Митигция |
|---|------|-------------|----------|
| R9 | **Fail-closed (Phase 11) ломает легальные флоу:** OUT OF SCOPE (type=null, pipeline=[] — пустой массив truthy, validatePipeline вызывается :556), DECOMPOSITION Turn A (ключ «DEV-null-false» отсутствует в PIPELINES :1394–1403), BUGFIX continuation (3 варианта массива на один ключ) — без whitelist эскалация 9.2 заблокирует их через THROW | **Высокая без whitelist** | Whitelist 11.1(а)(б)(в) — ОБЯЗАТЕЛЬНО до flip'а :1429; Phase 11 выполняется ПОСЛЕДНЕЙ (все легальные варианты уже прогнаны smoke-тестами Phase 10/17); Verification 13 прогоняет все примеры Части I как fixtures |
| R10 | **Streaming re-fires message.updated:** событие fires на каждый chunk одного сообщения → не-идемпотентные операции дрейфуют: `currentStep` двойной инкремент, `taskCallsPerTurn` обнуляется между двумя Task одного сообщения (гейт 13.2 не срабатывает никогда), `blockerEscalations` инфляция (3 за одно сообщение), ack-warn спам | **Высокая без dedup** | MessageID-дедуп `processedMessageIDs` (9.0(б)) во всех не-идемпотентных точках: 10.2, 13.3 (`lastTurnMessageID`), 14.3, 16.1; Verification 12 (streaming-проверка single-increment) |
| R11 | **Throw в event-хуке инертен:** сообщение уже отправлено, рантайм может проглотить исключение (плагин сам отмечает :357–359) → иллюзия enforcement | Средняя | Единый механизм 9.0: детект в message.updated → флаг → THROW в tool.execute.before (блокирует РЕАЛЬНОЕ действие — tool-вызов); прямой throw только там, где он блокирует вызов (13.2, 14.2) либо где заказчик явно потребовал (9.6 — с caveat и планом деградации до флага по итогам Verification 11) |
| R12 | **Атрибуция вложенных Task:** наивный подсчёт `input.tool === "task"` без depth/sessionID-guard'а заблокирует легальный параллельный fan-out сабагентов (scout-wave research-writer-complex — ядро RESEARCH COMPLEX, ARCHITECTURE.md §2) → сломан пайплайн row 4/6 plankestrator | **Высокая без guard** | 13.2(а): подсчёт только при `activeTaskDepth === 0`; 13.2(б): параллельный Task блокируется ТОЛЬКО при `callerSessionID === topLevelSessionID`; fallback при ненадёжной атрибуции — NEW-2 деградирует до существующего warn :704; Verification 14 (прогон RESEARCH COMPLEX с wave — обязательный негатив-контроль) |
| R13 | **Дрейф якорей:** Phase 9–17 правят один файл последовательно — строки :441/:559/:573/... устаревают после первой же вставки | Высокая | Карта якорей привязана к снимку 2026-09-29; OLD-блоки процитированы дословно — после каждой фазы ре-анкоринг grep'ом по OLD-тексту (Verification 10: «найден ровно один раз ДО правки»); коммит после каждой фазы/группы (точечный revert возможен) |
| R14 | **Ложные срабатывания на легальных сообщениях:** (1) ранний streaming-chunk без identity/JSON → флаг, хотя итоговое сообщение валидно; (2) цитирование forbidden-фраз в служебном тексте; (3) «## Root Cause» в финальном BUGFIX-summary orchestrator → selfWorkDetected | Средняя | Recovery latest-message-wins (9.0(г)): чистое валидное сообщение снимает message-derived флаги до tool-вызова; consume-once семантика (после throw флаги сброшены — коррекция проходит); (3) не опасно: после первого Task инспекции уже заблокированы read-lock :735–750, а Task-вызовы self-work НЕ блокирует (:653–655) — финальное summary не пострадает |
| R15 | **SUPERCOMPLEX неоднозначность:** семантика `pipeline` для row 6 («full chain PER PLAN STEP») не формализована (RESEARCH: Implementation Notes) — ре-эмиссия массива на каждом шаге может триггерить 10.3/17.2; вариант цепочки с `rework` в loop'е отсутствует в PIPELINES «DEV-SUPERCOMPLEX-true» | Средняя | Verification 12 включает полный SUPERCOMPLEX-прогон (per-step ack, step-boundary rework); при ложных срабатываниях — точечная деградация: для `complexity === "SUPERCOMPLEX"` проверки 10.3/17.2 → log-only (константа `SUPERCOMPLEX_STRICT = false`), решение до Phase 11 |
| R16 | **Непокрытый scope (follow-up, НЕ делать в этом плане):** пост-ack проза («no analysis after ack», orchestrator.md:189 — P1.8 вторая половина); P2-пункты RESEARCH: inspection-бюджет Turn 1 для orchestrator + сужение :746 до `*plan*.md` (P2.10), hard-блок смены режима :419–432 (P2.11), явный `continuation`-режим в JSON (P2.12), проверка существования REVIEW_CONTEXT.md (P2.13), перекрёстные ссылки INSPECTION_BUDGET (P2.14) | — | Задокументированы здесь как backlog; в Phase 16 — только ack-формат (warn-only, безопасный аудит перед будущей эскалацией) |
| R17 | **Нет unit-тестов плагина:** регресс 8 существующих throw'ов и гейтов обнаружится только в runtime | Средняя | Verification 15 — полная регрессионная матрица (все существующие throw'ы + bypass'ы: plan-mode :716, builtin explore/general :1028, parentID :210, identity probes); поэтапные коммиты через git-commit; опционально master-константа `STRICT_ENFORCEMENT_V6` (false = все новые гейты log-only) для быстрого отката без revert |

## Estimated Effort

### Часть I (Phase 1–8, markdown-only)

| Фаза | Содержимое | Оценка |
|------|-----------|--------|
| Phase 1 | PIPELINE GUIDE orchestrator (~62 строки) | 30 мин |
| Phase 2 | 12 примеров (~65 строк) | 30 мин |
| Phase 3 | Decision tree + edge cases + cross-routing + фикс :188 (~55 строк) | 30 мин |
| Phase 4 | PIPELINE GUIDE plankestrator (~35 строк) | 20 мин |
| Phase 5 | 9 примеров + реструктура EXAMPLES (~50 строк) | 25 мин |
| Phase 6 | Decision tree + edge cases + cross-routing + фикс :156 (~45 строк) | 25 мин |
| Phase 7 | Сводная проверка (контент уже в 3/6) | 10 мин |
| Phase 8 | ARCHITECTURE.md sync (4 вставки, ~60 строк) | 30 мин |
| Verification 1–9 | Статические проверки + 10–12 smoke-тестов | 60–90 мин |
| **Подытог Часть I** | **~4–5 часов; сложность низкая-средняя; риск для кода нулевой (markdown-only)** | |

### Часть II (Phase 9–17, workflow-enforcement.ts)

| Фаза | Содержимое | Оценка |
|------|-----------|--------|
| Phase 9.0 | Единый механизм: state-блок (7 флагов + processedMessageIDs + topLevelSessionID), гейт 9.0(в) в tool.execute.before, recovery 9.0(г), сброс 9.0(д) в :234–241 | 45 мин |
| Phase 9.1–9.5 | 5 эскалаций log-only → флаг (по ~5 строк каждая) + FORBIDDEN_IDENTITY_TOKENS + правка комментария :641–644 | 30 мин |
| Phase 9.6 | Прямой throw identity drift + caveat-комментарий | 10 мин |
| Phase 10 | pipelineState + единый state-блок 10.2 (first-wins, messageID-дедуп, indexOf-продвижение) + замена :571–585 (10.3, loopback/rework-skip исключения) + сбросы | 60 мин |
| Phase 11 | Fail-closed :1429 + whitelist 11.1(а)(б)(в) (OUT OF SCOPE early-return, «DEV-null-false», PIPELINE_VARIANTS BUGFIX) + кросс-валидация 11.2 (3 правила, расширение сигнатуры) | 45 мин |
| Phase 12 | Ключ orchestrator в SELF_WORK_MARKERS + блок потребления 12.2 (mirror :854) | 20 мин |
| Phase 13 | taskCallsPerTurn + гейт 13.2 + закрытие параллельной дыры 13.2(б) (sessionID-атрибуция) + turn-boundary сброс 13.3 (lastTurnMessageID) | 40 мин |
| Phase 14 | reworkCount (throw в Task-ветке) + blockerEscalations (сабагент-ветка :375, флаг blockerStop без recovery) | 30 мин |
| Phase 15 | Severity-гейт primary (или zero-code вариант через VALID_VALUES — выбрать один) | 15 мин |
| Phase 16 | Ack-regex (warn-only, дедуп, SUPERCOMPLEX-варианта; сверка формата с orchestrator.md:63–96) | 20 мин |
| Phase 17 | Реализован внутри 10.2 — отдельная работа: сверка исключений и замена state | 10 мин |
| Verification 10–16 | Загрузка плагина + smoke-матрица Phase 9 (~6 сценариев) + полные прогоны пайплайнов (10/17) + fail-closed fixtures (13) + счётчики и негатив-контроль scout-wave (14) + регрессионная матрица (15) | 90–120 мин |
| **Подытог Часть II** | **~6–7 часов; сложность средняя-высокая (runtime-код без unit-тестов, streaming-семантика, атрибуция сессий); риск средний — mitigation: поэтапные коммиты, Phase 11 последней, регрессионная матрица** | |

| **ИТОГО (обе части)** | **~10–12 часов. Два коммита через git-commit: №1 = Часть I (3 markdown-файла), №2 = Часть II (плагин + mirror-правка ARCHITECTURE.md)** | |

**Порядок выполнения:**
1. **Часть I:** Phase 8 (A1–A4) выполнять ПАРАЛЛЕЛЬНО с Phase 3/6 (одно и то же правило формулируется один раз и копируется в оба файла). Коммит №1 — через агента git-commit.
2. **Часть II:** строго ПОСЛЕ коммита №1 (промпты уже заявляют hard-enforcement — плагин догоняет; обратный порядок оставил бы окно с незаблокированными нарушениями при уже обновлённых промптах). Внутри Части II: 9.0 → 9.1–9.6 → 10 → 12 → 13 → 14 → 15 → 16 → 17 → 11 (fail-closed последней). Phase 9.3 и 10.3 — один атом (эскалация next_agent без реального step-tracking даст ложные блокировки на Turn 2+). После каждой фазы: smoke-прогон + ре-анкоринг grep'ом; коммит через git-commit после каждой фазы или логической группы.
3. **Коммит №2:** workflow-enforcement.ts + точечная правка ARCHITECTURE.md (A4: слой 2 → «identity-токены HARD / имена log-only» + новые гейты) — same-commit по mirror-правилу :403.

---

```json
{
  "plan_file": "PLAN_PROMPT_ENHANCEMENTS.md",
  "plan_written": true,
  "next_action": "plan-reviewer-complex should read from plan_file"
}
```
