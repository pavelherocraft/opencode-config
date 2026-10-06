# PLAN: Multi-Phase Pipelines (MVP) — с фазой подтверждения от пользователя

**Дата:** 2026-10-01
**Статус:** Plan (готов к ревью; источник — `RESEARCH_MULTI_PHASE_PIPELINES.md`, APPROVED с правками reviewer)
**Scope:** MVP Stage 1 — линейная цепочка 2–3 фазы, композиция существующих строк PIPELINE TABLE, ноль новых агентов
**Out of scope:** параллельные фазы, DAG с явным `depends_on`, вложенные multi-phase, `continue_on_error`, лимит 4 фазы (Stage 2/3 — `RESEARCH_MULTI_PHASE_PIPELINES.md` §9.1)

---

## Executive Summary

### Цель

Дать оркестратору возможность выполнять **последовательность фаз** (каждая фаза = существующая строка 1–8 PIPELINE TABLE) для одного запроса с **обязательным подтверждением плана фаз пользователем** перед стартом. Сейчас mixed-intent запросы («исправь баг и добавь фичу») теряют вторичные deliverable: правило «NEVER split one request into two pipelines» (`ARCHITECTURE.md:438`, `agents/orchestrator.md:250`) допускает только Auto-DOCS hook и follow-up-упоминание в summary.

### Архитектура решения (сводка)

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

### Ключевые решения (7 из исследования + 3 резолюции плана)

| # | Решение | Выбор | Источник |
|---|---------|-------|----------|
| 1 | Модель фаз | Композиция существующих строк 1–8; `phases` — массив 2–3 (MVP), каждая фаза резолвится в строку по своим `(type, complexity, plan_exists)` | Research §9.2-1 |
| 2 | Контекст | Phase Result JSON (конверт, ≤3 предложений summary, ≤10 фактов) + `PHASE_STATE.md` («pointer, not transcript») + verbatim-передача в Task prompt | Research §9.2-2, §4 |
| 3 | Ошибки | Fail-fast default: фаза FAILED → цепочка стоп, downstream SKIPPED; rework живёт только внутри фазы (max 3) | Research §9.2-3, §4.3 |
| 4 | Подтверждение | Обязательное, через обычный текстовый ответ (`state: "AWAITING_CONFIRMATION"`), НЕ через tool `question` (`question: deny` не нарушается); fail-closed на неоднозначный ответ; explicit override «без подтверждений» = auto-approve | Research §9.2-4, §5 |
| 5 | Триггеры | Новый вопрос T0 перед деревом типов + строгие анти-триггеры; **default = single-phase** | Research §9.2-5, §8 |
| 6 | SUPERCOMPLEX | Фаза, не обёртка; ≤1 SUPERCOMPLEX-фаза на план; вложенность multi-phase запрещена | Research §9.2-6, §3.3 |
| 7 | JSON | `type: "MULTI_PHASE"` + `phases[]` + `current_phase` + `state`; `pipeline` = цепочка ТЕКУЩЕЙ фазы | Research §9.2-7, §7.2 |
| 8 | **Резолюция плана: писец PHASE_STATE.md** | `utility` (bash `Add-Content`, механическое append-verbatim; у utility `edit/write: deny`, но `bash: "*": allow` — `agents/utility.md:6-12`). DEVOPS-фазы (без utility) — хвостовые секции не пишутся в MVP (ограничение, Stage 2) | Этот план, Phase 2.10 |
| 9 | **Резолюция плана: лимит фаз в MVP** | Плагин: `MULTI_PHASE_MAX = 3` (константа; Stage 2 → 4). Промпт: «2–3 фазы». Устраняет разночтение research §7.3 ([2..4]) vs §9.1 (2–3) | Этот план, Phase 3.1 |
| 10 | **Резолюция плана: confirmation gate без события user-role** | Гейт блокирует Task пока `awaitingConfirmation && lastTurnMessageID === awaitingMsgId` (тот же ход). Сброс — при user-сообщении (role-паттерн `workflow-enforcement.ts:1016`) ИЛИ при новом assistant-messageID (turn-based гарантия opencode: primary просыпается только после user-ввода или завершения Task; Task в AWAITING-ходе запрещён → новый messageID ⇒ пользователь ответил) | Этот план, Phase 3.6 |

### Файлы к изменению

| Файл | Расположение | Изменения | Phase |
|------|--------------|-----------|-------|
| `ARCHITECTURE.md` | repo (канон; в live НЕ копируется — §8) | T0, mixed-intent rewording, новая §2-секция Multi-Phase, edge cases, Auto-DOCS dedup, §3 Multi-Phase Fields, gates table, §9 Plugin Hooks | 1 |
| `agents/orchestrator.md` | **live** (`C:\Users\Admin\.config\opencode\`) + repo mirror | Мета-правило PIPELINE TABLE, секция MULTI-PHASE PIPELINES, TURN ALGORITHM, JSON FORMAT, T0 + mixed-intent (зеркало), examples 13–16, PROHIBITIONS, PLUGIN ENFORCEMENT | 2 |
| `agents/utility.md` | live + repo mirror | PHASE_STATE scribe (микро-ответственность) | 2 |
| `plugins/workflow-enforcement.ts` | live + repo mirror | ~10 точечных изменений (VALID_VALUES, validatePipeline, mutation whitelist MP-1…MP-6, provisional fix, confirmation gate, blockerStop reset, ack regex) | 3 |
| `plugins/test-workflow-enforcement.mjs` | repo only (не входит в 5 sync-пар) | Harness-хелперы message.updated + тесты T9–T26 | 4 |
| `CHANGELOG.md` | repo | Entry [Unreleased] → Added | 5 |
| `backup/<date>_multi_phase/` | repo | Снапшот до правок (backup-snapshot skill) | 1 (шаг 1.1) |

**Не изменяются:** `opencode.json` (нет новых агентов/permissions), routing tables (29/10), `agents/plankestrator.md` (multi-phase — только orchestrator), tool lockdown (`question: deny` сохраняется — подтверждение через текст), модель/температура оркестратора.

### Порядок развёртывания (атомарный changeset)

Промпт и плагин функционально неразделимы (новый промпт + старый плагин = fail-closed блокировка MULTI_PHASE-ходов; старый промпт + новый плагин = инертно). Поэтому:

1. Backup (шаг 1.1) → 2. Правки live (Phases 2–3) + repo (Phase 1) → 3. Тесты harness против live-плагина (Phase 4) → 4. `config-sync --save` (live→repo) → 5. Тесты против repo-копии (`WORKFLOW_PLUGIN`) + `integrity-check` → 6. **Один коммит через агента `git-commit`** (mirror-правило `ARCHITECTURE.md:405/:427`: ARCHITECTURE.md + orchestrator.md в одном коммите; push — только по явной просьбе) → 7. Restart opencode (новые сессии) → 8. Пилот S1–S6 (Phase 4.4).

**Трудоёмкость:** ~15–22 ч (детали — «Оценка трудоёмкости» в конце).

---

## Phase 1: Canon Changes (`ARCHITECTURE.md`, repo-only)

> Все правки Phase 1 и Phase 2 (orchestrator.md) коммитятся ВМЕСТЕ (mirror-правило :405, :427). Нумерация строк — от текущего состояния файла (1066 строк); после вставок anchors сдвигаются — сверяться по заголовкам секций.

### Шаг 1.1 — Backup (до любых правок)

Запустить skill `backup-snapshot` (`.opencode/skills/backup-snapshot/`) → `backup/2026-10-01_multi_phase/`: live `agents/orchestrator.md`, `agents/utility.md`, `plugins/workflow-enforcement.ts` + repo `ARCHITECTURE.md`, `CHANGELOG.md`, `plugins/test-workflow-enforcement.mjs`. Прецедент: `backup/2026-09-22_dev_classification/` (`CHANGELOG.md:46`).

### Шаг 1.2 — Переформулировать mixed-intent правило (:438)

**Было (конец):** «…NEVER split one request into two pipelines.»

**Стало (полный текст замены, зеркалится 1:1 в orchestrator.md:250 — шаг 2.5):**

```markdown
**Mixed-intent priority (request spans several types):** BUGFIX > DEV > DOCS > DEVOPS. Pick exactly ONE row — the primary deliverable. Secondary intents are NOT separate pipelines: docs about the code change ride the Auto-DOCS hook (`requires_docs_update`); a deploy after a fix is mentioned in the final completion summary as a follow-up request. NEVER split one request into two pipelines **SILENTLY** — splitting is legal ONLY as a MULTI_PHASE pipeline: explicit `phases[]` in the JSON + user confirmation before execution (T0, "Multi-Phase Pipelines" below). Mixed-intent priority remains the DEFAULT and the fallback for borderline cases: if in doubt — single-phase.
```

Обоснование: research §7.5 строка 1 — прямое противоречие устраняется переформулировкой, а не удалением; default single-phase сохраняется (§8.3).

### Шаг 1.3 — T0 в Type Selection Decision Tree (:425–440)

Добавить строку T0 ПЕРЕД T1 в таблицу (:429–436) — зеркалится в orchestrator.md (шаг 2.5):

```markdown
| T0 | Request contains TWO OR MORE primary deliverables of DIFFERENT types, each independently resolving via T3–T6 to a different row, ALL within orchestrator scope (no plan/research deliverable), phases ≤ 3? | MULTI_PHASE → phase planning + user confirmation ("Multi-Phase Pipelines" section) | T1 |
```

**Scope-guard (обязателен в формулировке T0):** если хоть один deliverable — plan/research документ, T0 = NO (запрос уходит в T1/T2 как сегодня; multi-phase НЕ смешивает primaries — граница с plankestrator не пересекается, research §6.5). Identity/small-talk → T0 NO (нет deliverables).

Сразу под таблицей — блоки триггеров (из research §8.2, канон):

```markdown
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
```

### Шаг 1.4 — Новая §2-секция «Multi-Phase Pipelines»

**Место вставки:** после edge-case таблицы Type Selection (:455), перед `### DEV SIMPLE` (:457). Заголовок: `### Multi-Phase Pipelines (MVP — linear chain, 2–3 phases, user-confirmed)`. Обязательное содержание (канон; операционная версия зеркалится в orchestrator.md — шаг 2.2):

1. **Определение + flow-диаграмма** (research §2.1): фаза = строка 1–8 PIPELINE TABLE со своими `(type, complexity, plan_exists)`; фазы последовательны; план фиксируется до старта и подтверждается пользователем. ASCII-диаграмма из Executive Summary этого плана.
2. **PIPELINE TABLE meta-rule (ни одной новой строки):**

   ```markdown
   **Multi-phase:** `phases` — array of 2–3 phases (MVP); each phase independently resolves to row 1–8 by its own `(type, complexity, plan_exists)`. The session `pipeline` field ALWAYS contains the CURRENT phase's chain only; phase state lives in `phases[]` + `current_phase`. The session pipeline = sequential concatenation of phase chains with phase barriers (barrier = structural: all Task calls of the phase completed; NOT a dialog point — dialog happened at confirmation).
   ```
3. **Классификация фазы** (research §2.3): тип — T1–T6 применительно к подзадаче фазы; сложность — существующие правила (BUGFIX → null + triage; DEV → Q1–Q5; DOCS → по объёму; DEVOPS → null). Двухстадийные протоколы сохраняются ВНУТРИ фазы (BUGFIX continuation; DEV DECOMPOSITION). Multi-phase не меняет T1–T6/Q1–Q5 — применяется k раз.
4. **JSON-расширение** (research §7.2, обратно-совместимое): пример JSON + правила (`pipeline` = текущая фаза; на границе `current_phase` переключается, `pipeline` заменяется — легальная мутация whitelist MP-5).
5. **Confirmation protocol** (research §5.2): Turn 1 AWAITING (`state: "AWAITING_CONFIRMATION"`, `next_agent: null`, `pipeline: []`, Task НЕ вызывается) + человекочитаемая таблица фаз; Turn 2: approve / edit (≤2 раундов правок, дальше старт или отказ) / reject (`state: "CANCELLED"`, ноль Task). Разрешённые правки: (a) отклонить фазу → SKIPPED с каскадом зависимостей, (b) понизить сложность (SUPERCOMPLEX→COMPLEX), (c) переупорядочить независимые фазы (в MVP линейной цепочки — фактически отмена+пересборка), (d) отменить всё. Запрещённые: новые типы агентов, пропуск mandatory-ревьюеров. Тишина/неоднозначность = НЕ-подтверждение (fail-closed). Explicit override: «без подтверждений, делай сразу» → план показывается информативно, исполнение стартует сразу (auto-approve, без AWAITING-хода).
6. **Context passing** (research §4): три канала — Phase Result JSON-конверт (спецификация ниже), `PHASE_STATE.md` (журнал, секция на фазу; писец — `utility`, см. шаг 1.7 и Phase 2.10), verbatim-передача конверта в первый Task prompt следующей фазы + фраза-контекст. Запрет больших объёмов через JSON (XCom-принцип): summary ≤3 предложений, facts ≤10 ключей.

   **Phase Result envelope (канон):**

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
7. **Fail-fast** (research §4.3): фаза FAILED → цепочка останавливается, downstream SKIPPED, отчёт пользователю (какая фаза, конверт, что делать); «тихое продолжение» запрещено; rework max 3 ВНУТРИ фазы — глобального rework между фазами нет; BLOCKER STOP AFTER 3 = FAILED фазы.
8. **SUPERCOMPLEX disambiguation** (research §7.4): SUPERCOMPLEX = итерация по шагам одного DEV-плана внутри ОДНОЙ фазы; multi-phase = итерация по фазам разных типов; ≤1 SUPERCOMPLEX-фаза на план; вложенность запрещена; ack двухуровневый `→ PHASE 1/2 (P1), STEP 3/8 (S-3): DELEGATED to dev-professor`; приоритет классификации: сначала T0/multi-phase, затем Q1–Q5 внутри DEV-фаз.
9. **Edge cases** (таблица — research §6.5 + резолюции плана):

   | Ситуация | Резолюция |
   |----------|-----------|
   | План схлопался в 1 фазу | Деградация в обычный single-phase pipeline БЕЗ подтверждения |
   | Все фазы одного типа | НЕ multi-phase → SUPERCOMPLEX или один пайплайн |
   | Одна из фаз — plan/research deliverable | OUT OF SCOPE целиком (T0 scope-guard) |
   | Auto-DOCS hook внутри multi-phase | Hook срабатывает per-фаза (после BUGFIX/DEV-фазы), как сегодня per-pipeline |
   | `requires_docs_update` от P1, а в плане есть DOCS-фаза P3 | Hook НЕ дублируется (дедупликация по типу): docs-работа уходит в явную DOCS-фазу; конверт P1 несёт `docs_deferred_to: "P3"`, Task prompt DOCS-фазы получает его verbatim |
   | Фаза FAILED, пользователь: «продолжи с P2» | Resume: предпочтительно НОВАЯ сессия (blockerStop кумулятивен — §7.5 research); оркестратор читает `PHASE_STATE.md` (classification read), восстанавливает конверты, стартует с P2 без повторного подтверждения, если план не изменился; плагин: phase transition сбрасывает blockerStop (MP-5) |
   | Пропуск фазы mid-flight | Только отмена остатка цепочки («стоп»); ожидание между фазами НЕ вводится (barrier — структурное свойство, не точка диалога) |
   | Цепочка заканчивается DEVOPS-фазой | Хвостовая секция PHASE_STATE.md не пишется (у DEVOPS нет utility) — MVP-ограничение, финальный summary перечисляет результаты фаз текстом |
10. **Циклические зависимости** (research §6.4): фазы нумеруются, `depends_on` ссылается только на меньшие id (циклы невыразимы); псевдо-циклы — rework внутри фазы или повтор типа (две BUGFIX-фазы); data-dependent циклы между фазами запрещены.
11. **Stage 2 backlog** (research §9.1): `continue_on_error`, resume с произвольной фазы как first-class, явный DAG-`depends_on`, лимит 4, телеметрия длины сессий (кандидат — summarizer между фазами), поведение advisor на фазовых границах (NIT_ONLY_MODE window).

### Шаг 1.5 — Edge-case таблица Type Selection (:442–455)

Добавить строки (зеркалятся в orchestrator.md EDGE CASES — шаг 2.6):

```markdown
| «Исправь баг и добавь фичу» (2 primary deliverables, T3+T6) | MULTI_PHASE (T0): P1 BUGFIX → P2 DEV, user confirmation mandatory |
| «Исправь баг и обнови README» | NOT multi-phase (T0 anti-trigger): BUGFIX + Auto-DOCS hook |
| Multi-phase: user silence / ambiguous reply after the plan | Fail-closed: NOT a confirmation; re-show the plan (max 2 edit rounds), then CANCELLED |
| Multi-phase: phase FAILED | Fail-fast: downstream phases SKIPPED, report to the user; resume via PHASE_STATE.md (new session preferred) |
```

### Шаг 1.6 — Auto-DOCS Hook (:543–564)

Добавить в конец секции:

```markdown
**Multi-phase dedup:** within a MULTI_PHASE session the hook fires PER PHASE (after each BUGFIX/DEV phase's final `utility`), same as per-pipeline today. Exception: if the confirmed plan already contains a LATER DOCS phase covering the docs work, the hook is SUPPRESSED for the earlier phase — the implementation agent's `requires_docs_update: true` is carried into the phase result envelope as `docs_deferred_to: "<DOCS phase id>"`, and the DOCS phase's first Task prompt receives the envelope verbatim. Dedup key = phase type DOCS present downstream in `phases[]` (mechanical check, not analysis).
```

### Шаг 1.7 — §3 JSON Validation Fields (:667–765)

1. **orchestrator Required Fields (:669–680):** в строке `type` добавить `"MULTI_PHASE"`. Под таблицей — примечание:

   ```markdown
   **Conditional fields (MULTI_PHASE only):** `state`, `phases`, `current_phase` — REQUIRED when `type: "MULTI_PHASE"`, ABSENT otherwise (backward compatible; the plugin enforces conditionally in validateJSONOutput).
   ```
2. **Новая под-секция `### Multi-Phase Fields (orchestrator)`** (после orchestrator Required Fields):

   | Field | Type | Valid Values |
   |-------|------|--------------|
   | `state` | string \| null | `"AWAITING_CONFIRMATION"` (plan shown, Task forbidden), `"CANCELLED"` (user rejected), `null`/absent (executing / final summary) |
   | `phases` | array | 2–3 objects: `{id: "P<n>" unique, type: BUGFIX\|DEVOPS\|DEV\|DOCS, complexity: SIMPLE\|COMPLEX\|DEEP\|SUPERCOMPLEX\|null, plan_exists: bool\|null, goal: string, depends_on: [ids of EARLIER phases only; MVP: exactly [previous id], P1 → []]}` |
   | `current_phase` | string \| null | id from `phases[]`, or `null` iff `state ∈ {AWAITING_CONFIRMATION, CANCELLED}` |

   + правила: ровно одна стартовая фаза (`depends_on: []` = `phases[0]`); ≤1 SUPERCOMPLEX-фаза; SUPERCOMPLEX ⇒ `plan_exists: true` (enforced на executing-ходах; на AWAITING-ходе допустим `null` до DECOMPOSITION внутри фазы); phase refinement — `complexity`/`plan_exists` фазы могут уточниться `null → значение` ОДИН раз, только для текущей фазы, остальные поля и фазы заморожены; shapes: AWAITING/CANCELLED ⇒ `pipeline: []` + `next_agent: null`.
3. **Phase Result envelope** — спецификация из шага 1.4-п.6 (продублировать как канон JSON-конверта; envelope НЕ входит в orchestrator JSON — передаётся через Task prompts и PHASE_STATE.md).
4. **File-Pointer Fields (:765):** в список fixed-name pointers добавить `PHASE_STATE.md` (orchestrator → utility-scribe → следующая фаза / resume).

### Шаг 1.8 — Enforcement gates таблица (:646–664)

1. Строка «pipeline changed after Turn 1» — расширить список исключений: `…, SUPERCOMPLEX per-plan-step re-emission, MULTI_PHASE phase refinement (null→resolved, once per phase), MULTI_PHASE in-phase Auto-DOCS hook, MULTI_PHASE legal phase transition (+1, phases stable)`.
2. Новые строки:

   | Violation | Detection point | Delivery | Blocks |
   |-----------|-----------------|----------|--------|
   | Task call while `state: "AWAITING_CONFIRMATION"` (same turn, before user reply) | tool.execute.before | DIRECT throw (confirmation gate) | the Task call |
   | illegal phase transition (skip / phases tampering / wrong chain for the phase) | message.updated | deferred flag (pipelineImmutable) → gate | any tool call |
   | MULTI_PHASE schema violation (phases 2–3, unique ids, depends_on ⊆ earlier, ≤1 SUPERCOMPLEX, AWAITING/CANCELLED shapes) | message.updated (validateJSONOutput/validatePipeline) | deferred flag (invalidJSON / pipelineMismatch) → gate | any tool call |
3. Уточнение terminal-turn exemption (:1934–1944 в плагине; в ARCHITECTURE — сноска к gates): `state: "AWAITING_CONFIRMATION"` валидируется ЯВНОЙ веткой validatePipeline ДО terminal exemption (иначе AWAITING-ход неотличим от финального — research §7.5 строка 4).

### Шаг 1.9 — §9 Plugin Hooks (:1002–1014)

- Строка `message.updated`: добавить «…multi-phase per-phase pipeline validation (key = phase's type-complexity-plan_exists); confirmation-gate tracking (AWAITING set / user-reply clear); phase-transition mutation whitelist; blockerStop reset on legal phase transition (v7)».
- Строка `tool.execute.before`: добавить «…confirmation gate — Task blocked while AWAITING_CONFIRMATION in the same turn (v7)».
- §2 Scope rule (:366): одно предложение — «MULTI_PHASE keeps this rule: the `pipeline` field holds the CURRENT phase's linear chain; phases are concatenated sequentially by the primary, never in parallel».

---

## Phase 2: Orchestrator Changes (`agents/orchestrator.md` live-first + `agents/utility.md`)

> Правки в LIVE (`C:\Users\Admin\.config\opencode\agents\…`), затем `config-sync --save` (Phase 5). Язык секций — английский (конвенция файла). Anchors: PIPELINE TABLE :39–61, SUPERCOMPLEX :118–152, TURN ALGORITHM :154–169, JSON FORMAT :171–186, CLASSIFICATION RULES :206–237, TYPE SELECTION :239–252, EDGE CASES :254–267, EXAMPLES :276–339, PROHIBITIONS :341–352, PLUGIN ENFORCEMENT :354–363.

### Шаг 2.1 — PIPELINE TABLE: мета-правило (после Auto-DOCS hook note :61)

БЕЗ новых строк. Вставить текст meta-rule из шага 1.4-п.2 (1:1 с ARCHITECTURE.md) + указатель: «See MULTI-PHASE PIPELINES section below for the full protocol».

### Шаг 2.2 — Новая секция `## MULTI-PHASE PIPELINES (type MULTI_PHASE — phases, confirmation, boundaries)`

**Место:** после `## SUPERCOMPLEX PIPELINE` (:152), перед `## TURN ALGORITHM` (:154). Структура (операционная версия канона Phase 1.4 — протоколы, не теория):

**Stage 0 — Detection (T0):** ссылка на TYPE SELECTION T0 + анти-триггеры; «при сомнении — single-phase».

**Stage 1 — Phase planning + AWAITING (Turn 1):**
1. Разбить запрос на 2–3 первичных deliverable; для каждого применить T3–T6 (тип) и правила сложности (BUGFIX → `complexity: null`; DEV → Q1–Q5, при неясности — `null` с уточнением на старте фазы через DECOMPOSITION; DOCS → SIMPLE/DEEP; DEVOPS → `null`).
2. Вывести JSON:

   ```json
   {
     "agent": "orchestrator", "type": "MULTI_PHASE", "complexity": null,
     "plan_exists": null, "plan_source": null, "goal": "one sentence",
     "next_agent": null, "pipeline": [],
     "state": "AWAITING_CONFIRMATION",
     "phases": [
       {"id": "P1", "type": "BUGFIX", "complexity": null, "plan_exists": null, "goal": "…", "depends_on": []},
       {"id": "P2", "type": "DEV", "complexity": null, "plan_exists": null, "goal": "…", "depends_on": ["P1"]}
     ],
     "current_phase": null
   }
   ```
3. Показать план (единственный легальный prose-блок — см. PROHIBITIONS; заголовок НЕ должен совпадать с forbidden-vocab «## PLAN» / «# Implementation Plan» и self-work маркерами):

   ```markdown
   ## MULTI-PHASE PLAN — AWAITING CONFIRMATION
   | # | id | type | goal | pipeline (row) | depends_on |
   |---|----|------|------|----------------|------------|
   | 1 | P1 | BUGFIX | исправить <баг> | bugfix-triage → continuation (row 1) | — |
   | 2 | P2 | DEV | добавить <фичу> | row 3–6 after Q1–Q5 (with P1 results) | P1 |

   Reply «да/ок» to start, request edits (max 2 rounds), or «отмена» to cancel.
   ```
4. Ack: `→ PHASE PLAN AWAITING CONFIRMATION (2 phases)`. STOP — Task НЕ вызывается (плагин блокирует).

**Stage 2 — Confirmation turn (ответ пользователя):**

| Ответ | Действие |
|-------|----------|
| «да / ок / поехали» (однозначное согласие) | JSON: `state: null`, `current_phase: "P1"`, `pipeline` = цепочка P1 (для BUGFIX — `["bugfix-triage"]`), `next_agent` = pipeline[0] → Task → ack `→ PHASE 1/2 (P1): DELEGATED to <agent> for: <goal>` |
| Правка («фазу 2 сделай SIMPLE», «убери P3») | Пересчёт затронутой фазы + каскад зависимостей (отклонённая фаза → downstream SKIPPED с информированием) → повторный AWAITING (лимит 2 раунда; после — «стартуем как есть или отмена») |
| «отмена / не надо» | JSON `state: "CANCELLED"`, `pipeline: []`, `next_agent: null`, `current_phase: null` + краткое резюме предложенного. Ноль Task |
| Тишина / неоднозначно | Fail-closed: НЕ подтверждение — переспросить (раунд правок) |
| Override в ИСХОДНОМ запросе («без подтверждений, делай сразу») | Auto-approve: план показывается информативно, старт P1 в ТОМ ЖЕ ходе (без AWAITING JSON) |

**Stage 3 — Phase execution (каждая фаза = существующая механика строки):**
1. Внутри фазы действуют ВСЕ правила её строки: BUGFIX continuation (one-time), DECOMPOSITION (Q1/Q3), rework loop max 3, SEVERITY RULES, ADVISOR STEP RULES, SUPERCOMPLEX per-step (с двухуровневым ack).
2. Уточнение фазы: если `phases[i].complexity === null` для DEV-фазы — на старте фазы применить Q1–Q5 (с учётом конверта предыдущей фазы), при >3 шагах — DECOMPOSITION; в JSON уточнять `phases[i]` (`null → значение`, ОДИН раз, только текущая фаза).
3. Ack каждого delegation-хода с фазовым префиксом: `→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>`; внутри SUPERCOMPLEX-фазы: `→ PHASE <i>/<n> (<id>), STEP <j>/<m> (<sid>): DELEGATED to <agent>`.
4. **Phase barrier (конец фазы):** после финального `utility` фазы (или `devops-reviewer` для DEVOPS) оркестратор МЕХАНИЧЕСКИ собирает Phase Result envelope (см. JSON FORMAT/ARCHITECTURE §3) из уже прочитанных полей (status utility, `files_modified` consistency-checker, `requires_docs_update`, `TRIAGE_RESULT`, severity-итоги) — это mechanical field reads, НЕ анализ.
5. **PHASE_STATE scribe:** в Task prompt финального `utility` фазы добавить блок: `PHASE_STATE TASK: append the following section VERBATIM to PHASE_STATE.md (create the file with the header "# PHASE_STATE" if it does not exist; append-only, never modify previous sections): <section markdown>`. Для DEVOPS-фаз (нет utility) — секция накапливается и уходит в PHASE_STATE TASK ближайшего следующего utility; если цепочка ЗАКАНЧИВАЕТСЯ DEVOPS-фазой — хвостовая секция не пишется (MVP-ограничение), финальный summary перечисляет результаты текстом.
6. **Auto-DOCS hook per-phase + dedup:** как сегодня, но если в `phases[]` есть ПОЗДНЕЙШАЯ DOCS-фаза — hook подавить, в конверт добавить `docs_deferred_to: "<id>"` (правило — ARCHITECTURE §2 Auto-DOCS Hook).

**Stage 4 — Phase transition (граница):** следующий ход после barrier: JSON — `phases` БЕЗ изменений, `current_phase: "P<next>"`, `pipeline` = цепочка следующей фазы (по её ключу, с учётом уточнения), `next_agent` = pipeline[0]; первый Task prompt фазы получает конверт предыдущей verbatim + фразу-контекст: `Phase P<i> (<type>) completed: <summary>. Artifacts: <list>. Facts: <facts>. Read PHASE_STATE.md if you need more context.` Ack: `→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>`. Плагин: легальная мутация MP-5 (сброс rework/blocker-счётчиков).

**Stage 5 — Failure & completion:**
- Фаза FAILED (utility FAIL не исправлен rework / BLOCKER STOP AFTER 3) → fail-fast: JSON final (`next_agent: null`, `pipeline: []`, state null), downstream SKIPPED, отчёт: фаза, конверт, опции («продолжи с P<k>» = resume).
- Все фазы SUCCESS → final summary по всем фазам (таблица: фаза / статус / артефакты), `next_agent: null`, `pipeline: []`.
- Resume («продолжи с фазы P2»): Turn 1 — ОДИН classification `read` PHASE_STATE.md (разрешённое исключение — как чтение plan-файла); план НЕ пересоздаётся; JSON: те же `phases`, `current_phase: "P2"`, старт без повторного подтверждения (если план не изменился). Предпочтительно в НОВОЙ сессии (после BLOCKER STOP та же сессия заблокирована кумулятивным `blockerStop` — в новой сессии состояние плагина свежее).

### Шаг 2.3 — TURN ALGORITHM (:154–169)

1. **Turn 1 — CLASSIFY**, пункт 2: после «(Optional) Inspect to classify ONLY» добавить: «T0 multi-phase detection runs FIRST (TYPE SELECTION). If MULTI_PHASE → Stage 1 of MULTI-PHASE PIPELINES (AWAITING turn — no Task call this turn).»
2. Добавить третий блок хода:

   ```markdown
   **Confirmation turn (MULTI_PHASE only):** the user's reply is your next turn — apply Stage 2 of MULTI-PHASE PIPELINES (approve → start P1; edit → re-plan (≤2 rounds); reject → CANCELLED JSON; ambiguous → fail-closed re-ask).
   ```
3. Пункт mechanical field reads (:169): дополнить список — «…`plan_gap`, `steps` (DECOMPOSITION), **phase envelope assembly (MULTI-PHASE Stage 3 item 4: status/artifacts/facts copied from utility/consistency-checker/implementation JSON — mechanical, not analysis)**».
4. Turns 2..N пункт 2 (:165): «NEVER re-classify, NEVER change the pipeline (except the one-time BUGFIX continuation, **the MULTI_PHASE phase refinement / in-phase Auto-DOCS hook / phase transition — Stage 3–4**)».

### Шаг 2.4 — JSON FORMAT (:171–186)

Расширить схему (обратно-совместимо — последние три поля ТОЛЬКО для MULTI_PHASE, в остальных ходах ОТСУТСТВУЮТ):

```json
{
  "agent": "orchestrator",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|MULTI_PHASE|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|SUPERCOMPLEX|null",
  "plan_exists": true|false|null,
  "plan_source": "description or null",
  "goal": "one sentence",
  "next_agent": "agent from routing table or null",
  "pipeline": ["agent1", "agent2"] or [],
  "state": "AWAITING_CONFIRMATION|CANCELLED|null",
  "phases": [ {"id": "P1", "type": "…", "complexity": "…|null", "plan_exists": "…|null", "goal": "…", "depends_on": []} ],
  "current_phase": "P1|null"
}
```

Правила под схемой:
- `type: "MULTI_PHASE"` ⇒ `complexity`/`plan_exists`/`plan_source` top-level = `null` (классификация живёт в `phases[]`); top-level `plan_source: "DECOMPOSITION"` допустим на Turn B внутри-фазовой декомпозиции (существующее исключение).
- `state: "AWAITING_CONFIRMATION"` ⇒ `pipeline: []`, `next_agent: null`, `current_phase: null`; Task запрещён до ответа пользователя.
- `state: "CANCELLED"` ⇒ та же форма; сессия multi-phase завершена.
- Исполнение/финал ⇒ `state: null` (или поле отсутствует), `current_phase` = id активной фазы, `pipeline` = её цепочка.
- `If next_agent is null → do NOT call Task` (:186) — сохраняется.

### Шаг 2.5 — TYPE SELECTION (:239–252)

1. Строка T0 перед T1 — 1:1 зеркало шага 1.3 (таблица + strong triggers + anti-triggers + primacy heuristic + default single-phase).
2. Mixed-intent (:250) — 1:1 зеркало шага 1.2.

### Шаг 2.6 — EDGE CASES (:254–267)

Добавить строки — зеркало шага 1.5 (4 строки) + операционные:

```markdown
| Multi-phase: «продолжи с фазы P2» после падения | Resume: read PHASE_STATE.md (ONE classification read), same phases[], current_phase P2, no re-confirmation if the plan is unchanged; prefer a NEW session after BLOCKER STOP |
| Multi-phase: цепочка заканчивается DEVOPS-фазой | Хвостовая секция PHASE_STATE.md не пишется — финальный summary перечисляет результаты всех фаз текстом |
| Multi-phase: >3 первичных deliverable | Рекомендовать пользователю разбить на отдельные запросы (MVP limit 3) или объединить смежные фазы |
```

### Шаг 2.7 — CLASSIFICATION EXAMPLES (:276–339) — Examples 13–16

```markdown
### Example 13 — MULTI_PHASE: BUGFIX + DEV (full trace)
- **Request:** «Auth middleware падает с race condition — исправь, и сразу добавь refresh-токены»
- **Turn 1 (AWAITING):** `type: "MULTI_PHASE"`, `state: "AWAITING_CONFIRMATION"`, `next_agent: null`, `pipeline: []`, `phases: [P1 BUGFIX (null/null), P2 DEV (null/null, depends_on [P1])]`, `current_phase: null` + таблица «## MULTI-PHASE PLAN» + ack `→ PHASE PLAN AWAITING CONFIRMATION (2 phases)`. Task НЕ вызывается.
- **Turn 2 (user «да»):** `state: null`, `current_phase: "P1"`, `pipeline: ["bugfix-triage"]`, `next_agent: "bugfix-triage"` → ack `→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: исправить race condition`.
- **Turn 3 (TRIAGE_RESULT: DEEP):** continuation внутри фазы (row 1 DEEP), ack с фазовым префиксом.
- **Barrier P1:** envelope {status SUCCESS, facts {tests green, files_changed 3}} → PHASE_STATE TASK в prompt utility.
- **Transition:** `current_phase: "P2"`; P2 уточняется Q1–Q5 с учётом P1 (3 шага → COMPLEX row 5); `pipeline: ["dev-planner", …]`; Task prompt dev-planner получает envelope verbatim + «Phase P1 (BUGFIX) completed: …».
- **Final:** summary по обеим фазам, `next_agent: null`.
- **Why:** два первичных разнотипных deliverable (T3 + T6), зависимость по данным (фича поверх исправленного кода) — T0 YES.

### Example 14 — MULTI_PHASE: DEVOPS + DEV + DEVOPS (short)
- **Request:** «1. Настрой CI. 2. Добавь тесты. 3. Задеплой»
- **Turn 1:** AWAITING, `phases: [P1 DEVOPS, P2 DEV, P3 DEVOPS]` (явная нумерация разнотипных шагов — strong trigger 2; повтор типа допустимен — id разные).
- **Why:** каждая часть первична (нужны devops-agent+devops-reviewer / код тестов / операция деплоя); P2 потребляет имя workflow из P1, P3 — статус тестов из P2.

### Example 15 — anti-trigger (NOT multi-phase)
- **Request:** «Исправь баг с авторизацией и задеплой на прод»
- **JSON:** `type: "BUGFIX"` (row 1) — single-phase; деплой упомянут в финальном summary как follow-up.
- **Why:** deploy после фикса = follow-up (анти-триггер); multi-phase ТОЛЬКО если деплой нетривиален (миграции, откат). Contrast с Example 11 (README → Auto-DOCS hook).

### Example 16 — explicit auto-approve override
- **Request:** «Без подтверждений, сделай сразу: исправь баг X и добавь фичу Y»
- **Turn 1:** план фаз показывается информативно, НО сразу `state: null`, `current_phase: "P1"`, `pipeline: ["bugfix-triage"]`, `next_agent: "bugfix-triage"` → Task.
- **Why:** explicit request override (Stage 2) — confirmation схлопывается в информирование; default без override — подтверждение обязательно.
```

### Шаг 2.8 — PROHIBITIONS (:341–352)

1. :347 «No prose between identity line and JSON. No analysis after the ack line.» → добавить исключение: «**Exception:** the `## MULTI-PHASE PLAN` table on AWAITING_CONFIRMATION turns (it IS the confirmation request, not analysis). Heading must not collide with forbidden vocabulary.»
2. :348 «No pipeline changes after Turn 1 (except: …)» → дополнить список: «…, **the MULTI_PHASE phase refinement (null→resolved, once per phase), the MULTI_PHASE in-phase Auto-DOCS hook, and the legal phase transition (+1, phases stable)**».
3. Новые пункты:

   ```markdown
   - 🚫 No Task call on an AWAITING_CONFIRMATION turn — the plugin throws. Wait for the user's reply.
   - 🚫 No skipping the MULTI_PHASE confirmation unless the ORIGINAL request explicitly says «без подтверждений / делай сразу» (auto-approve override).
   - 🚫 No nested multi-phase: a phase may BE SUPERCOMPLEX, but phases never contain sub-phases; max ONE SUPERCOMPLEX phase per plan.
   - 🚫 No phases of the other primary's scope: any plan/research deliverable → T0 NO → OUT OF SCOPE as usual.
   ```

### Шаг 2.9 — PLUGIN ENFORCEMENT (:354–363)

Добавить bullets:

```markdown
- **Multi-phase validation**: for type=MULTI_PHASE the pipeline is validated PER PHASE (key = phase's type/complexity/plan_exists against PIPELINE TABLE + variants); phases structure validated (2–3, unique ids, depends_on ⊆ earlier, ≤1 SUPERCOMPLEX)
- **Confirmation gate**: Task calls are BLOCKED while state=AWAITING_CONFIRMATION until the user replies
- **Phase transition whitelist**: pipeline replacement is legal only as refinement / in-phase Auto-DOCS hook / phase advance (+1)
```

### Шаг 2.10 — `agents/utility.md` (live + mirror): PHASE_STATE scribe

Добавить секцию (после «Your role», :19–25 — пункт 4 роли; и Rules):

```markdown
4. PHASE_STATE scribe (multi-phase pipelines only):
   - If your Task prompt contains a `PHASE_STATE TASK:` block, append the given section
     VERBATIM to `PHASE_STATE.md` in the project root using bash
     (PowerShell: `Add-Content -Path PHASE_STATE.md -Value @'…'@`; create the file with
     the header line `# PHASE_STATE` first if it does not exist).
   - APPEND-ONLY: never modify or delete previous sections. This is a mechanical file
     operation, not content generation — copy the section exactly as given.
   - Report `PHASE_STATE: appended` (or `PHASE_STATE: FAILED <reason>`) in your output.
```

Обоснование механизма: у utility `edit: deny`, `write: deny`, `bash: "*": allow` (`utility.md:6-12`) — bash-append единственный легальный канал; операция механическая (verbatim), что совместимо с ролью utility («file operations» в description :2). Permissions НЕ меняются.

---

## Phase 3: Plugin Changes (`plugins/workflow-enforcement.ts`, live-first)

> Версионирование: комментарии `// v7 (Multi-Phase MVP)`. Все изменения — orchestrator-scoped; plankestrator не затрагивается. Anchors: VALID_VALUES :60–72, pipelineState :172, resets :312–334, blockerStop :474–499, turn boundary :534–543, primary validation :700–792, recovery/state block :815–933, ack audit :948–957, gate 9.0в :1105–1138, rework cap :1466–1486, validatePipeline :1883–2009, validateNextAgent :2014–2032, validateJSONOutput :2038–2123.

### Шаг 3.1 — Константы и состояние (после :198)

```ts
// ============================================================
// v7 (Multi-Phase MVP) — phase-level state + confirmation gate.
// MVP: linear chain, MULTI_PHASE_MIN..MAX phases, depends_on = [previous].
// Stage 2: MAX → 4, explicit DAG, continue_on_error.
// ============================================================
const MULTI_PHASE_MIN = 2
const MULTI_PHASE_MAX = 3
const MULTI_PHASE_TYPES = ["BUGFIX", "DEVOPS", "DEV", "DOCS"]
const MULTI_PHASE_STATES = ["AWAITING_CONFIRMATION", "CANCELLED"]
const DOCS_HOOK_CHAIN = ["docs-writer", "utility"]

// Confirmation gate: true between an AWAITING_CONFIRMATION JSON and the user's
// reply. Clearing: (a) a user-role message (role pattern of the self-work guard,
// :1016), or (b) ANY new assistant messageID — turn-based guarantee: the primary
// only wakes on user input or Task completion, and Task is blocked while awaiting,
// so a new assistant turn IMPLIES a user reply (fallback if opencode does not
// surface user-role messages to plugins).
let awaitingConfirmation = false
let awaitingMsgId: string | null = null
```

Расширить тип `pipelineState` (:172):

```ts
const pipelineState = new Map<string, {
  pipeline: string[]; currentStep: number; provisional: boolean; type: string | null;
  phases?: any[]; currentPhaseIdx?: number   // v7: MULTI_PHASE only
}>()
```

В reset-блок `session.created` (:325–334) добавить: `awaitingConfirmation = false; awaitingMsgId = null`.

### Шаг 3.2 — VALID_VALUES (:60–72)

```ts
orchestrator: {
  agent: ["orchestrator"],
  type: ["BUGFIX", "DEVOPS", "DEV", "DOCS", "MULTI_PHASE", null],
  complexity: ["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX", null],
  state: ["AWAITING_CONFIRMATION", "CANCELLED", null]   // v7: optional; validated if present
},
```

(`validateJSONOutput` :2052–2056 проверяет поле только если `json[field] !== undefined` — `state` остаётся опциональным для single-phase; `null` — легальное значение.)

### Шаг 3.3 — Хелперы multi-phase (перед validatePipeline, ~:1880)

```ts
/** v7: current phase object of a MULTI_PHASE JSON, or null. */
function resolveCurrentPhase(json: any): any | null {
  if (String(json?.type) !== "MULTI_PHASE" || !Array.isArray(json?.phases)) return null
  if (json?.current_phase == null) return null
  return json.phases.find((p: any) => p?.id === json?.current_phase) ?? null
}

/** v7: structural validation of phases[] (fail-closed). Returns error string or null. */
function validatePhasesStructure(phases: any, state: string | null): string | null {
  if (!Array.isArray(phases)) return "phases must be an array"
  if (phases.length < MULTI_PHASE_MIN || phases.length > MULTI_PHASE_MAX)
    return `phases.length ${phases.length} out of range [${MULTI_PHASE_MIN}..${MULTI_PHASE_MAX}] (MVP; >3 → ask the user to split the request)`
  const ids = new Set<string>()
  let supercomplexCount = 0
  for (let i = 0; i < phases.length; i++) {
    const p = phases[i]
    if (!p || typeof p.id !== "string" || !p.id) return `phases[${i}].id missing`
    if (ids.has(p.id)) return `duplicate phase id "${p.id}"`
    ids.add(p.id)
    if (!MULTI_PHASE_TYPES.includes(String(p.type))) return `phases[${i}].type invalid: ${p.type}`
    if (p.complexity != null && !["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX"].includes(String(p.complexity)))
      return `phases[${i}].complexity invalid: ${p.complexity}`
    if (p.plan_exists != null && typeof p.plan_exists !== "boolean")
      return `phases[${i}].plan_exists must be boolean|null`
    if (String(p.complexity) === "SUPERCOMPLEX") {
      supercomplexCount++
      // AWAITING time: plan_exists may still be null (in-phase DECOMPOSITION pending)
      if (state !== "AWAITING_CONFIRMATION" && p.plan_exists !== true)
        return `phases[${i}]: SUPERCOMPLEX requires plan_exists=true`
    }
    // MVP linear chain: depends_on = exactly [previous id]; root = phases[0] with []
    const deps = Array.isArray(p.depends_on) ? p.depends_on : null
    if (!deps) return `phases[${i}].depends_on must be an array`
    const expectedDeps = i === 0 ? [] : [phases[i - 1].id]
    if (JSON.stringify(deps) !== JSON.stringify(expectedDeps))
      return `phases[${i}].depends_on must be ${JSON.stringify(expectedDeps)} (MVP: linear chain)`
  }
  if (supercomplexCount > 1) return `at most ONE SUPERCOMPLEX phase allowed (got ${supercomplexCount})`
  return null
}

/** v7: true iff phases arrays are identical EXCEPT null→value refinement of the
 *  current phase's complexity/plan_exists (once; other fields frozen). */
function phasesStableOrRefined(prevPhases: any[], newPhases: any[], currentPhaseId: any): boolean {
  if (!Array.isArray(prevPhases) || prevPhases.length !== newPhases.length) return false
  for (let i = 0; i < prevPhases.length; i++) {
    const a = prevPhases[i] ?? {}, b = newPhases[i] ?? {}
    if (a.id !== b.id || a.type !== b.type || a.goal !== b.goal ||
        JSON.stringify(a.depends_on) !== JSON.stringify(b.depends_on)) return false
    const isCurrent = a.id === currentPhaseId
    const complexOk = a.complexity === b.complexity ||
      (isCurrent && (a.complexity === null || a.complexity === undefined) && b.complexity != null)
    const planOk = a.plan_exists === b.plan_exists ||
      (isCurrent && (a.plan_exists === null || a.plan_exists === undefined) && typeof b.plan_exists === "boolean")
    if (!complexOk || !planOk) return false
  }
  return true
}
```

### Шаг 3.4 — validatePipeline: MULTI_PHASE ветка (:1883–2009)

Вставить ПОСЛЕ type-null early return (:1928–1932) и ДО terminal exemption (:1940):

```ts
// v7 (Multi-Phase MVP): explicit branch — AWAITING/CANCELLED shapes are handled
// HERE, BEFORE the terminal-turn exemption (:1940), so an AWAITING turn is
// distinguishable from a final turn (research §7.5 row 4 — shape-based exemption
// would silently swallow it).
if (agent === "orchestrator" && type === "MULTI_PHASE") {
  const mpState = jsonContent?.state != null ? String(jsonContent.state) : null
  const phases = jsonContent?.phases
  if (mpState !== null && !MULTI_PHASE_STATES.includes(mpState))
    return { valid: false, error: `Invalid state for MULTI_PHASE: ${mpState}` }
  if (mpState === "AWAITING_CONFIRMATION" || mpState === "CANCELLED") {
    if (pipeline.length !== 0 || (jsonContent?.next_agent !== null && jsonContent?.next_agent !== undefined))
      return { valid: false, error: `state=${mpState} requires pipeline=[] and next_agent=null` }
    if (jsonContent?.current_phase != null)
      return { valid: false, error: `state=${mpState} requires current_phase=null` }
    if (mpState === "AWAITING_CONFIRMATION") {
      const structErr = validatePhasesStructure(phases, mpState)
      if (structErr) return { valid: false, error: structErr }
    }
    return { valid: true }
  }
  // v7: TERMINAL TURN of a multi-phase session (final summary): state=null,
  // pipeline=[], next_agent=null. Same shape exemption as :1940, replicated
  // HERE because this branch sits BEFORE :1940 and intercepts ALL MULTI_PHASE
  // turns — without it the final turn falls into the per-phase key check and
  // [] never matches the phase chain (false pipelineMismatch on every
  // multi-phase completion).
  if (mpState === null && pipeline.length === 0 &&
      (jsonContent?.next_agent === null || jsonContent?.next_agent === undefined)) {
    return { valid: true }
  }
  // Executing turn: structure + per-phase key
  const structErr = validatePhasesStructure(phases, mpState)
  if (structErr) return { valid: false, error: structErr }
  const phase = resolveCurrentPhase(jsonContent)
  if (!phase)
    return { valid: false, error: `current_phase "${jsonContent?.current_phase}" not found in phases[].id` }
  // In-phase Auto-DOCS hook (canonical 2-agent chain only — mechanical, safe)
  if (JSON.stringify(pipeline) === JSON.stringify(DOCS_HOOK_CHAIN) &&
      ["BUGFIX", "DEV"].includes(String(phase.type)))
    return { valid: true }
  // Per-phase key against the EXISTING table + variants (fail-closed preserved)
  const pKey = String(phase.type) === "DOCS"
    ? `${phase.type}-${phase.complexity}-any`
    : `${phase.type}-${phase.complexity}-${String(phase.plan_exists ?? null)}`
  const pExpected = PIPELINES.orchestrator?.[pKey]
  const pVariants = PIPELINE_VARIANTS[`orchestrator:${pKey}`]
  if (!pExpected && !pVariants)
    return { valid: false, error: `MULTI_PHASE: unknown phase combination "${pKey}" for phase ${phase.id} (fail-closed)` }
  const pMatches = pVariants
    ? pVariants.some(v => JSON.stringify(pipeline) === JSON.stringify(v))
    : JSON.stringify(pipeline) === JSON.stringify(pExpected)
  if (!pMatches)
    return { valid: false, error: `MULTI_PHASE: pipeline mismatch for phase ${phase.id} (${pKey}). Expected: ${
      pVariants ? pVariants.map(v => `[${v.join(", ")}]`).join(" | ") : `[${pExpected!.join(", ")}]`
    }, got: [${pipeline.join(", ")}]` }
  return { valid: true }
}
```

Дополнительно в существующих правилах:
- **Rule 3** (:1964–1970, «complexity=null only for BUGFIX/DEVOPS»): ветка MULTI_PHASE возвращает valid РАНЬШЕ — Rule 3 не затрагивается (top-level `complexity: null` легален). Проверить порядок: вставка до :1946 гарантирует это.
- **Rule 1** (:1948, SUPERCOMPLEX+plan_exists=false): для MULTI_PHASE не применяется top-level (фаза SUPERCOMPLEX ⇒ plan_exists=true проверяется в `validatePhasesStructure`).
- **Terminal exemption** (:1940–1944): ветка MULTI_PHASE вставлена ДО неё и перехватывает ВСЕ MULTI_PHASE-ходы, поэтому terminal-shape (`pipeline: []`, `next_agent: null`, `state: null`) обрабатывается ЯВНЫМ early return внутри ветки (см. код выше) — финальный ход не доходит до :1940, но семантика exemption сохранена (сессия завершена, ложного pipelineMismatch нет; покрыто T15b).

### Шаг 3.5 — provisional fix + multi-phase mutation whitelist (:850–933, state block)

**3.5.1 — provisional ловушка (edge case #1 задания).** Заменить :861:

```ts
// v7 fix (research §7.3-2 provisional trap): top-level complexity of MULTI_PHASE
// turns is ALWAYS null → without this guard prev.provisional would stay true for
// the WHOLE multi-phase session and exception F-4 below would allow ANY pipeline
// replacement (immutability effectively dead). MULTI_PHASE immutability is
// governed by the MP-1..MP-6 whitelist instead.
const provisional = (jsonContent.complexity === null || jsonContent.complexity === undefined) &&
  String(jsonContent.type) !== "MULTI_PHASE"
```

**3.5.2 — Turn 1 lock (:864–872):** добавить в объект состояния:

```ts
pipelineState.set(currentAgent, {
  pipeline: newPipeline,
  currentStep: nextIdx >= 0 ? nextIdx : 0,
  provisional,
  type: newType,
  // v7: multi-phase snapshot (phases + index)
  phases: newType === "MULTI_PHASE" && Array.isArray(jsonContent.phases) ? jsonContent.phases : undefined,
  currentPhaseIdx: newType === "MULTI_PHASE"
    ? (Array.isArray(jsonContent.phases) ? jsonContent.phases.findIndex(p => p?.id === jsonContent?.current_phase) : -1)
    : undefined
})
```

+ warn-only лог при `currentPhaseIdx > 0` на Turn 1 lock: `MULTI_PHASE RESUME DETECTED — current_phase ≠ phases[0]; verify prior phase results exist in PHASE_STATE.md` (resume-сценарий, шаг 2.2 Stage 5).

**3.5.3 — Mutation whitelist (:873–909).** Заменить вычисление `isException` на две ветки:

```ts
} else if (JSON.stringify(newPipeline) !== JSON.stringify(prev.pipeline)) {
  // Phase 17.2 — pipeline changed after being locked
  let isException: boolean
  let mpCase: string | null = null
  if (prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE") {
    // v7: MULTI_PHASE immutability — closed whitelist MP-1..MP-6 (F-4 provisional
    // does NOT apply; see the provisional fix above).
    const newPhases = Array.isArray(jsonContent.phases) ? jsonContent.phases : []
    const prevIdx = prev.currentPhaseIdx ?? -1
    const newIdx = newPhases.findIndex((p: any) => p?.id === jsonContent?.current_phase)
    const samePhase = prevIdx >= 0 && newIdx === prevIdx
    const phaseAdvanced = prevIdx >= 0 && newIdx === prevIdx + 1   // MVP: strictly +1
    const stableOrRefined = phasesStableOrRefined(prev.phases ?? [], newPhases, jsonContent?.current_phase)
    const prevPhase = (prev.phases ?? [])[prevIdx]
    const newPhase = newPhases[newIdx]
    const isBugfixContinuationMP = samePhase && String(prevPhase?.type) === "BUGFIX" &&
      JSON.stringify(prev.pipeline) === JSON.stringify(["bugfix-triage"]) &&
      newPipeline.length > 1 && newPipeline[0] === "bugfix-triage"   // variants re-validated by validatePipeline
    const isDocsHookMP = samePhase && JSON.stringify(newPipeline) === JSON.stringify(DOCS_HOOK_CHAIN) &&
      ["BUGFIX", "DEV"].includes(String(newPhase?.type ?? prevPhase?.type))
    const isDecompMP = samePhase && (jsonContent.plan_source === "DECOMPOSITION" ||
      (newPipeline.length === 1 && ["dev-planner", "codebase-analyzer"].includes(newPipeline[0])))
    if (samePhase && stableOrRefined && (isDecompMP || isBugfixContinuationMP || isDocsHookMP ||
        String(newPhase?.complexity) === "SUPERCOMPLEX" /* F-11 parity, log-only */)) {
      isException = true
      mpCase = isDocsHookMP ? "MP-4 in-phase Auto-DOCS hook"
        : isBugfixContinuationMP ? "MP-2 in-phase BUGFIX continuation"
        : isDecompMP ? "MP-1/MP-3 phase refinement / DECOMPOSITION"
        : "MP-6 SUPERCOMPLEX per-step re-emission"
    } else if (phaseAdvanced && stableOrRefined) {
      isException = true
      mpCase = "MP-5 phase transition"
    } else {
      isException = false
    }
  } else {
    isException =
      prev.provisional ||                                     // F-4 (single-phase only, v7)
      jsonContent.type === "BUGFIX" ||                        // BUGFIX continuation
      jsonContent.plan_source === "DECOMPOSITION" ||          // DECOMPOSITION Turn B (Q3)
      jsonContent.severity === "nit" ||                       // nit-skip re-emission
      (prev.type !== "DOCS" && newType === "DOCS") ||         // F-12: Auto-DOCS hook
      (!SUPERCOMPLEX_STRICT && jsonContent.complexity === "SUPERCOMPLEX") // F-11 / R15
  }
  if (isException) {
    // ...existing counter resets (:887–894) unchanged...
    // v7: blockerStop reset is SCOPED to the legal phase transition ONLY
    // (edge case #2 — resume after fail-fast in the SAME session; conservative:
    // single-phase semantics "cumulative, only session.created clears" untouched).
    if (mpCase === "MP-5 phase transition" && blockerStop) {
      blockerStop = false
      violationDetail = ""
      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
        message: "BLOCKERSTOP RESET — legal multi-phase transition (new phase = new fail-fast context)" } })
    }
    if (mpCase) await client.app.log({ body: { service: "workflow-enforcement", level: "info",
      message: `MULTI_PHASE MUTATION ALLOWED — ${mpCase}`, extra: { agent: currentAgent, mpCase } } })
    maxStepReached.set(currentAgent, nextIdx >= 0 ? nextIdx : 0)
    prev.pipeline = newPipeline
    if (nextIdx >= 0) prev.currentStep = nextIdx
    prev.provisional = provisional
    prev.type = newType
    // v7: refresh phase snapshot
    if (newType === "MULTI_PHASE") {
      prev.phases = Array.isArray(jsonContent.phases) ? jsonContent.phases : prev.phases
      const idx = (prev.phases ?? []).findIndex((p: any) => p?.id === jsonContent?.current_phase)
      if (idx >= 0) prev.currentPhaseIdx = idx
    }
  } else {
    pipelineImmutable = true
    v6FlagSetThisEvent = true
    violationDetail = mpCase === null && (prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE")
      ? `PIPELINE IMMUTABLE (MULTI_PHASE): illegal mutation — allowed: phase refinement (null→resolved, once), in-phase BUGFIX continuation / DECOMPOSITION / Auto-DOCS hook, phase transition (+1, phases stable). Got: [${prev.pipeline.join(", ")}] → [${newPipeline.join(", ")}], current_phase ${prev.currentPhaseIdx} → ${jsonContent?.current_phase}`
      : `PIPELINE IMMUTABLE: ... (existing text :908)`
  }
}
```

Примечание: `SUPERCOMPLEX` per-step re-emission внутри фазы обычно идёт по ветке «pipeline unchanged» (:910–931, advance step) — MP-6 нужен только если модель пере-эмитирует массив (R15 log-only паритет через effComplexity фазы).

### Шаг 3.6 — Confirmation gate (edge case из требований: state AWAITING_CONFIRMATION)

**3.6.1 — Установка флага** (в primary-validation branch, после успешной валидации JSON — рядом с :816 `hasOutputtedJSON.set(...)`):

```ts
// v7: confirmation gate arming — a VALID AWAITING_CONFIRMATION JSON arms the gate.
if (currentAgent === "orchestrator" && String(jsonContent.type) === "MULTI_PHASE" &&
    String(jsonContent.state) === "AWAITING_CONFIRMATION") {
  awaitingConfirmation = true
  awaitingMsgId = turnMsgId || null
  await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
    message: "MULTI_PHASE AWAITING CONFIRMATION — Task calls blocked until the user replies",
    extra: { agent: currentAgent, msgId: turnMsgId } } })
}
// v7: CANCELLED — defensive disarm (normally already cleared by the new messageID)
if (currentAgent === "orchestrator" && String(jsonContent?.state) === "CANCELLED") {
  awaitingConfirmation = false; awaitingMsgId = null
}
```

**3.6.2 — Сброс** (в начале primary-ветки message.updated, после turn-boundary tracker :539–543):

```ts
// v7: confirmation gate clearing. (a) explicit user-role message (role pattern of
// :1016); (b) FALLBACK — any NEW assistant messageID: the primary only wakes on
// user input or Task completion, and Task is blocked while awaiting ⇒ a new
// assistant turn implies the user replied (robust even if user messages never
// reach message.updated). Same-messageID Task calls stay blocked (3.6.3).
if (awaitingConfirmation) {
  const gateRole = String((message as any).role || (message as any).info?.role || "assistant")
  if (gateRole === "user") {
    awaitingConfirmation = false; awaitingMsgId = null
    await client.app.log({ body: { service: "workflow-enforcement", level: "info",
      message: "USER RESPONSE RECEIVED — confirmation gate cleared" } })
  } else if (turnMsgId && turnMsgId !== awaitingMsgId) {
    awaitingConfirmation = false; awaitingMsgId = null
    await client.app.log({ body: { service: "workflow-enforcement", level: "info",
      message: "NEW ASSISTANT TURN after AWAITING — user reply implied (turn-based guarantee); gate cleared" } })
  }
}
```

**3.6.3 — Гейт** (в `tool.execute.before`, СРАЗУ после unified gate 9.0в :1105–1138):

```ts
// v7 (Multi-Phase MVP): CONFIRMATION GATE — direct throw (blocks the call itself).
// Scope: Task only (read/glob/grep stay legal — re-planning may need a
// classification read). Same-turn violation: the AWAITING JSON and a Task call
// in one message share the messageID → the gate is still armed.
if (awaitingConfirmation && currentAgent === "orchestrator" && input.tool === "task") {
  await client.app.log({ body: { service: "workflow-enforcement", level: "error",
    message: "CONFIRMATION GATE — Task blocked while AWAITING_CONFIRMATION",
    extra: { agent: currentAgent, awaitingMsgId } } })
  throw new Error(`
⛔ AWAITING USER CONFIRMATION (MULTI_PHASE):
You presented a phase plan with state="AWAITING_CONFIRMATION". Do NOT dispatch any
Task until the USER replies. Your turn ended with the plan + ack line.
On the user's approval: identity line → JSON (state: null, current_phase: "P1",
pipeline = P1's chain, next_agent = pipeline[0]) → ONE Task call.
  `)
}
```

### Шаг 3.7 — validateNextAgent whitelists (:750–791, вызов :756)

Добавить два whitelist-кейса (рядом с isLoopback/isReworkSkip/isDocsHook/isSupercomplexExempt :763–775):

```ts
// (5) v7: MULTI_PHASE phase transition — next_agent = first agent of the NEW
//     phase's chain (effectiveStep points into the OLD pipeline → mismatch is structural).
const isPhaseTransitionMP = !!pState && pState.type === "MULTI_PHASE" &&
  jsonContent.type === "MULTI_PHASE" &&
  (pState.currentPhaseIdx ?? -1) >= 0 &&
  Array.isArray(jsonContent.phases) &&
  jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase) === (pState.currentPhaseIdx ?? -1) + 1 &&
  String(nextAgent) === String((Array.isArray(jsonContent.pipeline) ? jsonContent.pipeline[0] : ""))
// (6) v7: MULTI_PHASE in-phase Auto-DOCS hook — next_agent = "docs-writer" =
//     newPipeline[0] of the canonical hook chain (isDocsHook :770 keys on
//     jsonContent.type === "DOCS", which never holds for MULTI_PHASE).
const isDocsHookMP = !!pState && pState.type === "MULTI_PHASE" &&
  jsonContent.type === "MULTI_PHASE" &&
  JSON.stringify(jsonContent.pipeline ?? null) === JSON.stringify(DOCS_HOOK_CHAIN) &&
  String(nextAgent) === "docs-writer" &&
  (pState.currentStep >= pState.pipeline.length - 1)   // hook fires after the phase's final step
```

Включить в условие :776: `if (!(isLoopback || isReworkSkip || isDocsHook || isSupercomplexExempt || isPhaseTransitionMP || isDocsHookMP))` + в `extra.whitelisted` :787. Также `isSupercomplexExempt` (:774–775) расширить фазовой сложностью: `|| (jsonContent.type === "MULTI_PHASE" && String(resolveCurrentPhase(jsonContent)?.complexity) === "SUPERCOMPLEX")`.

**Проверка существующих кейсов под MULTI_PHASE (не ломать):**
- within-phase rework loopback → `isLoopback` (pipeline unchanged path) ✓;
- DECOMPOSITION Turn B внутри фазы (next=dev-planner, effectiveStep=1, slice(0,1) нового pipeline содержит dev-planner) → `isLoopback` ✓;
- BUGFIX continuation внутри фазы (next=worker/plan-bug после triage; эффективный шаг 1, новый pipeline ["bugfix-triage","worker","utility"], slice(0,1)=["bugfix-triage"] НЕ содержит "worker" → isLoopback FALSE!) → **добавить кейс (7):**

```ts
// (7) v7: MULTI_PHASE in-phase BUGFIX continuation — same phase, prev pipeline
//     ["bugfix-triage"], new pipeline is a BUGFIX variant, next_agent = newPipeline[1].
const isBugfixContMP = !!pState && pState.type === "MULTI_PHASE" &&
  jsonContent.type === "MULTI_PHASE" &&
  (pState.currentPhaseIdx ?? -1) === (Array.isArray(jsonContent.phases)
    ? jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase) : -2) &&
  JSON.stringify(pState.pipeline) === JSON.stringify(["bugfix-triage"]) &&
  String(nextAgent) === String((jsonContent.pipeline ?? [])[1] ?? "")
```

(Сегодня single-phase BUGFIX continuation проходит потому, что continuation-ход несёт `type: "BUGFIX"` и state блок :873 обрабатывает мутацию до next_agent-гейта… фактически next_agent-валидация :750 идёт ДО state-блока; в single-phase continuation isLoopback: effectiveStep=1, pipeline новый ["bugfix-triage","worker","utility"], slice(0,1)=["bugfix-triage"], next="worker" → FALSE… но `jsonContent.type === "BUGFIX"`… Кейс (7) закрывает multi-phase вариант явно; для single-phase ничего не меняется — существующее поведение сохраняется как есть.)

### Шаг 3.8 — validateJSONOutput: conditional fields (:2038–2123)

После блока required fields (:2043–2048):

```ts
// v7: MULTI_PHASE conditional requirements (research §7.3-1: required iff type=MULTI_PHASE)
if (agent === "orchestrator" && String(json.type) === "MULTI_PHASE") {
  if (!("phases" in json)) missingFields.push("phases")
  if (!("current_phase" in json)) missingFields.push("current_phase")
  if (!Array.isArray(json.phases)) {
    errors.push(`Invalid phases: expected array`)
  } else {
    const structErr = validatePhasesStructure(json.phases, json.state != null ? String(json.state) : null)
    if (structErr) errors.push(structErr)
  }
  const mpState = json.state != null ? String(json.state) : null
  if (mpState === "AWAITING_CONFIRMATION" || mpState === "CANCELLED") {
    if (json.current_phase != null) errors.push(`state=${mpState} requires current_phase=null`)
  } else {
    if (json.current_phase == null) errors.push(`MULTI_PHASE executing turn requires current_phase`)
  }
}
// v7: state is MULTI_PHASE-only for orchestrator
if (agent === "orchestrator" && json.state != null && String(json.type) !== "MULTI_PHASE") {
  errors.push(`state field is only valid with type=MULTI_PHASE (got type=${json.type})`)
}
```

### Шаг 3.9 — Ack regex (:948–957, warn-only)

Обновить паттерн (добавить опциональный фазовый префикс + 2 новые формы; фаза 16 комментария — перечислить 8+ вариантов):

```ts
const ackPattern = /^→ (?:(?:PHASE \d+\/\d+\s*\([^)]*\)(?:,\s*)?)?(?:(?:STEP \d+\/\d+\s*(?:\([^)]*\))?\s*:\s*)?DELEGATED to [\w-]+(?:\s*\(step [^)]*\)| for: .+)?|PHASE \d+\/\d+\s*\([^)]*\):\s*[A-Z+]+|PHASE PLAN AWAITING CONFIRMATION \(\d+ phases?\)|DECOMPOSITION requested from [\w-]+ for: .+|rework SKIPPED \(.+\)|SUPERCOMPLEX steps \(\d+\):.*\(source: .+\)))\s*$/m
```

Примечание: AWAITING-ход имеет `next_agent: null` → ack-audit (:948) пропускается — форма `PHASE PLAN AWAITING CONFIRMATION` добавлена на вырост (audit scope может расшириться); warn-only ⇒ дрейф не блокирует.

### Шаг 3.10 — Gate 9.0в (:1105–1138)

Без изменений (новые флаги не вводятся в deferred-набор: confirmation gate — DIRECT throw 3.6.3; illegal transition использует существующий `pipelineImmutable`).

---

## Phase 4: Testing

### Шаг 4.1 — Расширение harness (`plugins/test-workflow-enforcement.mjs`, repo-only)

Текущий harness (165 строк) симулирует только `session.created` + `tool.execute.before/after` (`lockSession` :67–71, `tryTool` :73–80). Добавить хелперы симуляции `message.updated`:

```js
// v7 helpers — message.updated simulation
let msgSeq = 0
async function sendMessage(role, content) {
  const id = `m${++msgSeq}`
  await plugin.event({ event: { type: 'message.updated', properties: { message: { id, role, content } } } })
  return id
}
function orchMsg(jsonObj, { identity = true, ack = '→ DELEGATED to x for: y' } = {}) {
  return (identity ? '✓ IDENTITY VERIFIED: I am orchestrator (Conductor). I am NOT plankestrator.\n' : '') +
    '```json\n' + JSON.stringify(jsonObj) + '\n```\n' + ack
}
function tryTask(subagent) { return tryTool('task', { subagent_type: subagent, description: 'd', prompt: 'p' }) }
```

Важно: candidate-2 harness резолвит **LIVE** плагин (`~/.config/opencode/plugins/workflow-enforcement.ts`), candidate-3 — repo. Прогоны:
- против live (default): `node plugins\test-workflow-enforcement.mjs` — после правок live;
- против repo (mirror check): `$env:WORKFLOW_PLUGIN='P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts'; node plugins\test-workflow-enforcement.mjs` — после `config-sync --save` (идентичность копий).

Перед каждым сценарием — `lockSession('orchestrator')` (сброс состояния плагина через session.created).

### Шаг 4.2 — Новые тесты (T9–T26)

| # | Сценарий | Симуляция | Assert |
|---|----------|-----------|--------|
| T9 | Confirmation gate: same-turn Task после AWAITING | AWAITING JSON (валидный, phases 2) → `tryTask('bugfix-triage')` | `{ok:false}` + message содержит «AWAITING USER CONFIRMATION»; в логах «Task calls blocked until the user replies» |
| T10 | Gate cleared user-сообщением | T9 → `sendMessage('user','да')` → новый assistant ход (P1 JSON) → `tryTask('bugfix-triage')` | `{ok:true}`; лог «USER RESPONSE RECEIVED» |
| T10b | Gate fallback: новый assistant messageID без user-role | AWAITING (msgId A) → assistant JSON (msgId B, executing) → `tryTask` | `{ok:true}`; лог «user reply implied» |
| T11 | AWAITING с type≠MULTI_PHASE → invalid | `{type:"DEV", state:"AWAITING_CONFIRMATION", …}` | `{ok:false}` на следующем tool; лог INVALID JSON («state field is only valid with type=MULTI_PHASE») |
| T12 | Executing-ход MULTI_PHASE: per-phase валидация | confirm turn: phases [P1 BUGFIX, P2 DEV], current_phase P1, pipeline ["bugfix-triage"] | `{ok:true}`; нет PIPELINE VALIDATION FAILED |
| T13 | In-phase BUGFIX continuation | T12 → TRIAGE JSON ход: pipeline ["bugfix-triage","worker","utility"], next worker | `{ok:true}`; лог «MP-2» |
| T14 | **Provisional trap fixed**: нелегальная замена pipeline внутри frozen-фазы | phases [P1 DEV COMPLEX, P2 …], P1 executing (row 5) → ход: pipeline ["worker","utility"] (подмена), current_phase P1 | `{ok:false}`; лог «PIPELINE IMMUTABLE (MULTI_PHASE)» (F-4 НЕ срабатывает) |
| T15 | Legal phase transition | P1 завершён (utility dispatched) → ход: current_phase P2, pipeline = row P2, phases identical | `{ok:true}`; лог «MP-5 phase transition» |
| T15b | **Final turn clean** (terminal-shape внутри MULTI_PHASE ветки) | после завершения последней фазы — ход: `state: null`, `pipeline: []`, `next_agent: null`, `current_phase` = id последней фазы, phases без изменений → `tryTask` не вызывается (next_agent null) | НЕТ deferred-флагов (pipelineMismatch/invalidJSON) в логах; ход валиден |
| T16 | Transition-skip (P1→P3) запрещён | как T15 но current_phase P3 | `{ok:false}`; PIPELINE IMMUTABLE (MULTI_PHASE) |
| T17 | Phases tampering на transition | T15 + изменён goal/type P2 | `{ok:false}`; phasesStableOrRefined=false → IMMUTABLE |
| T18 | Структурные нарушения phases | (a) 4 фазы; (b) дубль id; (c) depends_on=[P2] у P1 (forward ref); (d) 2 SUPERCOMPLEX; (e) depends_on=[] у P2 (два корня) | каждый → `{ok:false}` на следующем tool; invalidJSON/pipelineMismatch в логах с текстом ошибки |
| T19 | CANCELLED shape | AWAITING → user «отмена» → ход {state:"CANCELLED", pipeline:[], next_agent:null, current_phase:null} → `tryTask` | ход валиден (нет флагов); Task после CANCELLED… гейт снят, но next_agent null — отдельный assert: нет DEFERRED VIOLATION в логах |
| T20 | In-phase Auto-DOCS hook | P1 BUGFIX (SIMPLE continuation, utility dispatched) → ход: pipeline ["docs-writer","utility"], next docs-writer, current_phase P1 | `{ok:true}`; лог «MP-4» |
| T21 | **blockerStop reset** (edge case #2) | в P1: 3 subagent-blocker JSON (severity blocker ×3, depth-симуляция через сообщения SEVERITY_AGENTS при activeTaskDepth>0 — потребуется helper `sendSubagentReviewer()`; либо прямая симуляция message.updated с role assistant от dev-reviewer… ограничение harness: subagent-ветка требует activeTaskDepth>0, который ставится tool.execute.before(task)+after — использовать tryTask/tryToolAfter пару) → blockerStop=true → gate блокирует → transition-ход MP-5 → `tryTask` | до transition: `{ok:false}` «BLOCKER STOP»; после: `{ok:true}`; лог «BLOCKERSTOP RESET» |
| T22 | Phase refinement once | P2 DEV complexity null: ход A pipeline ["dev-planner"] (DECOMPOSITION, current P2) → ход B plan_source DECOMPOSITION, phases[P2].complexity="COMPLEX", pipeline row 5 → ход C: повторный refinement complexity="SIMPLE" | A,B `{ok:true}`; C `{ok:false}` (второй refinement → phasesStableOrRefined false) |
| T23 | SUPERCOMPLEX phase — log-only паритет | phases [P1 DEV SUPERCOMPLEX plan_exists true, P2 …]; per-step re-emission row-6 массива | `{ok:true}` (MP-6/F-11 exempt), warn-логи |
| T24 | Ack audit: новые формы НЕ дают warn | ходы с ack `→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: …`, `→ PHASE 1/2 (P1), STEP 2/5 (S-2): DELEGATED to dev-professor` | в логах НЕТ «ACK FORMAT INVALID» |
| T25 | Resume в новой сессии | `lockSession('orchestrator')` (сброс) → Turn1 JSON: current_phase P2, pipeline row P2, phases те же | `{ok:true}`; warn «MULTI_PHASE RESUME DETECTED» |
| T26 | Single-phase регрессия | полный прогон существующих сценариев: BUGFIX Turn1+continuation, DECOMPOSITION A/B, Auto-DOCS hook (type DOCS), nit-skip | все `{ok:true}`, поведение идентично pre-v7 |

**Регрессия:** существующие T1–T8 harness — зелёные без изменений.

### Шаг 4.3 — Проверка видимости user-role сообщений (V-pilot-1)

Эксперимент в живой сессии: AWAITING-ход → ответ пользователя → проверить логи opencode (`~/.local/share/opencode/log/`): появилось ли «USER RESPONSE RECEIVED» (role=user виден) или «NEW ASSISTANT TURN … implied» (fallback). Оба пути легальны (резoлюция #10); результат зафиксировать в CHANGELOG/секции Limitations — если user-role НЕ виден, это постоянное поведение, fallback — основной механизм.

### Шаг 4.4 — Пилотные сценарии (живые сессии, после restart)

| # | Запрос | Ожидание |
|---|--------|----------|
| S1 | «Auth middleware падает с race condition — исправь, и сразу добавь refresh-токены» | T0 YES → AWAITING (2 фазы) → «да» → P1 BUGFIX (triage→continuation) → barrier+PHASE_STATE.md → P2 DEV (Q1–Q5 с учётом конверта) → final summary по 2 фазам |
| S2 | «Исправь баг с авторизацией и обнови README» | Анти-триггер: single-phase BUGFIX (+hook при requires_docs_update); НЕТ AWAITING |
| S3 | S1 + ответ «измени: фичу делай SIMPLE» | Edit-round: повторный AWAITING с phases[P2].complexity=SIMPLE → «да» → старт |
| S4 | S1 + ответ «отмена» | CANCELLED JSON, ноль Task, резюме предложенного |
| S5 | «1. Настрой CI github-actions. 2. Добавь unit-тесты для X. 3. Задеплой» | 3 фазы DEVOPS+DEV+DEVOPS; повтор типа допустим; конверты передаются (имя workflow P1→P2, статус тестов P2→P3) |
| S6 | «Исправь баг X и добавь фичу Y, без подтверждений — делай сразу» | Auto-approve: план информативно + немедленный старт P1 (без AWAITING-хода) |
| S7 (негатив) | «Составь план рефакторинга и реализуй его» | T0 scope-guard: plan-deliverable → OUT OF SCOPE (type null), НЕ multi-phase |

Критерии: нет WORKFLOW VIOLATION в логах; ack-форматы без warn-дрейфа; PHASE_STATE.md содержит секции всех utility-терминированных фаз; конверты в Task prompts фаз (проверить в storage/session_diff).

### Шаг 4.5 — Нагрузочное наблюдение (телеметрия Stage 2)

В пилотных сессиях S1/S5 зафиксировать: длину сессии (число ходов), расход контекста primary (субъективно: деградация ack/JSON к концу цепочки). Данные — в `RESEARCH_MULTI_PHASE_PIPELINES.md` §9.4 follow-up (решение о summarizer между фазами).

---

## Phase 5: Documentation & Deployment

### Шаг 5.1 — CHANGELOG.md ([Unreleased] → Added)

Draft entry:

```markdown
- **Multi-Phase Pipelines MVP (source: RESEARCH_MULTI_PHASE_PIPELINES.md; plan: PLAN_MULTI_PHASE_PIPELINES.md; backup: backup/2026-10-01_multi_phase/)**: последовательные фазы (2–3, линейная цепочка) для mixed-intent запросов — композиция существующих строк PIPELINE TABLE, ноль новых агентов. Канон: ARCHITECTURE.md — T0 в Type Selection Tree + mixed-intent rewording («NEVER split SILENTLY» — разбиение только через MULTI_PHASE + user confirmation) + новая §2 «Multi-Phase Pipelines» + §3 Multi-Phase Fields (state/phases/current_phase) + Auto-DOCS dedup (docs_deferred_to) + enforcement gates; orchestrator.md (mirror, same commit) — секция MULTI-PHASE PIPELINES (Stage 0–5: T0, AWAITING_CONFIRMATION, edit ≤2 rounds fail-closed, phase barrier, fail-fast, resume через PHASE_STATE.md), JSON FORMAT +state/phases/current_phase, Examples 13–16, PROHIBITIONS +4; utility.md — PHASE_STATE.md scribe (bash append verbatim, permissions unchanged). Plugin v7: VALID_VALUES +MULTI_PHASE/state; validatePipeline per-phase (ключ type-complexity-plan_exists фазы, fail-closed); provisional-trap fix (MULTI_PHASE не provisional — F-4 отключён, whitelist MP-1..MP-6); confirmation gate (DIRECT throw на Task в AWAITING-ходе; clear: user-role ИЛИ новый assistant messageID — turn-based fallback); blockerStop reset на legal phase transition (scoped); validateNextAgent +isPhaseTransitionMP/isDocsHookMP/isBugfixContMP; ack regex +PHASE-формы (warn-only). Tests: harness +message.updated simulation, T9–T26 (confirmation gate, per-phase validation, provisional trap, transitions, tamper, structural, hook, blockerStop reset, refinement-once, resume, single-phase regression). Stage 2 backlog: continue_on_error, DAG depends_on, 4 phases, summarizer telemetry. Restart required (new sessions only).
```

### Шаг 5.2 — Sync + integrity

1. `config-sync --save` (live→repo: `agents/orchestrator.md`, `agents/utility.md`, `plugins/workflow-enforcement.ts`).
2. `integrity-check` (5 sync-пар; routing/счётчики не менялись — должен пройти).
3. Прогон harness против repo-копии (`WORKFLOW_PLUGIN` = repo path) — идентичность зеркала.
4. Smoke `pipeline-visualize` (`.opencode/skills/pipeline-visualize/scripts/visualize.py:39` парсит SUPERCOMPLEX/таблицу): мета-правило добавлено ТЕКСТОМ после таблицы, новых строк нет — проверить, что парсер не сломан; если сломан — поправить скрипт скилла (repo-only, вне sync).

### Шаг 5.3 — Коммит (delegate)

**Один атомарный коммит** (mirror-правило ARCHITECTURE.md:405/:427 + неразделимость промпт/плагин): `ARCHITECTURE.md`, `agents/orchestrator.md`, `agents/utility.md`, `plugins/workflow-enforcement.ts`, `plugins/test-workflow-enforcement.mjs`, `CHANGELOG.md`, `PLAN_MULTI_PHASE_PIPELINES.md`, `backup/2026-10-01_multi_phase/`. **Выполняет агент `git-commit` через Task tool (global hard rule — прямые commit/push запрещены); push только по явной просьбе пользователя.**

### Шаг 5.4 — Restart + announcement

Restart opencode (плагин и промпты подхватываются только новыми сессиями — конвенция «Restart required»). Пилот S1–S7 (Phase 4.4). Опционально: обновление `.serena/memories/project-overview.md` (упоминает SUPERCOMPLEX :24 — добавить строку о MULTI_PHASE).

---

## Verification Checklist

**Канон (Phase 1):**
- [ ] V-1: `ARCHITECTURE.md` mixed-intent (:438) переформулирован; «NEVER split … SILENTLY» + отсылка к T0/Multi-Phase
- [ ] V-2: T0-строка присутствует в ОБЕИХ деревьях (ARCHITECTURE.md + orchestrator.md) с идентичной формулировкой и scope-guard
- [ ] V-3: Новая §2-секция Multi-Phase содержит: meta-rule (2–3 фазы), confirmation protocol, envelope spec, PHASE_STATE.md + utility-scribe, fail-fast, SUPERCOMPLEX disambiguation, edge-case таблицу (включая Auto-DOCS dedup и resume)
- [ ] V-4: §3: orchestrator type += MULTI_PHASE; Multi-Phase Fields subsection; File-Pointer Fields += PHASE_STATE.md
- [ ] V-5: enforcement gates table: 3 новые строки + расширение исключений pipeline-changed
- [ ] V-6: В ARCHITECTURE.md/orchestrator.md НЕТ заголовков, совпадающих с FORBIDDEN_VOCAB («## PLAN», «# Implementation Plan») и SELF_WORK_MARKERS — выбранный заголовок «## MULTI-PHASE PLAN» проверен substring-поиском

**Оркестратор (Phase 2):**
- [ ] V-7: PIPELINE TABLE — новых строк НЕТ (только мета-правило); 8 строк без изменений
- [ ] V-8: Секция MULTI-PHASE PIPELINES: Stage 0–5; ack-форматы; AWAITING/CANCELLED shapes; auto-approve override; edit ≤2 rounds fail-closed
- [ ] V-9: JSON FORMAT расширен (state/phases/current_phase — только MULTI_PHASE); подтверждение БЕЗ tool `question` (`question: deny` не тронут — ARCHITECTURE.md:281 без изменений)
- [ ] V-10: Examples 13–16 добавлены; Example 11 (mixed-intent README) НЕ противоречит новым (анти-триггер сохранён)
- [ ] V-11: PROHIBITIONS: исключения pipeline-changes + 4 новых пункта; utility.md: scribe-секция (append-only, bash, permissions не менялись)

**Плагин (Phase 3):**
- [ ] V-12: `VALID_VALUES.orchestrator.type` += MULTI_PHASE; `state` enum; plankestrator НЕ затронут
- [ ] V-13: **provisional fix**: `provisional = complexity==null && type!=="MULTI_PHASE"` — T14 доказывает (F-4 не даёт произвольную замену)
- [ ] V-14: **validatePipeline по фазовому ключу** `${phase.type}-${phase.complexity}-${phase.plan_exists}` (+DOCS-any, +variants) — fail-closed сохранён (T18, unknown key → ошибка)
- [ ] V-15: **AWAITING ветка ДО terminal exemption** (:1940) — AWAITING-ход отличим от финального; финальный ход (state null, pipeline []) проходит terminal-shape early return ВНУТРИ ветки (T15b — нет ложного pipelineMismatch)
- [ ] V-16: **Confirmation gate**: same-turn Task blocked (T9); clear по user-role (T10) И по новому assistant messageID (T10b)
- [ ] V-17: **blockerStop reset ТОЛЬКО в MP-5** (T21); single-phase семантика «cumulative, only session.created» не изменена (регрессия T1–T8 + code review диффа :474–499)
- [ ] V-18: Mutation whitelist MP-1..MP-6 закрытый (нелегальные мутации → PIPELINE IMMUTABLE с multi-phase detail); phases[]/currentPhaseIdx хранятся в pipelineState
- [ ] V-19: validateNextAgent: isPhaseTransitionMP + isDocsHookMP + isBugfixContMP; существующие 4 whitelist-кейса не изменены
- [ ] V-20: Ack regex: новые формы не дают warn (T24); старые 6 форм работают (регрессия)
- [ ] V-21: `session.created` reset включает awaitingConfirmation/awaitingMsgId; parentID-guard не затронут

**Тесты (Phase 4):**
- [ ] V-22: T1–T8 (регрессия) + T9–T26 — все зелёны против LIVE и против REPO копии (`WORKFLOW_PLUGIN`)
- [ ] V-23: Пилоты S1–S7 пройдены в живых сессиях; V-pilot-1 (user-role видимость) зафиксирован
- [ ] V-24: PHASE_STATE.md создаётся/дописывается корректно (append-only, заголовок, секции фаз); конверты в Task prompts — «pointer, not transcript» (summary ≤3 предложений, facts ≤10 ключей)

**Документация/деплой (Phase 5):**
- [ ] V-25: CHANGELOG entry; config-sync --save; integrity-check зелёный; pipeline-visualize smoke
- [ ] V-26: Один коммит через агента git-commit (mirror-правило соблюдено: ARCHITECTURE.md + orchestrator.md вместе); restart выполнен

---

## Risks & Mitigations

| # | Риск | Вероятность | Митигция |
|---|------|-------------|----------|
| R1 | **opencode не доставляет user-role сообщения в message.updated** → confirmation gate не снимается | Средняя | Fallback (резoлюция #10, шаг 3.6.2b): сброс по новому assistant messageID — turn-based гарантия (primary просыпается только от user-ввода или Task-завершения; Task заблокирован ⇒ новый ход = пользователь ответил). Проверка V-pilot-1 (Phase 4.3) |
| R2 | **Model behavior (QWEN3.7-plus)**: ошибки T0-классификации (false-positive fan-out), дрейф ack/JSON на длинных multi-phase сессиях | Высокая | Default single-phase + строгие анти-триггеры + Examples 15/16; fail-closed плагин (структурная валидация phases); ack warn-only (дрейф виден в логах, не блокирует); пилот S1–S7 до объявления стабильности; телеметрия (Phase 4.5) |
| R3 | **Промпт/плагин рассинхрон при частичном деплое** (промпт обновлён, плагин нет → MULTI_PHASE ходы блокируются fail-closed) | Низкая | Атомарный changeset: один коммит + restart (порядок развёртывания в Executive Summary); fail-closed = безопасный отказ, не порча данных |
| R4 | **Регрессия single-phase** (mutation whitelist, provisional, ack regex задевают существующие сценарии) | Средняя | Ветка MULTI_PHASE изолирована условием `prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE"`; single-phase whitelist (F-4/F-11/F-12) без изменений; T26 + T1–T8 регрессия; blockerStop reset строго scoped MP-5 |
| R5 | **Длина сессии/контекст primary** на 3 полных цепочках с ревьюерами | Средняя | MVP лимит 3 (MULTI_PHASE_MAX); envelope small-data (≤3 предложения, ≤10 фактов) + PHASE_STATE.md как внешний журнал («pointer, not transcript»); телеметрия Phase 4.5 → Stage 2 summarizer |
| R6 | **Хвостовая потеря PHASE_STATE.md** (цепочка кончается DEVOPS-фазой — нет utility-писца) | Низкая | Задокументированное MVP-ограничение (шаг 1.4-п.9, 2.2 Stage 3-5): финальный summary перечисляет результаты текстом; resume таких фаз — через summary + artifacts; Stage 2: devops-reviewer-scribe или flush-агент |
| R7 | **Auto-DOCS dedup — prompt-level** (плагин не видит `requires_docs_update` и не может принудить дедупликацию) | Низкая | Механическое правило в промпте (шаг 1.6/2.2 Stage 3-6) + поле `docs_deferred_to` в конверте (аудируемо в PHASE_STATE.md); плагин гарантирует лишь легальность самой hook-цепочки (MP-4) |
| R8 | **Terminal exemption проглатывает AWAITING-ход** (shape-based :1940) — неотличимость от финала | Устранена дизайном | Явная AWAITING/CANCELLED ветка validatePipeline ДО exemption (шаг 3.4, V-15); state обязательный для пустого pipeline при MULTI_PHASE (шаг 3.8) |
| R9 | **provisional ловушка** (F-4 разрешает любую замену весь сеанс) | Устранена дизайном | Шаг 3.5.1 (`type !== "MULTI_PHASE"`) + закрытый whitelist MP-1..MP-6; тест T14 |
| R10 | **blockerStop навсегда блокирует resume в той же сессии** | Устранена дизайном | Шаг 3.5.3 (reset в MP-5) + промпт-рекомендация «resume = новая сессия» (Stage 5); тест T21 |
| R11 | **Live/repo drift** (правки в live, зеркало устарело) | Низкая | Порядок: live-first → config-sync --save → harness с WORKFLOW_PLUGIN=repo (V-22) → integrity-check (V-25); коммит одного снапшота |
| R12 | **Harness-симуляция subagent-ветки** (T21 требует activeTaskDepth>0 для blocker-счёта) | Средняя | Использовать пару tryTask (depth+1) → sendMessage (reviewer JSON) → tryToolAfter (depth-1); если глубина не балансируется в harness — деградировать T21 до интеграционной проверки в пилоте S-доп (3 blocker в живой сессии) с фиксацией в логах |
| R13 | **Forbidden-vocab/self-work false-positive** на MULTI-PHASE PLAN отображении | Низкая | Заголовок «## MULTI-PHASE PLAN» проверен: не содержит «## PLAN» (между «##» и «PLAN» есть «MULTI-PHASE »), не self-work маркер; V-6 substring-проверка до коммита |
| R14 | **Семантика `pipeline` при фазовом переходе** (открытый вопрос research §9.4: перезапись vs аккумуляция) | Принято решение | Перезапись (pipeline = текущая фаза, §7.2) — снимает ambiguity RESEARCH_PIPELINE_ENHANCEMENTS.md:71 для нового механизма; maxStepReached/reworkCount сбрасываются на MP-5 (существующий reset-блок :887–894) |

---

## Оценка трудоёмкости

| Phase | Содержание | Оценка |
|-------|-----------|--------|
| 1 | ARCHITECTURE.md: 10 шагов, ~150 новых строк канона | 2–3 ч |
| 2 | orchestrator.md (~200 строк: секция MULTI-PHASE + 4 example + правки 6 секций) + utility.md (~10 строк) | 3–4 ч |
| 3 | workflow-enforcement.ts: ~10 точечных изменений, ~250 строк кода (3 хелпера, ветка validatePipeline, whitelist MP, confirmation gate, regex) | 5–7 ч |
| 4 | Harness-хелперы + 20 тестов (T9–T26) + пилоты S1–S7 в живых сессиях | 4–6 ч |
| 5 | CHANGELOG, sync, integrity, коммит (git-commit agent), restart | 1–2 ч |
| **Итого** | | **~15–22 ч (2–3 рабочих дня)** |

**Критический путь:** Phase 3 (плагин) — наиболее рискованная часть (R4/R9/R10); рекомендуется порядок 1→2→3 с немедленным прогоном T1–T8 после каждого изменения плагина (регрессия до новых тестов).

**Точки невозврата/decision points для ревьюера:**
1. Резолюция #8 (utility = писец PHASE_STATE.md через bash-append) — альтернатива: отложить PHASE_STATE.md в Stage 2 (конверты только в Task prompts), но тогда resume (§6.1) не работает — принят вариант с писцом.
2. Резолюция #9 (MULTI_PHASE_MAX=3) — устранение разночтения research §7.3/§9.1; Stage 2 поднимет до 4.
3. Резолюция #10 (confirmation gate fallback по messageID) — если ревьюер сочтёт fallback недостаточным, альтернатива: блокировать ВСЕ tool-вызовы (не только Task) пока awaiting — строже, но ломает легальный classification read при edit-раундах.
