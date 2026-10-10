# Research: усиления следования пайплайнам (orchestration)

Дата: 2026-09-29 · Статус: quick research · Язык вывода: русский

---

## Current State

### Архитектура
- **2 primary-агента**: `orchestrator` (BUGFIX/DEVOPS/DEV/DOCS) и `plankestrator` (PLAN/RESEARCH/RESEARCH+PLAN). Области взаимоисключающи (`orchestrator.md:27-28`, `plankestrator.md:27-28`).
- **Plugin** `workflow-enforcement.ts` (1584 строк): 3 хука — `event` (`:192`, session.created/idle, message.updated), `tool.execute.before` (`:689`, все гейты), `tool.execute.after` (`:1138`, лог + декремент depth).

### Объявленные 5 валидаций (и реальный enforcement)
| # | Валидация | Реальный эффект |
|---|---|---|
| 1 | Identity required | **log-only** (`:441-445`) |
| 2 | Pipeline validation | **log-only** (`:556-568`) |
| 3 | next_agent validation | **log-only** (`:571-585`), счётчик шага — заглушка `const currentStep = 0 // TODO` (`:573`) |
| 4 | read/grep/glob lock после первого Task | **THROW** (`:746`) ✅ |
| 5 | severity nit skip | log-only в ветке сабагентов (`:355-407`) |

Реальные `throw` всего 8: `:746` (read-lock), `:777` (forbidden action tool), `:839/:863/:886` (inspection gate plankestrator), `:1009` (JSON before Task), `:1053/:1085` (routing table). **Всё остальное — логи.**

### Конфиг
- `ROUTING_TABLES` (`:6`): orchestrator — 29 агентов, plankestrator — 10. Дублируется в промптах (`orchestrator.md:24-28`).
- `REQUIRED_JSON_FIELDS` (`:55`): orchestrator 8 (вкл. `plan_exists`, `plan_source`), plankestrator 7 (вкл. `state`).
- `SEVERITY_AGENTS = [dev-reviewer, consistency-checker, advisor]` (`:86`); `MAX_NON_BLOCKER_FINDINGS_PER_UPDATE = 4` (`:94`); `INSPECTION_BUDGET = 3` (`:129`).
- `FORBIDDEN_VOCAB` (`:142`): по **9 токенов** у каждого (orchestrator: 3 identity-фразы + «## PLAN»/«# Implementation Plan» + 4 имени plan/research-агентов; plankestrator: 5 identity-фраз + 4 имени dev-агентов) → **log-only** (`:628`; комм. `:641-644` сознательно не бросает throw — риск false-positive на легальных перекрёстных упоминаниях).
- `SELF_WORK_MARKERS` (`:165`): **только plankestrator**, ключа `orchestrator` нет.

### Промпты
- Оба: RUNTIME IDENTITY + identity line `IDENTITY VERIFIED: I am ...`, PIPELINE TABLE, TURN ALGORITHM, JSON FORMAT, PROHIBITIONS, PLUGIN ENFORCEMENT. Одинаковые permissions (edit/write/bash/patch/webfetch/question/todowrite = deny; read/grep/glob = allow).
- Orchestrator дополнительно: SUPERCOMPLEX 3-stage (`:63-96`), DECOMPOSITION (`:176-179`), SEVERITY RULES + rework max 3 (`:132-139`), ADVISOR STEP RULES, Auto-DOCS hook (`:61`). PROHIBITIONS: 10 пунктов (`:185-194`).
- Plankestrator: inspection MAX 2 (Turn 1), view-image как отдельный turn, self-work запрет. PROHIBITIONS: 12 пунктов (`:153-164`).

---

## Proposed Enhancements

### P0 — критично (закрыть обещания промптов, которые plugin не выполняет)

1. **Эскалация log-only нарушений в THROW** — pipeline mismatch (`:559`), next_agent mismatch (`:576`), невалидный JSON (`:591`), FORBIDDEN_VOCAB (`:628`), отсутствие identity (`:441`), identity drift при `identityLocked` (`:511`). Промпты заявляют «You cannot override plugin validation» (`orchestrator.md:205`) — сейчас это блеф для 5 из 6 пунктов (исключение — невалидный JSON: непрямая блокировка, т.к. `hasOutputtedJSON` выставляется только при валидном JSON (`:603-604`) → Task заблокирован гейтом `:1009`).
   - ⚠️ **Механизм**: throw в event-хуке (`message.updated`) не отменит уже сгенерированное сообщение (сам плагин отмечает это для субагентов, `:357-359`). Рабочий паттерн уже в коде — `selfWorkDetected` (`:667`): флаг ставится в message.updated, THROW потребляется в `tool.execute.before` (`:854`). Эскалации этого пункта реализовывать так же, не прямым throw в event-хуке.
   - ⚠️ **FORBIDDEN_VOCAB — эскалировать выборочно**: комм. `:641-644` сознательно избегает throw из-за false-positive на легальных перекрёстных упоминаниях (orchestrator вправе упомянуть «plan-writer-» в OUT OF SCOPE-ответе). THROW только на identity-токены («I am plankestrator» и т.п.), не на имена агентов.
2. **Реализовать трекинг шага пайплайна** вместо `currentStep = 0 // TODO` (`:573`). Хранить `pipeline[]` из первого JSON + индекс, валидировать `next_agent === pipeline[currentStep + 1]`, учитывая исключения (BUGFIX continuation, DECOMPOSITION, rework, nit-skip — `orchestrator.md:190`).
3. **Fail-closed `validatePipeline`** (`:1429`): неизвестные значения `type`/`complexity`/`plan_exists` сейчас → `valid: true`. Должны быть ошибкой. Плюс кросс-валидация: `SUPERCOMPLEX + plan_exists=false` → невалидно; `plan_source` только при `plan_exists=true`; `complexity=null` только для BUGFIX/DEVOPS.

### P1 — важные (покрыть неохраняемые запреты)

4. **SELF_WORK_MARKERS для orchestrator** (`:165` — нет ключа). Сейчас self-work детектится только у plankestrator.
5. **«Max ONE Task call per turn»** (`orchestrator.md:193`) — в plugin не проверяется. Считать task-вызовы в рамках turn и THROW при втором.
6. **Rework loop max 3** (`orchestrator.md:59`) и **BLOCKER STOP после 3-го** (`:138`) — не трекаются. Завести счётчики `reworkCount`, `blockerEscalations`.
7. **Severity-гейт для primary-сообщений** — сейчас severity проверяется только в ветке `activeTaskDepth>0` (`:355`), для JSON самого primary (если он вернёт `severity`) — нет.
8. **Строгий формат ack** `→ DELEGATED to <agent> for: <goal>` — regex-валидация после JSON. Также пост-ack проза (`orchestrator.md:189` «no analysis after ack») — не проверяется.
9. **Иммутабельность pipeline после Turn 1** (`orchestrator.md:190`) — зафиксировать `pipeline[]` из первого JSON, THROW при изменении вне whitelist-исключений.

### P2 — укрепление (edge cases и гигиена)

10. **Инспекционный бюджет Turn 1 для orchestrator** — гейт `INSPECTION_GATE` (`:812-907`) только для plankestrator. Нюанс: запрет read/grep/glob в Turns 2..N для orchestrator **уже работает** — blanket-lock `:746` после первого Task-вызова (без исключений: даже auxiliary-цель выставляет `primaryAgentFirstTaskCall`, `:730-732`). Реальные пробелы: (а) в Turn 1 до первого Task у orchestrator нет бюджета инспекций (у plankestrator — 3); (б) `:746` не знает исключения «counting steps in plan files» (`orchestrator.md:188`) — сузить: разрешить read только `*plan*.md` / `*.plan.md`.
11. **Хард-блок смены режима mid-session** (`:419-432`, сейчас log-only) и сброса identity.
12. **Валидация исключений BUGFIX continuation / DECOMPOSITION / Auto-DOCS** — сейчас только проза в промпте; ввести явный `mode` в JSON (напр. `continuation: true`) и whitelist-ветки.
13. **Проверка существования `REVIEW_CONTEXT.md`** (`:109`, инъекция указателя `:1104-1117`) — плагин не проверяет, что файл есть.
14. **Бюджет инспекций — зафиксировать интент, а не «выравнивать»**: промпт «MAX 2» (`plankestrator.md:58`) vs плагин `INSPECTION_BUDGET = 3` (`:129`). Расхождение намеренное (комм. `:127-128`: запас 1 вызов — «промпт строже закона, закон ловит эскалацию»; `plankestrator.md:161` прямо называет hard limit 3). Проблема не в числах, а в том, что интент разнесён по двум файлам — добавить перекрёстные ссылки. «Выбрать одно значение» = удалить запас, делать не нужно.

---

## Implementation Notes

### Слабости промптов (вне plugin)
- **BUGFIX-строка PIPELINE TABLE неформальна** (`orchestrator.md:54-57`): «bugfix-triage → CONTINUE» с ветвлением SIMPLE/DEEP прозой — статически невалидируема. Нужны 2 отдельные строки таблицы или `branch`-поле.
- **Семантика `pipeline` для SUPERCOMPLEX** (`:63-96`, «per step») неоднозначна: это массив всех шагов или только текущей стадии? Валидатор не сможет проверить без формализации.
- **JSON-схемы разошлись**: orchestrator — `plan_exists`/`plan_source`, plankestrator — `state` (`plankestrator.md:84-89`). Нет общего schema-документа → риск дрейфа от `REQUIRED_JSON_FIELDS` (`plugin:55-57`).
- **`plan_exists: null`** в таблице — literal `null` или отсутствие поля? Нужна явная нормализация.
- **Исключение «counting steps in plan files»** (`orchestrator.md:188`) — размытое, злоупотребляемое; лучше сузить до конкретного glob.
- **Переоценка enforcement в промптах**: оба агента читают «You cannot override plugin validation», но большинство проверок — soft. Ввести в промпт честную маркировку HARD (throw) vs SOFT (audit log), либо поднять всё до HARD (см. P0).
- **PLUGIN ENFORCEMENT plankestrator** (`:168-174`) перечисляет 4 пункта из 5 — severity отсутствует (корректно по дизайну, но стоит зафиксировать, чтобы не «починили» случайно).

### Edge cases, не покрыты
- **Дочерние сессии** (`session.created` + `parentID` → early return `:196-220`): валидации не применяются вообще — потенциальная обходная дверь.
- **Вложенные Task** (`activeTaskDepth>0` → bypass всех гейтов `:697-710`): сабагент-внутри-сабагента работает без ограничений.
- **`next_agent === undefined`** — проверка целиком пропускается (`:571-585` skip при `undefined`); отсутствие поля не ошибка.
- **Split/мультимодальный JSON** — `extractJSONFromMessage` (`:1358`) извлекает один блок; JSON, разнесённый по частям сообщения, не валидируется.
- **Первый Task = `explore`/`general`** (`:1028-1040`) — bypass routing + depth++, влияет на триггер read-lock и `isFirstTaskCall` (`:1006`).
- **Reviewer-агент как top-level сессия** — severity-ветка привязана к `activeTaskDepth>0`, для самостоятельного запуска dev-reviewer проверок нет.
- **`hasOutputtedJSON=true` отключает identity-check** (`:438-449`) — во всех последующих turn identity не проверяется (по дизайну, но drift-детект `:486-502` это лишь логирует).
- **`seenFindings` сбрасывается на session.created** (`:234-241`) — дубликаты между сессиями не ловятся.
- **`validateJSONOutput` не валидирует cross-field согласованность** (`:1470`): напр. `type=DOCS` + неожиданный `plan_exists`, `state=COMPLETE` при незавершённом pipeline.

### Малозатратные quick wins
1. Заменить `const currentStep = 0 // TODO` (`:573`) — ~10 строк, снимает главный пробел next_agent-валидации.
2. `SELF_WORK_MARKERS.orchestrator` — просто добавить ключ в константу (`:165`).
3. `INSPECTION_BUDGET`: не «выравнивать» (запас намеренный, см. P2.14) — добавить перекрёстные комментарии-ссылки в плагин и промпт.
4. `next_agent === undefined` → ошибка, а не skip (`:571`).

---

## Sources Consulted
- `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (205 lines)
- `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (174 lines)
- `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1584 lines)

## Key Facts
- Из 5 заявленных в PLUGIN ENFORCEMENT валидаций реально блокирует **одна**: read/grep/glob lock (`:746`); остальные — audit log. Routing table (`:1053/:1085`) блокирует реально, но в заявленный список из 5 пунктов не входит. Полный список 8 throw — выше (Current State).
- `validateNextAgent` содержит TODO-заглушку (`:573`) — next_agent не сверяется с реальной позицией в пайплайне.
- `validatePipeline` fail-open: неизвестные значения полей → `valid: true` (`:1429`).
- Self-work детектор покрывает только plankestrator (`:165`).
- Дочерние сессии и вложенные Task обходят все гейты (`:196-220`, `:697-710`).
- Промпт plankestrator: MAX 2 инспекции; плагин: бюджет 3 — численно расходится, но **намеренно и задокументировано с обеих сторон** (`:127-128` «промпт строже закона, закон ловит эскалацию» — запас 1 вызов; `plankestrator.md:161` прямо называет «Plugin hard limit: 3»).

## Limitations
- Анализ по снимку кода без запуска/трассировки runtime-поведения; фактический порядок срабатывания хуков (`session.idle` vs `message.updated`) не проверялся экспериментально.
- Содержимое `REVIEW_CONTEXT.md` и фактические сессионные логи не анализировались — предложения по severity/rework-счётчикам не сверялись с реальными транскриптами.
- Не оценивалась производительность (1584-строчный плагин на каждом tool-call) и конкурентный доступ к state между сессиями.
