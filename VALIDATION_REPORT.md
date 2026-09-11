# Отчёт о валидации конфигурации primary agents

**Дата:** 2026-09-07
**Источник данных:** `P:\Programming\Рефакторинг\RESEARCH.md`

**Проверенные файлы:**
- `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (125 строк)
- `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (117 строк)
- `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1020 строк)
- `C:\Users\Admin\.config\opencode\opencode.json` (1588 строк)
- `P:\Programming\Рефакторинг\ARCHITECTURE.md` (668 строк)

---

## 1. Сводка по 6 найденным проблемам

| № | Название | Severity | Затронутые файлы | Суть проблемы | Потенциальное влияние |
|---|----------|----------|------------------|---------------|----------------------|
| 1 | Противоречие слоёв разрешений по `todowrite`/`question` | Medium | `orchestrator.md` (frontmatter + PROHIBITIONS L120), `plankestrator.md` (frontmatter + PROHIBITIONS L110), `opencode.json` (обе primary-секции: orchestrator L1232–1239, plankestrator L1420–1427), `ARCHITECTURE.md` (L166–178, L183, L187), `AGENTS.md` (глобальный), `workflow-enforcement.ts` (L466–510) | ARCHITECTURE.md «Primary Agent Tool Lockdown (v3)» требует `todowrite: deny` и `question: deny` для обоих primary agents, но frontmatter и opencode.json выставляют `todowrite: allow`, а plankestrator — ещё и `question: allow`. Глобальный `AGENTS.md` также разрешает эти инструменты. Дополнительно тот же класс противоречия касается грантов `unity-mcp.*` и семи `serena_*` в opencode.json (~9 «мёртвых» инструментов на каждого primary). | Runtime-гейт плагина (`PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}`) всё равно блокирует эти инструменты: модель видит их в тулсете, вызывает и получает жёсткое исключение `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL`. Конфиг, документация и рантайм противоречат друг другу; списки PROHIBITIONS в .md не дают защиты в глубину (orchestrator не запрещает `todowrite`, plankestrator — ни `todowrite`, ни `question`). ARCHITECTURE.md L183 также ссылается на несуществующее поле `tools:` frontmatter «layer 2». |
| 2 | Task-allowlist plankestrator в opencode.json шире его routing table | Medium-High | `opencode.json` (L1440–1442), `workflow-enforcement.ts` (`ROUTING_TABLES.plankestrator`, fallback L643–656), `plankestrator.md` (`OPENCODE_ROUTING_TABLE`, L26) | `opencode.json` предоставляет plankestrator `task`-доступ к `view-image`, `generate-image`, `generate-image-gpt` — агентам, которых нет ни в plugin routing table (9 агентов), ни в `OPENCODE_ROUTING_TABLE` plankestrator.md. Все три есть в whitelist orchestrator. | Если plankestrator вызовет одного из этих агентов, routing-fallback плагина сопоставит его с таблицей *другого* агента и **мутирует `currentAgent` в `orchestrator`**, молча перепривязав идентичность сессии. `lockedAgentName` не меняется (hard-gate и vocab-check ссылаются на исходного агента), но все последующие Task-вызовы валидируются по 24-агентной таблице orchestrator (plankestrator сможет легально вызывать `worker`, `bugfix-triage` и т.д.), а JSON plankestrator начнёт валидироваться по схеме orchestrator → постоянные предупреждения «INVALID JSON OUTPUT» (нет полей `plan_exists`/`plan_source`). |
| 3 | Routing-fallback плагина игнорирует identity lock | Medium (plugin-side) | `workflow-enforcement.ts` (`tool.execute.before` L643–656, `message.updated` L337–353), `ARCHITECTURE.md` (L541) | Fallback в `tool.execute.before` переключает `currentAgent`, когда целевой субагент находится в whitelist другого primary, без проверки `identityLocked`. | Противоречит гарантии v3-лока («агент не может быть перепривязан после этого момента», ARCHITECTURE.md L541), которую обработчик дрейфа `message.updated` соблюдает. Проблема №2 — реалистичный триггер этого латентного бага. |
| 4 | Замечание о rework-loop в orchestrator.md не покрывает строки 4 и 6 | Low-Medium | `orchestrator.md` (L59), `ARCHITECTURE.md` (L244, L257, L265, L282) | L59 ограничивает rework-loop строками «1-DEEP, 5, 8». ARCHITECTURE.md же назначает rework-loop для DEV SIMPLE с планом (строка 4 — «task returns to **worker** for fixes», L257) и для DEV SUPERCOMPLEX (строка 6 — per-step loop «returns to `rework`», L282). | Скобочное уточнение «(or the agent named in its `escalate_to`)» частично покрывает цель `worker` строки 4, но буквальное прочтение замечания вообще исключает обе строки из зацикливания — риск того, что модель не выполнит обязательный rework-loop для этих пайплайнов. |
| 5 | Литеральные запрещённые токены в orchestrator.md L109 | Low | `orchestrator.md` (L109), `workflow-enforcement.ts` (`FORBIDDEN_VOCAB` L91–92, обработка L414–432) | Правило детекции `plan_exists=true` содержит литеральные строки `"## PLAN"` и `"# Implementation Plan"` — обе входят в список `FORBIDDEN_VOCAB` orchestrator. | Если модель процитирует это правило дословно в сообщении, плагин залогирует ложноположительную ошибку `FORBIDDEN VOCABULARY DETECTED`. Плагин не бросает исключение при vocab-нарушениях, поэтому влияние — шумные error-логи и ложные сигналы дрейфа идентичности, а не жёсткая блокировка. |
| 6 | Ячейка `plan_exists: any` в строке 5 orchestrator.md противоречит правилу классификации L116 | Trivial | `orchestrator.md` (таблица L49, правило L116) | L116 маршрутизирует `plan_exists=false + COMPLEX` в plankestrator как OUT OF SCOPE, поэтому строка 5 (DEV COMPLEX) недостижима при `plan_exists=false`. | Ячейка таблицы вводит в заблуждение: должна читаться как `true`, а не `any`. Функционального сбоя нет — только неточность документации в промпте. |

---

## 2. Сводка по 7 рекомендациям

| № | Связь с проблемой | Что нужно сделать | Затронутые файлы | Приоритет |
|---|-------------------|-------------------|------------------|-----------|
| 1 | Проблема №1 | Согласовать слои `todowrite`/`question`. Рекомендуется: выставить `todowrite: deny` и `question: deny` в обоих frontmatter-блоках и обеих секциях opencode.json (соответствуя ARCHITECTURE.md и гейту плагина) и убрать их из списка разрешённых в глобальном `AGENTS.md`. Если инструменты намеренно сохраняются — обновить lockdown-таблицу ARCHITECTURE.md и добавить их в `PRIMARY_AGENT_ALLOWED_TOOLS` плагина. **Дополнительно (addendum ревьюера):** удалить ключи `unity-mcp.*` и `serena_*` из обеих primary-секций opencode.json (primary должны делегировать такие операции через Task); добавить `todowrite`/`question` в оба списка PROHIBITIONS (orchestrator.md уже запрещает `question` — добавить `todowrite`; plankestrator.md нужны оба); исправить ARCHITECTURE.md L183 — либо убрать вымышленный «layer 2» с полем `tools:` frontmatter, либо реально добавить это поле. | `orchestrator.md` (frontmatter + PROHIBITIONS L120), `plankestrator.md` (frontmatter + PROHIBITIONS L110), `opencode.json` (обе primary-секции), `ARCHITECTURE.md` (L166–178, L183), `AGENTS.md`, `workflow-enforcement.ts` (L466) | High |
| 2 | Проблема №2 | Сократить JSON task-allowlist plankestrator: удалить `view-image`, `generate-image`, `generate-image-gpt` из `opencode.json` L1440–1442, чтобы allowlist совпадал с plugin routing table (9 агентов). Если генерация изображений из планировочных сессий — желаемая фича, добавить этих агентов в `ROUTING_TABLES.plankestrator` в плагине *и* в `OPENCODE_ROUTING_TABLE` plankestrator.md. | `opencode.json` (L1440–1442); опционально `workflow-enforcement.ts`, `plankestrator.md` | High |
| 3 | Проблема №3 | Защитить routing-fallback identity lock'ом: в `workflow-enforcement.ts` L643 пропускать переключение агента при `identityLocked === true` и вместо этого бросать routing-table violation. Это делает v3-лок герметичным на обоих enforcement-хуках. | `workflow-enforcement.ts` (L643) | High |
| 4 | Проблема №4 | Исправить замечание о rework-loop: изменить orchestrator.md L59, чтобы покрывать все строки, содержащие `consistency-checker`, например: «Rework loop (rows 1-DEEP, 4, 5, 6, 8): if consistency-checker reports critical issues, return to the agent named in its `escalate_to` (default `rework`; `worker` for row 4), max 3 iterations, then `utility`.» | `orchestrator.md` (L59) | Medium |
| 5 | Проблема №5 | «Обезвредить» литеральные токены: переписать orchestrator.md L109, избегая точных строк, например `a top-level markdown PLAN heading ("## P"+"LAN" style)` или описание «an H2 heading whose text is PLAN». Функционально идентично, ложные vocab-срабатывания исчезают. | `orchestrator.md` (L109) | Low |
| 6 | Проблема №6 | Исправить ячейку `plan_exists` строки 5: изменить `any` → `true` в orchestrator.md L49, отражая правило классификации L116. | `orchestrator.md` (L49) | Low |
| 7 | Опциональное усиление (запреты orchestrator) | Добавить два явных пункта по образцу plankestrator: «No skipping dev-reviewer / consistency-checker — they are mandatory pipeline elements» и «No more than ONE Task call per turn.» | `orchestrator.md` (PROHIBITIONS, L118–125) | Low |

*Примечание: колонка «Приоритет» отсутствует в RESEARCH.md — она выведена составителем отчёта из severity проблем и Executive Summary (проблемы №1–2 названы «the most serious»). Рекомендации №1–№3 отмечены High как устраняющие угрозы целостности сессии и runtime-исключения.*

---

## 3. Общий вывод

### Валидна ли текущая конфигурация?

**Да, по существу валидна («substantially valid»).** Pipeline-first рефакторинг корректен во всех ключевых измерениях:

- **JSON-контракты** обоих агентов точно совпадают с требованиями плагина: orchestrator содержит все 8 обязательных полей (`agent`, `type`, `complexity`, `plan_exists`, `plan_source`, `goal`, `next_agent`, `pipeline`), plankestrator — все 7 (`agent`, `state`, `type`, `complexity`, `goal`, `next_agent`, `pipeline`). Все значения из `VALID_VALUES` плагина.
- **Routing tables идентичны** во всех трёх источниках: orchestrator — 24 агента (включая порядок), plankestrator — 9 агентов.
- **Identity-блоки** обоих агентов совпадают с regex плагина (`/IDENTITY VERIFIED:\s*I am\s+(orchestrator|plankestrator)/i`), содержат fatal-refusal clause; legacy IDENTITY PROBE шаг полностью удалён.
- **State machines** единственны и детерминированы в обоих файлах (одна секция `## TURN ALGORITHM`, без дубликатов); все четыре состояния plankestrator (`CLASSIFY/EXECUTE/REVIEW/COMPLETE`) имеют однозначные триггеры.
- **Edge-case пайплайны** корректно специфицированы: BUGFIX two-stage (orchestrator), RESEARCH+PLAN (plankestrator), OUT OF SCOPE в обе стороны, SUPERCOMPLEX step counting, JSON-before-Task gate.
- **Проверки frontmatter vs opencode.json** пройдены по модели, температуре, mode, отсутствию dead-конфига.

### Основные риски

1. **Критично — противоречие трёх слоёв разрешений (Проблемы №1 и №2):** конфиг *разрешает* инструменты (`todowrite`, `question`, `unity-mcp.*`, `serena_*`, image-агенты для plankestrator), которые плагин *блокирует в рантайме* или которые приводят к мутации идентичности сессии. Это самый опасный класс проблем: модель видит инструмент, вызывает его и либо получает исключение, либо (хуже) молча перепривязывает сессию к другому агенту.
2. **Средне — латентный баг плагина (Проблема №3):** routing-fallback игнорирует `identityLocked`, что подрывает гарантию v3-лока. Имеет реалистичный триггер через Проблему №2.
3. **Низко — неточности промптов (Проблемы №4–6):** неполное покрытие rework-loop, ложные vocab-срабатывания, вводящая в заблуждение ячейка таблицы. Не ломают работу, но создают шум и риск неверного поведения модели.

### Что критично исправить в первую очередь

Приоритет **High** — рекомендации №1, №2, №3 (синхронизация permission-слоёв, обрезка task-allowlist plankestrator, защита routing-fallback identity lock'ом). Они устраняют единственные реальные угрозы целостности сессии и runtime-исключения. Рекомендации №4–№7 можно выполнить в том же проходе как низкозатратные правки промптов.

---

*Отчёт составлен исключительно на основе данных `RESEARCH.md` — закрытой валидации консистентности пяти файлов системы.*
