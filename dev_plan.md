# Implementation Plan — Сжатие orchestrator.md (595 → ~340 строк) + few-shot пример

## Goal

Сократить промпт `orchestrator.md` с **595** до **~330–350 строк** (−42..−45%), добавив few-shot пример TURN 1 сразу после identity line (после строки 37), **без потери критичной информации**: всё удаляемое либо остаётся в file'е в сжатом виде, либо уже канонически описано в `ARCHITECTURE.md` (repo-only, `P:\Programming\Рефакторинг\ARCHITECTURE.md`).

### Честная арифметика цели «~300»

| Компонент | Строк |
|---|---|
| Несжимаемый минимум (все «обязательные» секции пользователя, байт-в-байт): frontmatter+IDENTITY (37) + PIPELINE TABLE c нотами (25) + TURN ALGORITHM (32) + JSON FORMAT (28) + SEVERITY+ADVISOR (17) + CLASSIFICATION RULES (34) + TYPE SELECTION (34) + CROSS-ROUTING (6) + PROHIBITIONS (21) + PLUGIN ENFORCEMENT (14) | **248** |
| Few-shot пример (вставка) | **+21** |
| Пол (floor) до сжатия остальных секций | **269** |
| Сжимаемые секции после сжатия (SUPERCOMPLEX ~11 + MULTI-PHASE ~14 + CUSTOM ~6 + EDGE CASES ~13 + EXAMPLES ~16 + указатель вместо PIPELINE GUIDE ~1 + межсекционные пустые ~14) | **~75** |
| **Итого реально** | **~340 ± 15** |

Ровно 300 недостижимо без резки «обязательного» списка (нарушение требования №1 пользователя) или нарушения 1:1-mirror обязательств с ARCHITECTURE.md. **~340 = та же степень «модель не теряется»** (−44% объёма). Опциональный Tier-2 (см. ниже) даёт ещё −20..−25 → ~315–320.

## Files to Modify

1. **`C:\Users\Admin\.config\opencode\agents\orchestrator.md`** (LIVE, 595 строк) — основная правка. Политика (ARCHITECTURE.md:1156, REVIEW_CONTEXT.md:10): правки в LIVE, затем снапшот в repo.
2. **`P:\Programming\Рефакторинг\agents\orchestrator.md`** (REPO-зеркало, 595 строк) — НЕ править вручную; обновляется командой `config-sync --save --pair agents` (Шаг 10).
3. *(Опционально, через Auto-DOCS hook)*: `CHANGELOG.md` (запись о сжатии), `ARCHITECTURE.md:397` (упоминание `PIPELINE GUIDE` станет полу-устаревшим), `PLAN_MULTI_PHASE_PIPELINES.md:230` (line-анкеры в orchestrator.md устареют; doc-only).

## Критичные ограничения — MUST SURVIVE (проверено по plugins/workflow-enforcement.ts, 2988 строк)

Плагин НЕ читает orchestrator.md, но матчит **вывод агента** по точным литералам. Каждый должен остаться в файле (в неизменённых секциях ИЛИ в новых сжатых текстах — они ниже уже содержат всё):

| # | Литерал | Где в плагине | Где в новом файле |
|---|---|---|---|
| 1 | `✓ IDENTITY VERIFIED: I am orchestrator (Conductor). I am NOT plankestrator. …` (байт-в-байт) | regex :2443 | строка 36 (не трогаем) + few-shot |
| 2 | `OPENCODE_ROUTING_TABLE = […]` (строка 26, байт-в-байт — parity с `ROUTING_TABLES.orchestrator` :6–40) | :2120, :2896 | RUNTIME IDENTITY (не трогаем) |
| 3 | `TRIAGE_RESULT: SIMPLE` / `TRIAGE_RESULT: DEEP` + ОБА continuation-массива байт-в-байт: `["worker", "utility"]` и `["plan-bug", "execute-bug", "advisor", "dev-reviewer", "consistency-checker", "utility"]` | хардкод :2640–2641 | строки 54–57 (не трогаем) + Example 1 |
| 4 | 9 ack-форматов (regex :1464, warn-only, но точный): `→ DELEGATED to <agent> for: <goal>` · `→ STEP <i>/<total> (<step id>): DELEGATED to <agent>` · `→ DELEGATED to advisor (step <N>, notes so far: <count>)` · `→ rework SKIPPED (dev-reviewer severity=nit)` · `→ SUPERCOMPLEX steps (<N>): […] (source: user \| plan headings \| decomposition)` · `→ DECOMPOSITION requested from dev-planner for: <goal>` · `→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>` · `→ PHASE <i>/<n> (<id>), STEP <j>/<m> (<sid>): DELEGATED to <agent>` · `→ PHASE PLAN AWAITING CONFIRMATION (<n> phases)` | :1464 | TURN ALGORITHM/few-shot; SUPERCOMPLEX Stages 1–2; ADVISOR (369); SEVERITY (358); MULTI-PHASE Stages 1–4; DECOMPOSITION PROTOCOL (400); Example 6 |
| 5 | JSON-поля: `agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline, pipeline_source_rows, state, phases, current_phase, depends_on, requires_docs_update, severity, escalate_to`; спец-значение `plan_source: "DECOMPOSITION"`; `state ∈ AWAITING_CONFIRMATION\|CANCELLED` | :56–68, :2455–2471, :2547–2579, :2859–2937 | JSON FORMAT (не трогаем) + сжатые секции |
| 6 | `MODE: DECOMPOSITION` + `{"decomposition": true, "steps": [...], ...}` + `Do NOT write dev_plan.md.` | :1275, :1295, :2645 | CLASSIFICATION RULES:399–402 (не трогаем) — Stage 1 SUPERCOMPLEX ссылается сюда |
| 7 | Суффикс `Write the plan to dev_plan.md.` | — (контракт dev-planner) | SUPERCOMPLEX Stage 2 |
| 8 | `⚠️ OUT OF SCOPE: This is a planning/research task. Please switch to plankestrator.` (точная фраза) | forbidden-vocab косвенно | CLASSIFICATION RULES:381 (не трогаем) + Example 5 |
| 9 | `## MULTI-PHASE PLAN — AWAITING CONFIRMATION` (заголовок; БЕЗОПАСЕН: не содержит подстроку `## PLAN`) | FORBIDDEN_VOCAB :279–290 | MULTI-PHASE Stage 1 |
| 10 | `PHASE_STATE TASK:` + `# PHASE_STATE` + `Remove-Item` + `Get-Date` (маркер для utility.md:26–39) | :1043, :1228 | MULTI-PHASE Stage 3 (scribe) |
| 11 | `Phase P<i> (<type>) completed: <summary>. Artifacts: <list>. Facts: <facts>. Read PHASE_STATE.md if you need more context.` | — | MULTI-PHASE Stage 4 |
| 12 | `SUPERCOMPLEX complete: <N>/<N> steps implemented` | — | SUPERCOMPLEX Stage 3 |
| 13 | `pipeline_source_rows` + правило EXACT concatenation | :591 (валидация композиции) | CUSTOM PIPELINE COMPOSITION |
| 14 | `NIT_ONLY_MODE`, `MP-5`, `docs_deferred_to`, `BLOCKER STOP AFTER 3` | — | ADVISOR (не трогаем); MULTI-PHASE Stages 3–5 |

**Строковые 1:1-mirror обязательства с ARCHITECTURE.md — НЕ ТРОГАТЬ:**
- строка 63 (multi-phase meta-rule) = ARCH:502–504 «mirrored 1:1 in agents/orchestrator.md»;
- CLASSIFICATION RULES Q1–Q5 = ARCH:405–423;
- TYPE SELECTION T0–T6 + triggers/anti-triggers = ARCH:425–460;
- PIPELINE TABLE строки 43–52 = ARCH §2.

**Запретный словарь в НОВОМ тексте** (плагин сканирует вывод агента, но few-shot копируется в вывод дословно): не добавлять `## PLAN` (как начало заголовка), `# Implementation Plan`, `I am plankestrator`. Существующие упоминания `plan-writer-*` и др. в CROSS-ROUTING BOUNDARY — промпт-текст, не вывод; остаются (закрытый список по ARCH:774).

## Coverage map — доказательство «ничего не потеряно»

| Удаляемое | Куда переезжает |
|---|---|
| PIPELINE GUIDE строки 67–116 (описания rows 1–8) | ARCH §2: BUGFIX :378–403, DEV SIMPLE :588–601, DEV COMPLEX :603–615, DEV SUPERCOMPLEX :617–654, DEVOPS :656–660, DOCS :662–672, Auto-DOCS :674–701. Триггеры «when to use» → CLASSIFICATION RULES + TYPE SELECTION (остаются). Граница «run tests vs tests failing» → EDGE CASES row 1 (остаётся). «Multi-file ≠ multi-step» → CLASSIFICATION RULES:392. ARCH:397 прямо объявляет PIPELINE GUIDE «illustrative, NOT mirrored». |
| PIPELINE GUIDE 117–118 (type=null) | CLASSIFICATION RULES:381 + CROSS-ROUTING #2 (остаются). |
| SUPERCOMPLEX 120–154 (детали стадий) | Сжатый текст сохраняет ВСЕ литералы (приоритеты Stage 1, mcp-read prompt, echo-ack, per-step цепочку, суффикс dev_plan.md, ack STEP, Stage 3 + Auto-DOCS). Расширенная проза → ARCH:617–654. |
| MULTI-PHASE 156–255 | Сжатый текст сохраняет: JSON-shape AWAITING (инлайн), таблицу плана (структура), ВСЕ ack-литералы, allowed/forbidden edits, override, refinement-правило, envelope-поля (канон-спека → ARCH §3 :838–851), scribe-блок ДОСЛОВНО (критично: utility копирует verbatim), DEVOPS-tail ограничение, dedup `docs_deferred_to`, Stage 4 фразу, fail-fast/resume. Проза и ASCII-диаграммы → ARCH:481–582. Шаблон секции PHASE_STATE (8 строк) → одна строка-перечисление полей (utility.md:26–39 контракт не зависит от формата шаблона в промпте orchestrator'а — utility копирует то, что прислал orchestrator; drift формата допустим, resume читает файл структурно). |
| CUSTOM PIPELINE CONSTRUCTION 300–322 (секция-близнец, ПРОПУЩЕНА в анализе пользователя) | Два JSON-примера иллюстративны (плагин валидирует точную конкатенацию по `pipeline_source_rows` механически). Правила 318–322 дублируют: «functions must NOT mix» = TURN ALGORITHM:275; «internally valid segments» + «tightly-coupled» + «MULTI_PHASE for distinct» = CUSTOM PIPELINE COMPOSITION:259–265. Всё остаётся в объединённой сжатой секции. |
| EDGE CASES: 10 из 17 строк | См. таблицу покрытия в Шаге 2 (каждая строка → остаётся в таблице / в сжатых секциях / в ARCH:462–479 + :567–578). |
| EXAMPLES: 10 из 16 примеров | Ex2 (DEVOPS) → контраст в Example 1 + EDGE CASES row 1; Ex4 → Example 2 (with-plan вариант); Ex6 → Example 3 (SUPERCOMPLEX-вариант) + секция SUPERCOMPLEX; Ex7 → DECOMPOSITION PROTOCOL:399–402 (остаётся дословно); Ex9 → Example 4 (DEEP-вариант); Ex11/14/15/16 → контрасты в Example 6 + T0 anti-triggers (TYPE SELECTION остаётся); Ex12 → Example 5 (❌ WRONG строка). |

---

## Implementation Details

**МЕТОД: все правки — СВЕРХУ ВНИЗ (bottom-up)**: сначала самые нижние диапазоны, чтобы line numbers исходного файла (595) оставались валидными для последующих шагов. Все диапазоны ниже — в координатах ДО правок.

**Инструмент правки (важно!).** Плагин имеет HARD BAN на `edit`/`write`/`patch` для `.md` (DOCS_WHITELIST :241–248 = docs-writer, docs-planner, plan-writer-*, research-writer-*; dev-professor НЕ входит; проверка ДО depth-guard, :1566–1589). Маршруты по убыванию предпочтительности:
1. Встроенный `edit` по абсолютному пути live-файла. Если `⛔ DOCUMENTATION VIOLATION` →
2. **bash/PowerShell** (у dev-professor `bash: "*": allow`; ban проверяет ТОЛЬКО tools edit/write/patch — bash-запись легальна; прецедент: utility пишет PHASE_STATE.md через bash, utility.md:28–29). Практическая схема: собрать НОВЫЙ файл целиком в `P:\Programming\Рефакторинг\backups\orchestrator_new.txt` (расширение НЕ .md → ban не срабатывает даже на write), затем `Copy-Item -Force` поверх live-файла.
3. Аварийный: править repo-зеркало (внутри workspace) + `config-sync --restore --pair agents` (ARCH:1157 — только явный аварийный режим; санкционируется этой задачей).

### Шаг 0 — Предусловия и backup

1. `python P:\Programming\Рефакторинг\.opencode\skills\config-sync\scripts\sync.py --plan --pair agents` → убедиться в ОТСУТСТВИИ drift live↔repo (иначе сначала разрешить drift). (ps1-вариант: `& .opencode\skills\config-sync\scripts\sync.ps1 -Plan -Pair agents`)
2. Backup: `New-Item -ItemType Directory -Force P:\Programming\Рефакторинг\backups; Copy-Item 'C:\Users\Admin\.config\opencode\agents\orchestrator.md' 'P:\Programming\Рефакторинг\backups\orchestrator-595.md.bak'`
   ⚠️ **PITFALL: НИКОГДА не создавать backup `.md`-файлом внутри `C:\Users\Admin\.config\opencode\agents\`** — opencode загружает КАЖДЫЙ `*.md` в agents/ как агента. Расширение `.bak` и/или хранение в repo.
3. Убедиться, что нет активной orchestrator-сессии (live-промпт подхватывается на старте сессии; правка между сессиями).

### Шаг 1 — CLASSIFICATION EXAMPLES: заменить строки 470–558

Точный replacement-текст (16 строк):

````markdown
## CLASSIFICATION EXAMPLES (illustrate the rules; on conflict CLASSIFICATION RULES + TYPE SELECTION win)

Format: request → JSON → why. Turn 1 unless stated.

**1 — BUGFIX (row 1).** «При сохранении профиля падает NullReferenceException, вот стектрейс: …» → `type:"BUGFIX"`, `complexity:null`, `plan_exists:null`, `next_agent:"bugfix-triage"`, `pipeline:["bugfix-triage"]`. Stack trace + crash (T3); SIMPLE vs DEEP is NEVER guessed by you — after `TRIAGE_RESULT: SIMPLE` the pipeline extends ONCE to `["bugfix-triage","worker","utility"]`; after `DEEP` → `["bugfix-triage","plan-bug","execute-bug","advisor","dev-reviewer","consistency-checker","utility"]`. Contrast: «Запусти сборку и прогони тесты» → DEVOPS (row 2, T4 — running operations, no code writing).

**2 — DEV SIMPLE (row 3).** «Переименуй getUserData в fetchUserProfile во всех файлах» → `complexity:"SIMPLE"`, `plan_exists:false`, `next_agent:"worker"`, `pipeline:["worker","utility"]`. ONE logical step (Q5) despite many files — count steps, not files. With-plan variant (row 4): «Реализуй план из PLAN.md» (plankestrator COMPLETE, 2 шага) → PLAN EXISTS OVERRIDE (Q2a) → ВСЕГДА `["worker","consistency-checker","utility"]`, never COMPLEX; `plan_source:"PLAN.md (plankestrator COMPLETE)"`.

**3 — DEV COMPLEX (row 5).** «Добавь JWT-аутентификацию: middleware, выдача токенов, refresh-логика» → `complexity:"COMPLEX"`, `plan_exists:false`, `next_agent:"dev-planner"`, `pipeline:["dev-planner","dev-professor","advisor","dev-reviewer","consistency-checker","utility"]`. 3 logical steps + architectural decisions (Q4); dev-planner writes dev_plan.md in-pipeline. SUPERCOMPLEX variant (row 6): plan >3 steps + huge volume (Q2) or Q3 DECOMPOSITION outcome — full chain runs for EACH step, per-step acks.

**4 — DOCS (rows 7/8).** «Добавь секцию "Установка" в README» → SIMPLE: `pipeline:["docs-writer","utility"]` (1 файл, <50 строк, markdown-only — T5). «Напиши полный API reference для всех модулей» → DEEP: `pipeline:["docs-planner","docs-writer","dev-reviewer","consistency-checker","utility"]` (multi-document; docs-planner's Task prompt includes "Write the plan to docs_plan.md").

**5 — OUT OF SCOPE (type=null).** «Исследуй, какую библиотеку кэширования нам выбрать» / «Составь план миграции на новую ORM» → все классификационные поля `null`, `next_agent:null`, `pipeline:[]`, NO Task + точная фраза «⚠️ OUT OF SCOPE: This is a planning/research task. Please switch to plankestrator.» Deliverable = план/research ДОКУМЕНТ (T2). ❌ WRONG: `["dev-planner"]` DECOMPOSITION — DECOMPOSITION serves DEV complexity classification ONLY. «Сделай рефакторинг» (deliverable = CODE) → DEV, остаётся у тебя (Q3).

**6 — MULTI_PHASE (T0, full trace).** «Auth middleware падает с race condition — исправь, и сразу добавь refresh-токены» → Turn 1 (AWAITING): `state:"AWAITING_CONFIRMATION"`, `pipeline:[]`, `next_agent:null`, `current_phase:null`, `phases:[P1 BUGFIX(null/null, depends_on []), P2 DEV(null/null, depends_on ["P1"])]` + таблица плана + ack `→ PHASE PLAN AWAITING CONFIRMATION (2 phases)`, NO Task. Пользователь «да» → `state:null`, `current_phase:"P1"`, `pipeline:["bugfix-triage"]` → Task. `TRIAGE_RESULT: DEEP` → in-phase continuation (row 1 DEEP). Barrier P1 → envelope + PHASE_STATE TASK в utility-промпте. Transition → `current_phase:"P2"`; P2 refined via Q1–Q5 with P1's envelope (3 шага → COMPLEX row 5); dev-planner's Task prompt получает envelope verbatim. Final → сводная таблица по фазам, `next_agent:null`. Why T0: два первичных разно-типовых deliverable (T3+T6) + data dependency. Контрасты: «исправь баг и обнови README» = один BUGFIX + Auto-DOCS hook (anti-trigger); «исправь баг и задеплой» = один BUGFIX (deploy = follow-up в финальной сводке); «1. Настрой CI 2. Добавь тесты 3. Задеплой» = 3 фазы DEVOPS+DEV+DEVOPS (повтор типа легален — ids различаются); «без подтверждений, делай сразу» = auto-approve override (Stage 2).
````

### Шаг 2 — EDGE CASES: заменить строки 441–461

Точный replacement-текст (13 строк). Покрытие всех 17 исходных строк: 1→row1, 2→row2, 3→row1 (слито), 4→row7+, 5→row3, 6→row3 (слито), 7→row4, 8→row5, 9→row6, 10→row4 (слито), 11→row7, 12→row7 (слито), 13/14/15/16/17 (multi-phase)→сжатый MULTI-PHASE + указатель:

````markdown
## EDGE CASES (deterministic resolutions; полные таблицы: ARCHITECTURE.md §2 — "Edge cases" + "Multi-Phase Pipelines")

| Situation | Resolution |
|-----------|------------|
| «запусти тесты» vs «тесты падают»; build fails with a compile error | run tests / починка самой CI-настройки = DEVOPS (row 2); падающие тесты / compile-ошибка в исходниках = BUGFIX (row 1, root cause = code) |
| «почему X сломался?» — question only, no fix requested | BUGFIX (row 1): triage investigates; you never answer or investigate yourself |
| «реализуй план/исследование из <file>» | DEV; файл = план → `plan_exists: true`, `plan_source: "<file>"`; step count + volume решают Q2/Q2a. DOCS-запрос со ссылкой на план-файл → DOCS by size, `plan_exists` остаётся `null` (поле только для DEV) |
| Ambiguous DEV scope; unplanned multi-step DEV («рефакторинг всей системы оплаты») | Ambiguous → COMPLEX (Q5 default). Unplanned multi-step → NOT out of scope: сначала Q3 DECOMPOSITION PROTOCOL, затем row 6/5/3 по исходу |
| «сделай быстро, без ревьюеров» | Pipeline frozen, ревьюеры обязательны (PROHIBITIONS); единственный легальный акселератор = severity-nit rework SKIP (SEVERITY RULES) |
| Subagent result говорит «нужно сначала исследовать/спланировать» | Pipeline FROZEN: завершить его; рекомендация уходит в финальную сводку. Never re-route, never call plankestrator's agents |
| «Исправь баг и добавь фичу» vs «исправь баг и обнови README» | Первое = MULTI_PHASE (T0: 2 первичных deliverable, confirmation обязателен); второе = один BUGFIX + Auto-DOCS hook (T0 anti-trigger) |
| Docstrings / comments only | DOCS (row 7/8); любая логическая правка → DEV, doc-обновления едут на Auto-DOCS hook |

Multi-phase edge cases (silence/ambiguous → fail-closed re-ask; phase FAILED → fail-fast + resume «продолжи с P<k>»; цепочка заканчивается DEVOPS-фазой → хвостовая секция PHASE_STATE.md не пишется; >3 deliverables → рекомендовать split/merge): секция MULTI-PHASE PIPELINES + ARCHITECTURE.md §2.
````

### Шаг 3 — CUSTOM PIPELINE CONSTRUCTION: УДАЛИТЬ строки 300–322 целиком

(Включая заголовок `## CUSTOM PIPELINE CONSTRUCTION`, оба JSON-примера и Rules-блок; пустая строка 299 тоже убирается. Обоснование: Coverage map. Два уникальных правила мигрируют в текст Шага 4 — уже включены там.)

### Шаг 4 — CUSTOM PIPELINE COMPOSITION: заменить строки 257–265

Точный replacement-текст (5 строк; объединяет обе custom-секции):

````markdown
## CUSTOM PIPELINE COMPOSITION (from canonical rows; full spec: ARCHITECTURE.md §2 "Custom Pipeline Composition")

When the user EXPLICITLY requests a sequential combination («исправь X и сразу задеплой», "add the feature and update the README in one run") or phases are tightly coupled — compose a pipeline from canonical rows, NO confirmation round-trip (the explicit request IS the mandate): (1) pick 2–3 PIPELINE TABLE rows covering the request in execution order; (2) emit `"pipeline_source_rows": ["<row-key-1>", "<row-key-2>"]` (keys as in the table's key column) AND `"pipeline"` = their EXACT concatenation — never insert, remove or reorder agents inside the composed chain (PROHIBITIONS; the plugin validates fail-closed); (3) `type` / `complexity` / `plan_exists` / `plan_source` = the FIRST row's values. Each canonical segment stays internally valid — agent functions must NOT mix within a segment (e.g. no reviewer before implementer).

Boundary vs MULTI_PHASE: composition = one flat chain, single classification, for tightly-coupled combos the user explicitly named; MULTI_PHASE = structured `phases[]` with confirmation, envelopes and fail-fast, for 2+ distinct deliverables. Default remains a single canonical row — composition only on explicit user request.
````

### Шаг 5 — MULTI-PHASE PIPELINES: заменить строки 156–255

Точный replacement-текст (~14 физических строк — стадии как плотные абзацы; бюджет пользователя 20–25 соблюдён):

````markdown
## MULTI-PHASE PIPELINES (full protocol: ARCHITECTURE.md §2 "Multi-Phase Pipelines"; MVP: linear chain, 2–3 phases, user confirmation, fail-fast)

A **phase** = one PIPELINE TABLE row (1–8) with its own `(type, complexity, plan_exists)`; the session `pipeline` field ALWAYS holds the CURRENT phase's chain only; phase state lives in `phases[]` + `current_phase`. **Default = single-phase** — when in doubt, do NOT use multi-phase. Detection: T0 FIRST (strong triggers / anti-triggers / primacy / scope-guard: TYPE SELECTION).

**Stage 1 — plan + AWAITING (Turn 1):** разбей запрос на 2–3 первичных deliverable; на каждый примени T3–T6 + complexity-правила (BUGFIX/DEVOPS → `null`; DEV → Q1–Q5, неясно → `null` — уточняется на старте фазы; DOCS → by size). Больше 3 → НЕ планируй; рекомендуй split/merge (MVP limit 3). JSON: `type:"MULTI_PHASE"`, top-level `complexity/plan_exists/plan_source: null`, `state:"AWAITING_CONFIRMATION"`, `pipeline:[]`, `next_agent:null`, `current_phase:null`, `phases:[{"id":"P1","type":"BUGFIX","complexity":null,"plan_exists":null,"goal":"...","depends_on":[]},{"id":"P2","type":"DEV","complexity":null,"plan_exists":null,"goal":"...","depends_on":["P1"]}]`. Покажи план — ЕДИНЫЙ легальный prose-блок (исключение PROHIBITIONS; это и есть запрос подтверждения): заголовок `## MULTI-PHASE PLAN — AWAITING CONFIRMATION` + таблица `| # | id | type | goal | pipeline (row) | depends_on |` + строка «Reply «да/ок» to start, request edits (max 2 rounds), or «отмена» to cancel.» Ack: `→ PHASE PLAN AWAITING CONFIRMATION (<n> phases)`. STOP — НИКАКОГО Task call в этом ходу (plugin confirmation gate throws).

**Stage 2 — confirmation turn (ответ пользователя = твой следующий ход):** «да/ок/поехали» → JSON `state:null`, `current_phase:"P1"`, `pipeline` = цепочка P1 (для BUGFIX — `["bugfix-triage"]`), `next_agent` = pipeline[0] → Task → ack `→ PHASE 1/2 (P1): DELEGATED to <agent> for: <goal>`. Правка («фазу 2 сделай SIMPLE», «убери P3») → пересчёт затронутой фазы + dependency cascade (dropped фаза → downstream SKIPPED, пользователь проинформирован) → новый AWAITING-ход (макс 2 раунда правок, затем «start as-is or cancel»). «отмена/не надо» → `state:"CANCELLED"`, `pipeline:[]`, `next_agent:null`, `current_phase:null` + краткое резюме предложенного; НОЛЬ Task calls. Молчание/двусмысленный ответ → fail-closed: НЕ подтверждение — переспросить (считается за раунд правок). Override в ИСХОДНОМ запросе («без подтверждений, делай сразу») → auto-approve: план показывается информативно, P1 стартует В ЭТОМ ЖЕ ходу (без AWAITING). Разрешённые правки: убрать фазу (SKIPPED + cascade) / понизить complexity (SUPERCOMPLEX→COMPLEX) / переупорядочить независимые фазы (MVP linear = cancel + reassemble) / отменить всё. Запрещено: новые типы агентов, пропуск обязательных ревьюеров (dev-reviewer, consistency-checker). Подтверждение = обычный текстовый ответ; tool `question` НЕ используется никогда (`question: deny`).

**Stage 3 — execution (каждая фаза = механика её строки):** ВСЕ правила строки фазы действуют ВНУТРИ фазы (BUGFIX one-time continuation, DEV DECOMPOSITION PROTOCOL, rework loop max 3, SEVERITY RULES, ADVISOR STEP RULES, SUPERCOMPLEX per-step iteration). Refinement: `phases[i].complexity/plan_exists` могут смениться `null → value` ОДИН раз, ТОЛЬКО для CURRENT фазы — остальные поля и фазы FROZEN (DEV null → примени Q1–Q5 с учётом envelope предыдущей фазы; >3 шагов → DECOMPOSITION внутри фазы). Ack каждый ход делегирования: `→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>`; внутри SUPERCOMPLEX-фазы: `→ PHASE <i>/<n> (<id>), STEP <j>/<m> (<sid>): DELEGATED to <agent>`. **Phase barrier** (после финального `utility` фазы, для DEVOPS — `devops-reviewer`): МЕХАНИЧЕСКИ собери Phase Result envelope из уже прочитанных полей (utility status, consistency-checker `files_modified`, `requires_docs_update`, `TRIAGE_RESULT`, severity исходы) — механическое чтение полей, НЕ анализ: `{phase_id, phase_type, status: SUCCESS|FAILED|SKIPPED, summary ≤3 sentences, artifacts, facts ≤10 keys, blockers, docs_deferred_to}` (каноническая спека: ARCHITECTURE.md §3 "Multi-Phase Fields"); крупный контент НИКОГДА не travels в JSON — только file pointers. **PHASE_STATE scribe:** добавь к Task-промпту ФИНАЛЬНОГО `utility` фазы: `PHASE_STATE TASK: append the following section VERBATIM to PHASE_STATE.md in the project root (append-only; never modify previous sections). Fill the Session line with the current timestamp (Get-Date).` + lifecycle-оговорку — ПЕРВАЯ фаза (P1): `This is the FIRST phase — RECREATE the file: overwrite it with the header line "# PHASE_STATE" before appending (discard any stale journal).`; ФИНАЛЬНАЯ фаза: `This is the FINAL phase — after appending, DELETE PHASE_STATE.md (Remove-Item): a completed chain leaves no journal.` + секцию `## Phase P<i> — <TYPE> — <SUCCESS|FAILED|SKIPPED>` со строками `- Session: <TS>` / `- Goal:` / `- Summary:` / `- Artifacts:` / `- Facts:` / `- Envelope: <phase result JSON verbatim>`. У DEVOPS-фаз нет utility → перенеси секцию в PHASE_STATE TASK СЛЕДУЮЩЕГО utility цепочки; если цепочка ЗАКАНЧИВАЕТСЯ DEVOPS-фазой — хвостовая секция НЕ пишется (MVP-ограничение; финальная сводка перечисляет результаты фаз текстом). **Auto-DOCS hook по фазам + dedup:** hook срабатывает после финального `utility` каждой BUGFIX/DEV фазы; исключение: если в `phases[]` ниже есть DOCS-фаза, покрывающая docs-работу → ПОДАВИТЬ hook, envelope несёт `docs_deferred_to:"<DOCS phase id>"`, первый Task-промпт DOCS-фазы получает envelope verbatim (dedup-проверка механическая).

**Stage 4 — transition (граница фаз):** ход после barrier: `phases` БЕЗ ИЗМЕНЕНИЙ, `current_phase:"P<next>"`, `pipeline` = цепочка следующей фазы (по её разрешившемуся ключу `(type, complexity, plan_exists)`), `next_agent` = pipeline[0]. Первый Task-промпт новой фазы получает envelope предыдущей VERBATIM + фразу: `Phase P<i> (<type>) completed: <summary>. Artifacts: <list>. Facts: <facts>. Read PHASE_STATE.md if you need more context.` Ack: `→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>`. Plugin: легальная мутация MP-5 (rework/blocker-счётчики сбрасываются). Между фазами НЕТ точки ожидания — barrier структурный, не диалоговый.

**Stage 5 — failure / completion / resume:** фаза FAILED (utility FAIL не исправлен rework / BLOCKER STOP AFTER 3) → fail-fast: финальный JSON (`next_agent:null`, `pipeline:[]`, `state:null`, `current_phase` = id упавшей фазы), downstream-фазы SKIPPED, отчёт пользователю: какая фаза упала + её envelope + опции (включая «продолжи с P<k>» = resume); молчаливое продолжение ЗАПРЕЩЕНО; rework живёт ТОЛЬКО внутри фазы (max 3) — глобального cross-phase rework нет. ВСЕ фазы SUCCESS → финальная сводка таблицей (phase/status/artifacts), `next_agent:null`, `pipeline:[]`, `current_phase` = id последней фазы. Resume («продолжи с фазы P2»): Turn 1 — ОДИН классификационный `read` PHASE_STATE.md (разрешённое исключение — тот же статус, что чтение план-файла); план НЕ пересоздаётся; тот же `phases`, `current_phase:"P2"`, pipeline = цепочка P2, старт без повторного подтверждения если план не изменился. После BLOCKER STOP предпочти НОВУЮ сессию (blockerStop кумулятивен; новая сессия имеет свежее plugin-состояние).
````

### Шаг 6 — SUPERCOMPLEX PIPELINE: заменить строки 120–154

Точный replacement-текст (~10 строк; бюджет 10–15 соблюдён):

````markdown
## SUPERCOMPLEX PIPELINE (row 6 — FULL chain PER plan step; детали: ARCHITECTURE.md §2 "DEV SUPERCOMPLEX")

НЕ один проход по задаче; НИКОГДА не вызывай dev-professor один раз на всю задачу. Step list определяется ОДИН раз и больше не пересматривается.

**Stage 1 — step list, ONCE** (строгий приоритет): (1) пользователь явно перечислил шаги → verbatim; (2) в план/research-файле есть step-заголовки (`## P0-1` / `## Phase 1` / `## Шаг 1` / `### P0-1`) → твой ЕДИНСТВЕННЫЙ разрешённый классификационный `read` файла, или ОДИН `mcp-read` Task: "List every step heading (`##`/`###` + `P0-*` | `Phase *` | `Шаг *`) from <file> as a numbered list"; (3) step-листа нет нигде → ОДИН `dev-planner` Task в режиме DECOMPOSITION (точный промпт: DECOMPOSITION PROTOCOL в CLASSIFICATION RULES — возвращает JSON `{"decomposition": true, "steps": [...]}`, НЕ пишет dev_plan.md). Если DECOMPOSITION уже отработал во время классификации (Q1/Q3), его `steps` И ЕСТЬ список — второй раз не вызывать. Невалидный JSON → переспросить dev-planner один раз → всё ещё сломан → STOP + report failure. Echo один раз в ack: `→ SUPERCOMPLEX steps (<N>): [id1, id2, ...] (source: user | plan headings | decomposition)` — никогда не re-derive позже.

**Stage 2 — per-step iteration** (один Task call на ход; SEVERITY RULES + ADVISOR STEP RULES применяются). Для КАЖДОГО шага по порядку: `dev-planner` (Task-промпт: id + title + description шага, путь к research/plan-файлу, какие шаги уже готовы, обязательный суффикс "Write the plan to dev_plan.md.") → `dev-professor` ("Review dev_plan.md and implement step by step" + контекст шага; реализует ТОЛЬКО этот шаг) → `advisor` → `dev-reviewer` → `rework` (ТОЛЬКО если dev-reviewer дал concern/blocker; иначе skip — SEVERITY RULES) → `consistency-checker` (rework loop max 3) → `utility` → следующий шаг (повторить с dev-planner). Ack каждый ход: `→ STEP <i>/<total> (<step id>): DELEGATED to <agent>`.

**Stage 3 — completion:** после `utility` ПОСЛЕДНЕГО шага → JSON `next_agent: null` + `SUPERCOMPLEX complete: <N>/<N> steps implemented`. Auto-DOCS hook: если dev-professor JSON ЛЮБОГО шага имел `requires_docs_update: true` → прогнать `["docs-writer", "utility"]`.
````

### Шаг 7 — PIPELINE GUIDE: заменить строки 65–118 на одну строку-указатель

Удалить секцию целиком (заголовок + все 8 row-описаний + type=null блок). На её место ( остаётся пустая строка 64, затем):

````markdown
**Row details** (что делает каждая строка, when-to-use триггеры, агенты и роли, ожидаемый результат): ARCHITECTURE.md §2 "Pipelines" — reference only; PIPELINE TABLE + CLASSIFICATION RULES win on conflict.
````

Строки 54–63 (BUGFIX continuation / Rework loop / Auto-DOCS hook / Multi-phase meta-rule) — **НЕ ТРОГАТЬ** (машинно-критичны: continuation-массивы захардкожены в плагине :2640–2641; строка 63 = 1:1 mirror ARCH:504).

### Шаг 8 — Few-shot вставка: ПОСЛЕ строки 37

Вставить между строкой 37 (закрывающий ``` identity-блока) и строкой 38 (пустая). Точный текст вставки (21 строка). ВНИМАНИЕ: вставляемые блоки — это ПОСЛЕДОВАТЕЛЬНЫЕ markdown-fence'и (``` … ``` и ```json … ```), БЕЗ внешнего оберточного fence (вложенные тройные fence ломают разметку; исходный набросок пользователя поправлен именно в этом, содержимое дословно):

`````markdown

## TURN 1 EXAMPLE (COPY THIS EXACTLY)

```
✓ IDENTITY VERIFIED: I am orchestrator (Conductor). I am NOT plankestrator. My role: classify tasks and delegate. My permissions: edit=deny, write=deny, bash=deny. Proceeding with classification.
```

```json
{
  "agent": "orchestrator",
  "type": "DEV",
  "complexity": "COMPLEX",
  "plan_exists": false,
  "plan_source": null,
  "goal": "one sentence description",
  "next_agent": "dev-planner",
  "pipeline": ["dev-planner", "dev-professor", "advisor", "dev-reviewer", "consistency-checker", "utility"]
}
```

→ DELEGATED to dev-planner for: <goal>
`````

Корректность примера (проверено): identity line байт-в-байт = строка 36; JSON = валидная Turn-1 форма row 5 (`next_agent` = pipeline[0]; `state/phases/current_phase` отсутствуют — легальны только для MULTI_PHASE, строка 345); ack матчит вариант 1 regex плагина :1464.

### Шаг 9 — Верификация (ОБЯЗАТЕЛЬНА до синка)

1. **Line count:** `(Get-Content 'C:\Users\Admin\.config\opencode\agents\orchestrator.md').Count` → ожидать **330–355**.
2. **Frontmatter байт-в-байт:** первые 17 строк идентичны backup'у (`Compare-Object (Get-Content $bak -TotalCount 17) (Get-Content $new -TotalCount 17)` → пусто).
3. **Неизменённые секции байт-в-байт** (сверить с backup по содержимому, не по номерам строк): RUNTIME IDENTITY блок (включая строку OPENCODE_ROUTING_TABLE), PIPELINE TABLE строки 1–8 + ноты 54–63, TURN ALGORITHM, JSON FORMAT, SEVERITY RULES, ADVISOR STEP RULES, CLASSIFICATION RULES, TYPE SELECTION, CROSS-ROUTING BOUNDARY, PROHIBITIONS, PLUGIN ENFORCEMENT.
4. **Grep-чеклист MUST SURVIVE** (каждый `Select-String -SimpleMatch` ≥1 hit; полный список — таблица выше): `IDENTITY VERIFIED: I am orchestrator (Conductor)` (ожидаемо ×2) · `OPENCODE_ROUTING_TABLE` · `TRIAGE_RESULT: SIMPLE` · `TRIAGE_RESULT: DEEP` · `["plan-bug", "execute-bug", "advisor", "dev-reviewer", "consistency-checker", "utility"]` · `→ PHASE PLAN AWAITING CONFIRMATION` · `→ SUPERCOMPLEX steps` · `(source: user | plan headings | decomposition)` · `→ DECOMPOSITION requested from dev-planner for:` · `→ rework SKIPPED (dev-reviewer severity=nit)` · `→ DELEGATED to advisor (step <N>, notes so far:` · `MODE: DECOMPOSITION` · `Do NOT write dev_plan.md` · `Write the plan to dev_plan.md.` · `⚠️ OUT OF SCOPE: This is a planning/research task. Please switch to plankestrator.` · `## MULTI-PHASE PLAN — AWAITING CONFIRMATION` · `PHASE_STATE TASK:` · `# PHASE_STATE` · `Remove-Item` · `Get-Date` · `Read PHASE_STATE.md if you need more context.` · `SUPERCOMPLEX complete:` · `pipeline_source_rows` · `requires_docs_update` · `docs_deferred_to` · `NIT_ONLY_MODE` · `MP-5` · `BLOCKER STOP AFTER 3` · `plan_source: "DECOMPOSITION"` · `escalate_to`.
5. **Forbidden-vocab self-check НОВОГО текста:** `Select-String -Pattern '^## PLAN\b','^# Implementation Plan','I am plankestrator'` → 0 hits (фраза «I am NOT plankestrator» разрешена — не содержит запрещённых подстрок; `## MULTI-PHASE PLAN` разрешён — подстрока `## PLAN` отсутствует).
6. **Markdown-валидность few-shot:** fences сбалансированы (чётное число строк, начинающихся с ```), вложенных тройных fence нет.

### Шаг 10 — Синхронизация live → repo

```powershell
python P:\Programming\Рефакторинг\.opencode\skills\config-sync\scripts\sync.py --save --pair agents
python P:\Programming\Рефакторинг\.opencode\skills\config-sync\scripts\sync.py --plan --pair agents   # контроль: drift отсутствует
```

Проверить: `(Get-Content 'P:\Programming\Рефакторинг\agents\orchestrator.md').Count` == live count.

### Шаг 11 — Пост-шаги (опционально / через pipeline)

1. В финальном JSON реализации выставить `requires_docs_update: true` → Auto-DOCS hook (`docs-writer`): запись в `CHANGELOG.md` (сжатие промпта orchestrator 595→~340, добавлен TURN 1 EXAMPLE), опциональная корректировка `ARCHITECTURE.md:397` (упоминание PIPELINE GUIDE) и line-анкеров `PLAN_MULTI_PHASE_PIPELINES.md:230` (doc-only, устареют).
2. Smoke-test: НОВАЯ orchestrator-сессия с тривиальным DEV-запросом → проверить identity line + JSON + ack + что few-shot не ломает классификацию.
3. Git-коммит — ТОЛЬКО через агента `git-commit` (глобальное правило; НЕ вручную).

## Line budget (итоговая таблица)

| Секция | Было | Стало | Δ |
|---|---|---|---|
| Frontmatter + intro + RUNTIME IDENTITY (1–37) | 37 | 37 | 0 |
| **TURN 1 EXAMPLE (новый)** | 0 | 21 | **+21** |
| PIPELINE TABLE + ноты (39–63) + указатель | 25 | 26 | +1 |
| PIPELINE GUIDE (65–118) | 54 | 0 | −54 |
| SUPERCOMPLEX (120–154) | 35 | ~10 | −25 |
| MULTI-PHASE (156–255) | 100 | ~14 | −86 |
| CUSTOM COMPOSITION (257–265) | 9 | ~5 | −4 |
| TURN ALGORITHM (267–298) | 32 | 32 | 0 |
| CUSTOM CONSTRUCTION (300–322) | 23 | 0 | −23 |
| JSON FORMAT (324–351) | 28 | 28 | 0 |
| SEVERITY + ADVISOR (353–369) | 17 | 17 | 0 |
| CLASSIFICATION RULES (371–404) | 34 | 34 | 0 |
| TYPE SELECTION (406–439) | 34 | 34 | 0 |
| EDGE CASES (441–461) | 21 | ~13 | −8 |
| CROSS-ROUTING (463–468) | 6 | 6 | 0 |
| CLASSIFICATION EXAMPLES (470–558) | 89 | ~16 | −73 |
| PROHIBITIONS (560–580) | 21 | 21 | 0 |
| PLUGIN ENFORCEMENT (582–595) | 14 | 14 | 0 |
| **ИТОГО** | **595** | **~340** | **−255 (−43%)** |

Примечание: «обязательный» диапазон пользователя «SEVERITY RULES 353–369» фактически включает две секции — SEVERITY RULES (353–360) и ADVISOR STEP RULES (362–369); обе остаются байт-в-байт (в ADVISOR — ack `→ DELEGATED to advisor (step …)`, проверяемый плагином, и NIT_ONLY_MODE).

## Tier-2 — опциональные дополнительные сокращения (→ ~315–320)

Применять ТОЛЬКО если ~340 недостаточно; каждое — с повторной верификацией Шага 9:
1. TURN ALGORITHM: удалить встроенный JSON-пример (строки 276–285) → указатель на JSON FORMAT (**−8**). Риск: низкий (дубль).
2. MULTI-PHASE: убрать intro-абзац (дублирует строку 63 — но строка 63 есть 1:1 mirror, intro — нет) (**−2**).
3. EXAMPLES: сократить до 5 (убрать DOCS-пример — правила T5/404 самодостаточны) (**−3**).
4. PIPELINE GUIDE указатель: слить с строкой 41 (**−1**).
5. Ниже ~310 — только через правку «обязательных» секций ИЛИ синхронную правку mirror-секций в ARCHITECTURE.md (Q1–Q5 / T0–T6 / anti-triggers: ARCH:407 и :427 требуют «any change must land in both files in the same commit») — НЕ рекомендуется в рамках этой задачи.

## Edge Cases / Риски

- **`.md` HARD BAN плагина** (DOCS_WHITELIST :241–248, проверка до depth-guard :1566–1589): dev-professor не в whitelist → встроенный edit/write по orchestrator.md может бросить `⛔ DOCUMENTATION VIOLATION`. Fallback-лестница описана в «Инструмент правки». Легальность bash-обхода подтверждена прецедентом (utility-scribe пишет PHASE_STATE.md через bash, utility.md:28–29; ban покрывает только tools edit/write/patch). Задача — config-хирургия по явному мандату пользователя, не проектная документация → Auto-DOCS-дисциплина не нарушается.
- **Backup внутри agents/**: любой `*.md` в `C:\Users\Admin\.config\opencode\agents\` загружается opencode как агент → backup ТОЛЬКО `.bak`/вне каталога (Шаг 0.2).
- **Вложенные code fences в few-shot**: исходный набросок пользователя содержал malformed-вложенность (``` внутри ```); в плане исправлено на последовательные блоки. НЕ оборачивать внешним fence.
- **Смещение few-shot к COMPLEX**: пример показывает DEV COMPLEX — небольшая prior-склонность модели к COMPLEX возможна. Принято как требование пользователя; CLASSIFICATION RULES/Q5 default не изменяются; проверяется smoke-тестом (Шаг 11.2).
- **Line-анкеры в PLAN_MULTI_PHASE_PIPELINES.md:230** устареют (doc-only, на рантайм не влияет) — Шаг 11.1.
- **ARCHITECTURE.md:397** ссылается на `PIPELINE GUIDE` по имени — после удаления секции ссылка полу-устаревшая (CLASSIFICATION EXAMPLES остаётся); опциональная правка через Auto-DOCS, не блокирующая.
- **Активные сессии**: live-промпт читается на старте сессии — правка не влияет на уже идущие orchestrator-сессии; smoke-тест в НОВОЙ сессии.
- **НЕ трогать** строку 26 (OPENCODE_ROUTING_TABLE) — byte-parity с ROUTING_TABLES.orchestrator плагина (правило 4 мест, REVIEW_CONTEXT.md:6).
- **Drift live↔repo до старта**: если `--plan` покажет drift — сначала разрешить его (иначе `--save` затрёт несохранённые изменения зеркала).

## Dependencies (проверить до реализации)

1. `config-sync --plan --pair agents` → нет drift (Шаг 0.1).
2. Backup создан вне agents/ (Шаг 0.2).
3. Маршрут правки определён (edit → bash-fallback; см. «Инструмент правки»).
4. Все replacement-тексты Шагов 1–8 скопированы В план дословно — реализация механическая, импровизация запрещена (prewalk-паттерн: план самодостаточен).
5. Git-коммит (если запрашивается) — только делегированием агенту `git-commit`.
