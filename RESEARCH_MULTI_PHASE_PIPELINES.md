# Исследование: Multi-Phase Pipelines для оркестратора

**Дата:** 2026-10-01
**Статус:** Research (исследование, не план реализации)
**Scope:** возможность выполнения нескольких пайплайнов последовательно для одной задачи пользователя

---

## 1. Executive Summary

### Суть

Сейчас оркестратор классифицирует запрос ровно в **один** тип (`BUGFIX | DEVOPS | DEV | DOCS`) и выполняет **один** пайплайн. Жёсткое правило mixed-intent звучит так:

> «**Mixed-intent priority:** BUGFIX > DEV > DOCS > DEVOPS. Pick exactly ONE row — the primary deliverable… **NEVER split one request into two pipelines.**»
> — `ARCHITECTURE.md:438`, `agents/orchestrator.md:250`, `PLAN_PROMPT_ENHANCEMENTS.md:212`

Второстепенные намерения сегодня обрабатываются двумя обходными механизмами:
1. **Auto-DOCS hook** — единственный существующий «второй пайплайн»: после финального `utility` флаг `requires_docs_update: true` запускает `docs-writer → utility` (`ARCHITECTURE.md:543-564`).
2. **Follow-up в summary** — деплой после фикса просто упоминается в финальном отчёте как «следующий запрос», пользователь должен попросить отдельно.

### Главный вывод

Multi-Phase Pipelines — **реализуемая и архитектурно совместимая** эволюция, потому что:

- **SUPERCOMPLEX уже является multi-phase системой в зародыше**: полная цепочка `dev-planner → … → utility` выполняется отдельно для каждого шага плана (`ARCHITECTURE.md:486-523`). Механика итерации по шагам, механические чтения полей (`steps`, `TRIAGE_RESULT`), ack-форматы `→ STEP <i>/<total>` — всё это уже существует и может быть обобщено с «шагов одного DEV-плана» на «фазы разных типов».
- **Плагин уже хранит pipeline-state** (`pipelineState: Map<agent, {pipeline, currentStep, provisional, type}>` — `workflow-enforcement.ts:172`) и поддерживает whitelist мутаций пайплайна (`:875-881`). Расширение до phase-level state — инкрементальное, а не революционное изменение.
- **Паттерн передачи контекста файлами фиксированных имён** (`bug_plan.md`, `dev_plan.md`, `docs_plan.md` + JSON-конверты, «pointer, not transcript») напрямую масштабируется на межфазовую передачу.

### Главные риски

1. **Запрет `question: deny` для primaries** (`ARCHITECTURE.md:281`) — фаза подтверждения пользователем не может использовать tool `question`; нужен дизайн через обычный ответ пользователю (паттерн Claude Code Plan Mode / `ExitPlanMode`).
2. **Pipeline immutability** — текущий запрет изменений пайплайна после Turn 1 (`orchestrator.md:348`) имеет закрытый whitelist исключений; multi-phase добавляет в него новый класс мутаций (phase transition), который нужно формализовать, иначе плагин будет бросать `PIPELINE IMMUTABLE`.
3. **Размывание single-responsibility классификации** — риск, что модель начнёт объявлять multi-phase там, где достаточно single-phase + hook. Нужны строгие триггеры и default = single-phase.
4. **Открытый вопрос из прошлого research** (`RESEARCH_PIPELINE_ENHANCEMENTS.md:71`): семантика поля `pipeline` для итеративных пайплайнов до сих пор не формализована — multi-phase обостряет эту проблему.

### Рекомендация в двух словах

Внедрять **поэтапно**: сначала «линейная цепочка фаз без ветвлений» с обязательной фазой подтверждения, композиция существующих строк PIPELINE TABLE без новых агентов. Полный DAG с условными переходами — отложить. Подробности — §9.

---

## 2. Concept Overview

### 2.1 Определение

**Multi-Phase Pipeline** — выполнение последовательности фаз для одной задачи, где:

- **Фаза** = один существующий пайплайн из PIPELINE TABLE (строка 1–8) со своими `type`, `complexity`, `plan_exists`.
- **Фазы упорядочены** и исполняются последовательно (одна фаза за раз; параллельные волны внутри субагентов не затрагиваются — scope rule `ARCHITECTURE.md:366`).
- **Каждая фаза производит phase result** — компактный JSON-конверт + артефакты (файлы), потребляемые следующей фазой.
- **План фаз фиксируется до старта исполнения** и подтверждается пользователем (см. §5).

```
Задача пользователя
   │
   ▼
[PHASE PLANNING] ──► План фаз: [Phase 1: BUGFIX] → [Phase 2: DEV]
   │
   ▼
[USER CONFIRMATION] ──► approve / edit / reject
   │
   ▼
Phase 1: bugfix-triage → … → utility ──► phase_result_1 (JSON + файлы)
   │
   ▼ (barrier: фаза завершена, контекст собран)
Phase 2: dev-planner → … → utility ──► phase_result_2
   │
   ▼
[FINAL SUMMARY] — сводка по всем фазам
```

### 2.2 Как разбивать задачу на фазы

Принцип: **одна фаза = один первичный deliverable одного типа**. Разбиение происходит по границам типов из Type Selection Decision Tree (T1–T6, `ARCHITECTURE.md:427-440`):

- Разные **типы deliverable** в одном запросе → разные фазы. «Исправь баг **и** добавь фичу» = BUGFIX-фаза + DEV-фаза, потому что deliverable «исправленное поведение» и «новый код» классифицируются разными ветками дерева (T3 vs T6).
- Один тип, но **разные независимые объекты** → НЕ multi-phase; это один пайплайн (или SUPERCOMPLEX, если DEV с >3 шагами). «Исправь баги A, B, C» — один BUGFIX.
- **Зависимость по данным**: фаза N+1 потребляет результат фазы N (фикс нужен до фичи, код нужен до деплоя). Это и есть оправдание последовательности.

### 2.3 Классификация каждой фазы

Каждая фаза классифицируется **существующими механизмами**, без новых правил:

1. **Тип фазы** — по дереву T1–T6, применённому к подзадаче фазы (не ко всему запросу).
2. **Сложность фазы** — существующие правила: BUGFIX → `complexity: null` + triage; DEV → Q1–Q5; DOCS → по объёму; DEVOPS → без сложности.
3. **Двухстадийные протоколы сохраняются внутри фазы**: BUGFIX-фаза начинается с `["bugfix-triage"]` + one-time continuation; DEV-фаза с неясной сложностью → DECOMPOSITION PROTOCOL внутри фазы.

Ключевое следствие: **multi-phase не вводит новых типов и не меняет Q1–Q5 / T1–T6**. Он добавляет уровень абстракции НАД ними — «классификация применяется k раз, по одному на фазу».

### 2.4 Выбор pipeline для каждой фазы

По паре `(type, complexity, plan_exists)` фазы выбирается строка существующей PIPELINE TABLE — дословно как сейчас. Multi-phase пайплайн = **конкатенация выбранных строк** с фазовыми границами:

| Phase | type | complexity | Строка | Pipeline фазы |
|-------|------|-----------|--------|----------------|
| 1 | BUGFIX | (triage) | 1 | `["bugfix-triage"] → continuation` |
| 2 | DEV | COMPLEX | 5 | `["dev-planner", "dev-professor", "advisor", "dev-reviewer", "consistency-checker", "utility"]` |

Внешние аналоги этой композиции:
- **LangGraph subgraphs-as-nodes**: каждая фаза = подграф (существующий пайплайн), родительский граф = последовательность фаз (https://docs.langchain.com/oss/python/langgraph/persistence).
- **Temporal Child Workflows**: фаза = дочерний workflow с собственной Event History; родитель ждёт завершения (https://docs.temporal.io/child-workflows).
- **GitLab CI `stages`**: фазы исполняются строго последовательно, следующая стадия стартует после завершения предыдущей (https://docs.gitlab.com/ci/jobs/job_control/).

---

## 3. Phase Classification (примеры использования)

### 3.1 BUGFIX + DEV: «Исправь баг и добавь новую фичу»

**Текущее поведение:** mixed-intent priority BUGFIX > DEV → выполняется ТОЛЬКО BUGFIX, фича теряется (упоминается максимум в summary).

**Multi-phase:**

```json
{
  "phases": [
    {"id": "P1", "type": "BUGFIX", "complexity": null, "goal": "Исправить баг <описание>", "depends_on": []},
    {"id": "P2", "type": "DEV", "complexity": null, "goal": "Добавить фичу <описание>", "depends_on": ["P1"]}
  ]
}
```

- **P1**: `bugfix-triage` → (SIMPLE: `worker, utility` | DEEP: полная DEEP-цепочка).
- **Barrier**: phase_result_1 (что исправлено, какие файлы тронуты, статус тестов).
- **P2**: классификация сложности по Q1–Q5 с учётом phase_result_1 (фича строится поверх исправленного кода) → соответствующая DEV-строка.
- **Зависимость реальная**: фича на сломанном коде бессмысленна; падение P1 должно блокировать P2 (fail-fast, см. §6).

### 3.2 DEVOPS + DEV + DEVOPS: «Настрой CI, добавь тесты, задеплой»

**Multi-phase:**

| Phase | type | Обоснование |
|-------|------|-------------|
| P1 | DEVOPS | «Настрой CI» — операции, не написание кода (T4) |
| P2 | DEV | «Добавь тесты» — новый код (T6); сложность по Q1–Q5 |
| P3 | DEVOPS | «Задеплой» — операции (T4) |

- P1: `devops-agent → devops-reviewer`.
- P2: контекст от P1 — CI-конфиг существует, тесты должны в него вписаться (имя workflow, команда запуска — передаются в phase_result_1).
- P3: контекст от P2 — тесты зелёные (результат `utility`/тестового прогона), от P1 — деплой-таргет из CI-конфига.
- Демонстрирует **повторное использование одного типа** в разных фазах — схема должна допускать `type` дубликаты с разными `id`.

### 3.3 SUPERCOMPLEX с DEVOPS внутри: «Реализуй миграцию, запусти тесты, задеплой»

Самый сложный случай — два измерения итерации (шаги плана × фазы). Два легальных толкования:

**Вариант A (рекомендуемый): SUPERCOMPLEX — это фаза, а не обёртка.**
- P1 = DEV SUPERCOMPLEX (реализация миграции, полный per-step цикл).
- P2 = DEVOPS («запусти тесты» — T4, прогон, не написание).
- P3 = DEVOPS (деплой).
- Внутри P1 существующая per-step механика не меняется. Multi-phase и SUPERCOMPLEX **композируются, а не вкладываются**: оркестратор никогда не исполняет «multi-phase внутри шага SUPERCOMPLEX» и «SUPERCOMPLEX внутри multi-phase глубже одного уровня».

**Вариант B (отклонённый): SUPERCOMPLEX как единственный multi-phase механизм** — считать DEVOPS-части шагами DEV-плана. Отклонено: шаги SUPERCOMPLEX исполняются DEV-цепочкой (dev-planner → dev-professor → …), в которую devops-agent/devops-reviewer не входят. Уточнение механизма: devops-agent ЕСТЬ в routing table orchestrator (`orchestrator.md:26`), поэтому блокировать будет не ROUTING TABLE ENFORCEMENT, а `validatePipeline` — цепочка `"DEV-SUPERCOMPLEX-true"` жёстко зафиксирована (`workflow-enforcement.ts:1892`) и не содержит devops-агентов; притянуть их «шагами» = нарушить PIPELINE TABLE.

**Правило:** `complexity: SUPERCOMPLEX` допустим только внутри одной фазы; запрос на «несколько SUPERCOMPLEX-фаз» деградирует до одной SUPERCOMPLEX-фазы + последующих не-SUPERCOMPLEX фаз.

---

## 4. Context Passing (передача контекста между фазами)

### 4.1 Что передавать

Три канала, все — развития существующих паттернов:

**Канал 1: Phase Result JSON (машинный конверт).**
Финальный агент фазы (`utility` либо последний исполнитель) уже возвращает JSON. Дополняется фазовым конвертом:

```json
{
  "phase_id": "P1",
  "phase_type": "BUGFIX",
  "status": "SUCCESS | FAILED | SKIPPED",
  "summary": "Исправлен race condition в auth middleware",
  "artifacts": ["src/auth/middleware.ts", "bug_plan.md"],
  "facts": {
    "tests": "green",
    "files_changed": 3,
    "public_api_changed": false
  },
  "blockers": []
}
```

Аналоги: **Airflow XCom** (`return_value` по умолчанию, только маленькие данные — https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/xcoms.html), **GitHub Actions `outputs`** (`$GITHUB_OUTPUT` между jobs), **ReWOO** переменные `#E1, #E2` (arXiv:2305.18323). Общий принцип всех трёх: **машиночитаемый, компактный, типизированный** конверт — не свободный текст.

**Канал 2: Файлы-артефакты фиксированных имён (уже работающий паттерн).**
`bug_plan.md`, `dev_plan.md`, `docs_plan.md` передают контекст между шагами сегодня (passed via Task prompts, not JSON fields — `ARCHITECTURE.md` §file pointers). Для межфазового состояния предлагается один агрегат:

- **`PHASE_STATE.md`** (human-readable журнал): секция на фазу — цель, что сделано, ключевые решения, артефакты. Аналог gitlab `artifacts:` + `dependencies:` и `actions/upload-artifact → download-artifact`.

Принцип **«pointer, not transcript»** сохраняется: следующая фаза получает пути и краткие факты, а не сырые логи предыдущих агентов (то же правило, что у research-writer-complex — `ARCHITECTURE.md:626`).

**Канал 3: Verbatim-передача JSON предыдущего агента (существующий turn algorithm).**
`orchestrator.md:166`: «Call Task. Pass the previous agent's JSON output verbatim». На фазовой границе первый Task фазы N+1 получает phase_result_N verbatim + явную фразу-контекст («Phase 1 (BUGFIX) завершена: <summary>. Артефакты: <список>»).

### 4.2 Формат данных: JSON vs файлы vs переменные

| Данные | Канал | Почему |
|--------|-------|--------|
| Статус фазы, счётчики, флаги (`tests: green`) | Phase Result JSON | Механическое чтение оркестратором (`orchestrator.md:169` — уже читает `requires_docs_update`, `TRIAGE_RESULT`, `steps`) |
| Планы, rationale, длинные описания | Файлы (`*_plan.md`, `PHASE_STATE.md`) | Контекстные лимиты; существующий prewalk-паттерн (`ARCHITECTURE.md:399`) |
| Список изменённых файлов, публичные API | Phase Result JSON (`artifacts`, `facts`) | Нужны для классификации следующей фазы и Auto-DOCS hook |

**Запрет:** передача больших объёмов через JSON (правило XCom: «for small data only; large values → object storage»). Порог-ориентир: summary ≤ 3 предложений, facts ≤ 10 ключей.

### 4.3 Обработка ошибок между фазами

Семантика по умолчанию — **fail-fast** (Airflow: upstream failure → downstream skipped, DAG failed; Temporal: failed child workflow фейлит родителя по умолчанию):

1. **Фаза FAILED → вся цепочка останавливается.** Следующие фазы получают статус SKIPPED, пользователю — отчёт: какая фаза упала, phase_result упавшей фазы, что можно сделать (rework уже исчерпан внутри фазы — max 3, `workflow-enforcement.ts:1473-1486`).
2. **Нет «тихого продолжения»**: запустить DEV-фичу поверх неисправленного бага — детерминированно запрещено (зависимость `depends_on` не выполнена).
3. **Опциональный per-phase флаг `continue_on_error: true`** (аналог GitHub Actions `continue-on-error`, GitLab `allow_failure: true`) — ТОЛЬКО для фаз без downstream-зависимостей и только если пользователь явно запросил в подтверждении плана. Default = false.
4. **Blocker-эскалации сохраняют семантику**: `BLOCKER STOP AFTER 3` внутри фазы (`workflow-enforcement.ts:474-499`) = FAILED фазы, а не всей сессии — но цепочка останавливается по п.1.

---

## 5. User Confirmation Phase (фаза подтверждения)

### 5.1 Архитектурная проблема

`ARCHITECTURE.md:281`: tool `question` — `❌ deny` для обоих primaries («Primary agents don't ask the user»). Значит, интерактивный диалог «вот план, подтвердите?» через tool **невозможен**. Но подтверждение можно реализовать **без tool**: оркестратор завершает ход обычным сообщением с планом фаз и ждёт следующего сообщения пользователя. Это ровно паттерн **Claude Code Plan Mode**: `ExitPlanMode` не передаёт план — пользователь читает его и отвечает approve/edit (https://code.claude.com/docs/en/permission-modes, разбор: https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/). Также аналог — **OpenAI Agents SDK interruptions**: раннер ставит выполнение на паузу и ждёт `state.approve(item)` / `state.reject(item)` (https://openai.github.io/openai-agents-python/human_in_the_loop/).

### 5.2 Протокол подтверждения

```
Turn 1: CLASSIFY → обнаружен multi-phase →
        JSON: {"agent": "orchestrator", "type": "MULTI_PHASE", "state": "AWAITING_CONFIRMATION",
               "next_agent": null, "pipeline": [], "phases": [...]}
        + человекочитаемый план фаз (таблица: # / тип / цель / пайплайн / зависимости)
        STOP — Task НЕ вызывается.

Turn 2 (ответ пользователя):
  «да / ок / поехали»            → подтверждение: старт Phase 1.
  «измени: фазу 2 сделай SIMPLE» → пересчёт затронутой фазы → повторный показ плана
                                   (лимит: max 2 раунда правок, дальше — старт или отказ).
  «отмена / не надо»             → вежливый отказ, никаких Task-вызовов, состояние сброшено.
```

Правила:
- **Показ плана**: компактная таблица (аналог env protection rules UI в GitHub Actions): id, type, goal одной строкой, pipeline-цепочка, depends_on. Без внутренних деталей агентов.
- **Изменения пользователя**: разрешены — (a) отклонить фазу (→ SKIPPED, с проверкой зависимостей), (b) понизить сложность фазы (SUPERCOMPLEX→COMPLEX), (c) переупорядочить независимые фазы, (d) отменить всё. Запрещены — новые типы агентов, пропуск mandatory-ревьюеров (dev-reviewer/consistency-checker — `orchestrator.md:350`).
- **Тишина/неоднозначный ответ** трактуется как НЕ-подтверждение (fail-closed, как `needs_approval` callable в OpenAI SDK — fails closed при malformed args).
- **Explicit request override**: если пользователь в исходном запросе явно сказал «без подтверждений, делай сразу», фаза подтверждения схлопывается в информирование (план показывается, но исполнение начинается сразу — аналог auto-approve). Default — подтверждение обязательно: multi-phase необратимо дороже single-phase, silent fan-out недопустим.

### 5.3 Отказ от подтверждения

- Полный отказ → JSON `state: "CANCELLED"`, ноль Task-вызовов, краткое резюме «что было предложено».
- Частичный отказ (убрать фазу) → пересчёт зависимостей: если отклонённая фаза имела downstream-зависимых, они тоже помечаются SKIPPED (пользователь информируется), либо пользователь выбирает исполнить их standalone.

---

## 6. Edge Cases

### 6.1 Падение одной из фаз

- **Fail-fast** (default, §4.3): цепочка останавливается, downstream → SKIPPED, отчёт пользователю.
- **Rework внутри фазы исчерпан** (max 3, `REWORK LOOP MAX 3 EXCEEDED`) → фаза FAILED → fail-fast. НЕ запускать «глобальный rework» между фазами — иначе нарушается per-stage семантика `reworkCount` (`workflow-enforcement.ts:178-182`).
- **Возобновление после падения**: пользователь пишет «продолжи с фазы P2» → оркестратор НЕ пересоздаёт план, а читает `PHASE_STATE.md`, восстанавливает phase results завершённых фаз (аналог LangGraph checkpointing по `thread_id` — https://docs.langchain.com/oss/python/langgraph/persistence) и стартует с указанной фазы. Повторное подтверждение не требуется, если план не изменился. ⚠️ Нюанс плагина: если фаза упала по BLOCKER STOP, возобновление в ТОЙ ЖЕ сессии невозможно без правки плагина — `blockerStop` является кумулятивным session-state, НЕ сбрасывается ни recovery, ни заменой pipeline, только `session.created` (`workflow-enforcement.ts:483-485`), и гейт 9.0в заблокирует следующий Task-вызов. Резолюция: либо resume = новая сессия (просто, но теряется plugin-state), либо сброс `blockerStop` при легальном phase-transition/resume-ходе (добавить в §7.3 пункт 2).

### 6.2 Пользователь хочет пропустить фазу

- На этапе подтверждения — легально (§5.2), с каскадом зависимостей.
- **Mid-flight** («фаза 1 идёт, а фазу 3 не делай») — пользователь прерывает между фазами (на фазовой границе оркестратор выводит ack `→ PHASE 2/3 …` и ждёт? Нет — ожидание между фазами **не вводится**, иначе каждая граница = лишний round-trip; пропуск mid-flight = отмена остатка цепочки командой «стоп», дальнейшие фазы не стартуют). Обоснование: barrier между фазами — структурное свойство (все Task-вызовы фазы завершены), а не точка диалога; диалог был на подтверждении плана.

### 6.3 Зависимости между фазами

- Модель — **линейная цепочка как специальный случай DAG** (та же нотация, что в `ARCHITECTURE.md:357-364` для пайплайнов). MVP: только линейная цепочка, `depends_on = [предыдущая фаза]` неявно.
- Полный DAG (фаза зависит от двух фаз, параллельные фазы) — **не в MVP**: параллельные фазы на уровне оркестратора нарушили бы «ONE Task call per turn» (`orchestrator.md:351`) и одно-агентную модель сессии. Внешний ориентир на будущее — GitLab `needs` (DAG поверх stages) и LLMCompiler (Task Fetching Unit исполняет задачи по мере готовности зависимостей — https://blog.langchain.com/planning-agents/).

### 6.4 Циклические зависимости

- **Детекция на этапе планирования**: фазы нумеруются, `depends_on` может ссылаться только на меньшие id — циклы невыразимы синтаксически (как DAG в GitHub Actions `needs`). Дополнительно — валидация плагином: `depends_on ⊆ {ранее объявленные phase id}`.
- **Псевдо-циклы** («исправь баг → добавь фичу → если сломалось, снова исправь») выражаются существующими механизмами: rework loop внутри фазы, либо пользователь явно объявляет две BUGFIX-фазы (P1, P3) — это не цикл, а повтор типа. Настоящие data-dependent циклы («повторять до зелёных тестов») — запрещены на уровне фаз: bounded iteration живёт только внутри фазы (rework max 3).

### 6.5 Прочие edge cases

| Ситуация | Резолюция |
|----------|-----------|
| Фаза оказалась single после декомпозиции (план из 1 фазы) | Деградация в обычный single-phase pipeline, без подтверждения (нет смысла) |
| Все фазы — один тип (3 DEV подряд) | Это НЕ multi-phase → SUPERCOMPLEX (per-step) или один DEV; правило §7.4 |
| Одна фаза = plan/research deliverable | OUT OF SCOPE целиком — граница с plankestrator не пересекается (`orchestrator.md:269-274`); multi-phase не смешивает primaries |
| Auto-DOCS hook внутри multi-phase | Hook срабатывает per-фаза (после каждой BUGFIX/DEV-фазы), как сейчас per-pipeline |
| requires_docs_update от фазы P1, а DOCS-фаза уже есть в плане (P3) | Hook НЕ дублируется: docs-работа идёт в явную DOCS-фазу; дедупликация по типу |

---

## 7. Integration with Existing System

### 7.1 Влияние на PIPELINE TABLE

**Композиция, не расширение.** Ни одна новая строка не добавляется: фазы ссылаются на существующие строки 1–8. В таблицу добавляется мета-правило:

> **Multi-phase:** `"phases"` — массив из 2–4 фаз; каждая фаза независимо резолвится в строку 1–8 по своим `(type, complexity, plan_exists)`. Пайплайн сессии = последовательная конкатенация цепочек фаз с фазовыми barrier-ами.

Лимит 2–4 фазы: прагматичный потолок (стоимость, длина сессии, контекст). Больше 4 фаз → рекомендация разбить на отдельные запросы.

### 7.2 Влияние на JSON-схему оркестратора

Обратно-совместимое расширение (`orchestrator.md:171-186`):

```json
{
  "agent": "orchestrator",
  "type": "MULTI_PHASE",
  "complexity": null,
  "plan_exists": null,
  "plan_source": null,
  "goal": "one sentence",
  "next_agent": "bugfix-triage",
  "pipeline": ["bugfix-triage"],
  "phases": [
    {"id": "P1", "type": "BUGFIX", "complexity": null, "plan_exists": null,
     "goal": "...", "depends_on": []},
    {"id": "P2", "type": "DEV", "complexity": "COMPLEX", "plan_exists": false,
     "goal": "...", "depends_on": ["P1"]}
  ],
  "current_phase": "P1"
}
```

- `type: "MULTI_PHASE"` — новое значение enum (в `VALID_VALUES` плагина, `workflow-enforcement.ts:60-72`).
- `pipeline` отражает **текущую фазу** (существующая семантика «массив текущего исполняемого пайплайна»), `phases` + `current_phase` — фазовое состояние. Это снимает старую неоднозначность «массив всех шагов или только текущей стадии?» (`RESEARCH_PIPELINE_ENHANCEMENTS.md:71`) для нового механизма, не ломая SUPERCOMPLEX.
- На фазовой границе: `current_phase` переключается, `pipeline` заменяется цепочкой новой фазы — **новый пункт в mutation whitelist** плагина (рядом с BUGFIX continuation / DECOMPOSITION, `workflow-enforcement.ts:875-881`).

### 7.3 Валидация плагином (workflow-enforcement.ts)

Минимальный набор изменений:

1. **VALID_VALUES**: добавить `MULTI_PHASE` в `type`; `phases[]`, `current_phase` в `REQUIRED_JSON_FIELDS` — условно (required iff `type === MULTI_PHASE`).
2. **pipelineState**: хранить `phases`, `currentPhaseIdx` рядом с `{pipeline, currentStep}`; фазовый переход = законная мутация (новый whitelist-кейс: `newType === prev.type && phasesMatch && phaseAdvanced`). ⚠️ Ловушка `provisional`: флаг вычисляется как `complexity === null` (`workflow-enforcement.ts:861`), а у MULTI_PHASE-ходов top-level `complexity: null` — значит `prev.provisional` остаётся `true` ВСЮ multi-phase сессию, и исключение F-4 (`:876`) разрешает ЛЮБУЮ замену pipeline: иммутабельность фактически не работает, а предлагаемый whitelist-кейс недостижим (всё проходит раньше через F-4). Для `type: MULTI_PHASE` нужно: после подтверждения плана считать ход unfrozen явно — например, `provisional = complexity === null && type !== "MULTI_PHASE"`, либо отдельный признак `confirmed: true` в JSON.
3. **validatePipeline**: валидация per-фаза — ключ `${phase.type}-${phase.complexity}-${phase.planExists}` против существующей таблицы (`:1885-1904`) + `PIPELINE_VARIANTS` (`:1910-1924`). Multi-phase сам по себе не ключ — ключи остаются фазовыми. Fail-closed сохраняется.
4. **Cross-field rules**: `phases.length ∈ [2..4]`; `depends_on` ⊆ ранее объявленные id; ровно одна фаза без `depends_on` (стартовая); `current_phase ∈ phases[].id`.
5. **Confirmation gate**: JSON со `state: "AWAITING_CONFIRMATION"` + `next_agent: null` легален только для `type: MULTI_PHASE` на Turn 1; следующий Task-вызов до пользовательского ответа запрещён (плагин трекает «пользовательское сообщение после AWAITING» — механика похожа на существующий turn boundary по messageID, `:539-543`).
6. **Ack-форматы**: добавить `→ PHASE <i>/<n> (<id>): <type>` и `→ PHASE PLAN AWAITING CONFIRMATION (<n> phases)` в regex (`:935-957`, warn-only).

### 7.4 Влияние на SUPERCOMPLEX

- **Дизамбигуация**: SUPERCOMPLEX = итерация по шагам **одного** DEV-плана внутри **одной** фазы. Multi-phase = итерация по фазам **разных типов**. Вложенность запрещена (§3.3, Вариант A): фаза может БЫТЬ SUPERCOMPLEX, но фазы не содержат sub-phases.
- **Приоритет классификации**: сначала определяется multi-phase (запрос содержит разнотипные deliverable), затем DEV-фазы внутри него проходят Q1–Q5 как обычно — включая возможность стать SUPERCOMPLEX.
- **Совместное поле состояния**: ack-строка становится двухуровневой: `→ PHASE 1/2 (P1), STEP 3/8 (S-3): DELEGATED to dev-professor` — расширение существующего формата `→ STEP <i>/<total>`, не новый язык.

### 7.5 Что ломается / требует пересмотра

| Существующее правило | Конфликт | Резолюция |
|---|---|---|
| «NEVER split one request into two pipelines» (`ARCHITECTURE.md:438`, `orchestrator.md:250`) | Прямое противоречие | Правило переформулируется: «never split **silently** — разбиение допустимо только через multi-phase с explicit `phases[]` + user confirmation». Mixed-intent priority остаётся fallback для пограничных случаев |
| «No pipeline changes after Turn 1» (`orchestrator.md:348`) | Фазовый переход = смена pipeline | Whitelist-исключение «phase transition» (как BUGFIX continuation) |
| `question: deny` (`ARCHITECTURE.md:281`) | Подтверждение плана | Не нарушается: подтверждение = обычный текстовый ответ пользователю, tool `question` не используется (§5.1) |
| Terminal-turn exemption (`workflow-enforcement.ts:1940-1944`) | `AWAITING_CONFIRMATION` = `pipeline: []` + `next_agent: null` на НЕ-финальном ходе | Уточнение: эксемпция shape-based (`pipeline.length === 0 && next_agent === null` → valid без проверки, что ход действительно терминальный) и «молча» пропустит AWAITING-ход — конфликт не в блокировке, а в неотличимости AWAITING от финального хода. Плюс `state` отсутствует в orchestrator-схеме (`REQUIRED_JSON_FIELDS`/`VALID_VALUES` описывают `state` только для plankestrator, `:55-72`). Резолюция: добавить `state` в orchestrator-схему (`AWAITING_CONFIRMATION \| CANCELLED \| null`) и валидировать `AWAITING_CONFIRMATION` только при `type: MULTI_PHASE` |
| BLOCKER STOP (`workflow-enforcement.ts:478-497`) | `blockerStop` — кумулятивный session-state, не сбрасывается заменой pipeline (`:887-894` сбрасывает только `reworkCount`/`blockerEscalations`) | Phase transition должен также сбрасывать `blockerStop` (иначе fail-fast-остановка фазы навсегда блокирует и resume, и следующие сессии-продолжения в той же сессии) |

---

## 8. Syntax and Triggers (синтаксис классификации)

### 8.1 Как оркестратор определяет multi-phase

Новый вопрос **T0** в Type Selection Decision Tree, ПЕРЕД T1:

> **T0:** Запрос содержит **два или более разнотипных deliverable**, каждое из которых независимо проходит T3/T4/T5/T6 в разные строки? → MULTI_PHASE → phase planning → user confirmation. Иначе → T1 (существующее дерево).

«Разнотипные deliverable» проверяется механически: каждое под-действие прогоняется через T3–T6; если результаты — разные типы И оба deliverable первичны (не «основное + побочное») → multi-phase.

### 8.2 Триггеры multi-phase

**Сильные триггеры (комбинация обязательна — одного союза мало):**

1. **Связки последовательности + разнотипные глаголы**: «**и**», «**а затем**», «**после этого**», «**также**» + глаголы из разных T-веток: *исправь… и добавь…* (BUGFIX+DEV), *настрой… и задеплой* (DEVOPS+DEVOPS с разными целями — сомнительно, см. ниже), *реализуй… запусти тесты… задеплой* (DEV+DEVOPS+DEVOPS).
2. **Явная нумерация разнотипных шагов**: «1. Настрой CI. 2. Добавь тесты. 3. Задеплой» — глаголы резолвятся в T4, T6, T4.
3. **Явный запрос пользователя**: «сделай в несколько этапов/фаз», «multi-phase», «по пайплайну на каждую часть» — как explicit SUPERCOMPLEX в Q1.

**Анти-триггеры (НЕ multi-phase — критично для борьбы с false positives):**

| Запрос | Почему single-phase |
|--------|---------------------|
| «Исправь баг и обнови README» | DOCS вторичен → Auto-DOCS hook (существующий Example 11, `orchestrator.md:331-334`) |
| «Исправь баг и задеплой» | Deploy = follow-up в summary (существующее правило `ARCHITECTURE.md:438`); multi-phase ТОЛЬКО если деплой нетривиален (миграции, откат) |
| «Добавь фичу и напиши к ней тесты» | Оба — DEV (код); тесты — часть фичи, не отдельный deliverable |
| «Исправь баги в auth и в кэше» | Один тип, один BUGFIX |
| «Сделай рефакторинг оплаты (6 шагов)» | Один тип, много шагов → SUPERCOMPLEX, не multi-phase |

**Эвристика «первичности»**: deliverable первичен, если его нельзя покрыть (a) Auto-DOCS hook, (b) follow-up-упоминанием, (c) одним шагом существующего пайплайна. Deploy после фикса — пограничный: «задеплой на прод» = follow-up; «настрой CI, прогони тесты, задеплой» = полноценные DEVOPS-фазы, потому что каждая требует devops-agent + devops-reviewer.

### 8.3 Single vs Multi: граница решения

```
Запрос
 ├─ 1 тип deliverable                    → single-phase (существующая классификация)
 ├─ 2+ типа, но вторичные покрываются
 │   hook/follow-up/mixed-intent priority → single-phase (default!)
 └─ 2+ типа, все первичны,
    phases ∈ [2..4]                      → MULTI_PHASE → T0 план → confirmation
```

**Default = single-phase.** При сомнении — single-phase + mixed-intent priority (как сейчас). Multi-phase — осознанное исключение, потому что: (a) стоимость k полных цепочек с ревьюерами, (b) длина сессии, (c) обязательное подтверждение добавляет round-trip. Это зеркалит принцип планкестратора «ambiguous complexity → COMPLEX (безопасная сторона)», но в обратную сторону: для multi-phase безопасная сторона — НЕ разбивать.

---

## 9. Recommendations

### 9.1 Поэтапное внедрение

**Stage 1 — MVP «линейная цепочка» (рекомендуется):**
- Только линейные цепочки 2–3 фаз, `depends_on` неявный (предыдущая фаза).
- Типы фаз ограничены: BUGFIX, DEV, DEVOPS, DOCS — в любой комбинации, но без DAG и параллелизма.
- Обязательное подтверждение плана (§5), fail-fast (§4.3), `PHASE_STATE.md` + phase result JSON (§4).
- Плагин: пункты 1–4 и 6 из §7.3 (без сложной DAG-валидации).
- Изменения документов: `ARCHITECTURE.md` (Type Selection + новая секция Multi-Phase), `agents/orchestrator.md` (PIPELINE TABLE мета-правило, T0, ack-форматы, examples), плагин, `CHANGELOG.md`. По существующему правилу — правки ARCHITECTURE.md и orchestrator.md **в одном коммите** (mirror-правило, `ARCHITECTURE.md:427`).

**Stage 2 — расширения (после опыта эксплуатации):**
- `continue_on_error` per-phase, возобновление с произвольной фазы, явный `depends_on`, лимит до 4 фаз.
- SUPERCOMPLEX-фазы внутри multi-phase (в MVP — разрешить, но собрать телеметрию длины сессий).

**Stage 3 — отложить/не делать:**
- Параллельные фазы (конфликт с «ONE Task call per turn»), data-dependent циклы между фазами, вложенные multi-phase. Внешние ориентиры (GitLab `needs`, LLMCompiler) зафиксировать как backlog.

### 9.2 Ключевые дизайн-решения (сводка)

| # | Решение | Выбор | Обоснование |
|---|---------|-------|-------------|
| 1 | Модель фаз | Композиция существующих строк PIPELINE TABLE | Ноль новых агентов, routing table не трогаем |
| 2 | Контекст | Phase Result JSON + `PHASE_STATE.md`, «pointer, not transcript» | Масштабирует работающие `*_plan.md` и XCom-принцип «small data only» |
| 3 | Ошибки | Fail-fast default, `continue_on_error` opt-in | Airflow/Temporal-семантика, детерминизм |
| 4 | Подтверждение | Обязательное, через текстовый ответ (не tool `question`) | Совместимо с `question: deny`; паттерн Plan Mode / OpenAI interruptions |
| 5 | Триггеры | T0 + строгие анти-триггеры, default single-phase | Защита от false-positive fan-out |
| 6 | SUPERCOMPLEX | Фаза, не обёртка; вложенность запрещена | Избегаем двухмерной итерации |
| 7 | JSON | `type: MULTI_PHASE` + `phases[]` + `current_phase`; `pipeline` = текущая фаза | Обратная совместимость, снимает ambiguity `RESEARCH_PIPELINE_ENHANCEMENTS.md:71` |

### 9.3 Альтернативы (и почему отклонены или отложены)

1. **Status quo** (ничего не делать): рабочая, но фичи в mixed-запросах систематически теряются — пользователь вынужден дробить запросы вручную. Отклонено как не решающее проблему.
2. **«Lightweight chaining»** — оркестратор в конце пайплайна предлагает «запустить следующий?» и стартует новый по команде: минимальные изменения, но это по сути ручной multi-phase без плана, контекста и валидации. Рекомендуется как **временная мера до MVP**, не как целевое решение.
3. **Полный DAG с параллельными фазами сразу**: отклонено для MVP — конфликтует с одно-Task-per-turn и требует переработки session model плагина. LLMCompiler/GitLab `needs` — ориентиры для Stage 3.

### 9.4 Открытые вопросы для follow-up research

- Точная семантика `pipeline`-поля при фазовом переходе: перезапись vs аккумуляция (влияет на `maxStepReached`, `reworkCount` reset — `workflow-enforcement.ts:887-894`).
- Лимиты сессии: длина контекста primaries на 3–4 полных цепочки с ревьюерами — нужна телеметрия; возможно, потребуется summarizer между фазами (агент уже в routing table, позиция 17).
- Поведение advisor на фазовых границах: считается ли переход «step boundary» для `NIT_ONLY_MODE`.
- Формализация для consistency-checker: новый класс проверок (multi-phase секция ARCHITECTURE.md ↔ orchestrator.md ↔ плагин) по аналогии с Model Roles.

---

## 10. Sources Consulted

### Локальные источники
- `ARCHITECTURE.md` (P:\Programming\Рефакторинг) — routing tables, pipelines, type selection tree, mixed-intent rule (:438), Auto-DOCS hook (:543-568), SUPERCOMPLEX (:486-523), tool lockdown (:266-296)
- `agents/orchestrator.md` — PIPELINE TABLE (:43-61), JSON schema (:171-186), TURN ALGORITHM (:154-169), CLASSIFICATION RULES (:206-237), mixed-intent rule (:250), Example 11 (:331-334), PROHIBITIONS (:341-352)
- `plugins/workflow-enforcement.ts` — pipelineState (:172), validatePipeline (:1885-1904), PIPELINE_VARIANTS (:1910-1924), mutation whitelist (:875-881), VALID_VALUES (:60-72), rework cap (:1473-1486), blocker stop (:474-499), terminal exemption (:1940-1944), ack audit (:935-957)
- `RESEARCH_PIPELINE_ENHANCEMENTS.md` — открытый вопрос о семантике `pipeline` (:71), P0-2 step tracking (:45)
- `PLAN_PROMPT_ENHANCEMENTS.md` — mixed-intent rejection (:212), pipelineState semantics (:683-690), DECOMPOSITION two-turn protocol (:158-162)
- `dev_plan.md`, `CHANGELOG.md` — текущий контекст разработки; multi-phase chaining нигде не предлагался ранее

### Внешние источники
- LangGraph persistence & interrupts: https://docs.langchain.com/oss/python/langgraph/persistence, https://docs.langchain.com/oss/python/langgraph/interrupts
- Apache Airflow XComs / Tasks: https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/xcoms.html, https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html
- Temporal Workflows / Child Workflows: https://docs.temporal.io/workflows, https://docs.temporal.io/child-workflows
- Prefect Flows/Tasks: https://docs.prefect.io/v3/concepts/flows, https://docs.prefect.io/v3/concepts/tasks
- GitHub Actions environments & expressions: https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments, https://docs.github.com/en/actions/reference/workflows-and-actions/expressions
- GitLab CI job control / deployment approvals: https://docs.gitlab.com/ci/jobs/job_control/, https://docs.gitlab.com/ci/environments/deployment_approvals/
- LangChain planning agents (Plan-and-Execute, LLMCompiler): https://blog.langchain.com/planning-agents/
- ReWOO paper: https://arxiv.org/abs/2305.18323
- Claude Code Plan Mode: https://code.claude.com/docs/en/permission-modes, https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/
- OpenAI Agents SDK HITL: https://openai.github.io/openai-agents-python/human_in_the_loop/

---

## 11. Limitations

- **Нет runtime-трассировки**: выводы о плагине основаны на статическом чтении `workflow-enforcement.ts`; поведение `pipelineState` при реальных фазовых переходах не проверялось на живых сессиях (та же оговорка, что в `RESEARCH_PIPELINE_ENHANCEMENTS.md:110-113`).
- **Стоимость не измерена**: оценка «multi-phase дороже» качественная (k полных цепочек с обязательными ревьюерами); численная модель токенов/времени не строилась.
- **Триггеры T0 — эвристика**: порог «первичности deliverable» (§8.2) требует калибровки на реальных запросах; риск false positives/negatives оценить статически нельзя.
- **Поведение primaries-модели (QWEN3.7-plus) на двухуровневом планировании** (фазы × шаги SUPERCOMPLEX) не предсказано; возможны ошибки классификации — рекомендуется пилот на synthetic-запросах.
- **Кросс-проверка противоречий**: противоречие между существующим правилом «NEVER split one request into two pipelines» и целью multi-phase зафиксировано (§7.5) и требует осознанного изменения ARCHITECTURE.md — это не побочный эффект, а часть scope'а работ.
