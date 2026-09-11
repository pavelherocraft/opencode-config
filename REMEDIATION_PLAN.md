# План доработок: устранение 6 проблем валидации конфигурации primary agents

**Дата:** 2026-09-07
**Источник:** `P:\Programming\Рефакторинг\VALIDATION_REPORT.md`
**Назначение:** пошаговый исполнимый план для передачи orchestrator
**Объём:** 7 рекомендаций, устраняющих 6 проблем (№1–№6 из отчёта)

**Целевые файлы:**

| Файл | Положение |
|------|-----------|
| `C:\Users\Admin\.config\opencode\agents\orchestrator.md` | 125 строк |
| `C:\Users\Admin\.config\opencode\agents\plankestrator.md` | 117 строк |
| `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | 1020 строк |
| `C:\Users\Admin\.config\opencode\opencode.json` | 1588 строк |
| `P:\Programming\Рефакторинг\ARCHITECTURE.md` | 668 строк |
| `P:\Programming\Рефакторинг\AGENTS.md` | таблица разрешений на строке 207 |

> **Уточнение к отчёту (проверено по фактическим файлам):** отчёт называет `AGENTS.md` «глобальным», однако таблица «Tool allowance for primary agents» с `todowrite`, `question` в колонке Allowed фактически находится в **проектном** `P:\Programming\Рефакторинг\AGENTS.md` (строка 207). В глобальном `C:\Users\Admin\.config\opencode\AGENTS.md` упоминаний `todowrite` нет. Существует также копия таблицы в `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` (строка 207) — вне объёма отчёта, рекомендуется синхронизировать для консистентности.

> **Все номера строк ниже сверены с фактическими файлами и совпадают с номерами из VALIDATION_REPORT.md.** При правке рекомендуется использовать точное совпадение строк (string replace), а не номера строк: после удалений/вставок номера смещаются. Если правки идут по номерам строк в одном файле — выполнять **снизу вверх**.

---

## Сводная таблица

| Рек. | Проблема | Приоритет | Файлы | Требует перезапуска opencode |
|------|----------|-----------|-------|------------------------------|
| 1 | №1 (противоречие слоёв разрешений) | High | orchestrator.md, plankestrator.md, opencode.json, ARCHITECTURE.md, AGENTS.md | Да (frontmatter + opencode.json) |
| 2 | №2 (task-allowlist plankestrator шире routing table) | High | opencode.json (L1440–1442) | Да |
| 3 | №3 (routing-fallback игнорирует identity lock) | High | workflow-enforcement.ts (L643) | Да (плагин загружается при старте) |
| 4 | №4 (rework-loop не покрывает строки 4 и 6) | Medium | orchestrator.md (L59) | Да (промпт перечитывается в новой сессии) |
| 5 | №5 (литеральные запрещённые токены в L109) | Low | orchestrator.md (L109) | Да |
| 6 | №6 (`plan_exists: any` в строке 5) | Trivial/Low | orchestrator.md (L49) | Да |
| 7 | Усиление PROHIBITIONS orchestrator | Low | orchestrator.md (L118–125) | Да |

**Итог: один перезапуск opencode после завершения всех правок покрывает все рекомендации.** Правки ARCHITECTURE.md и AGENTS.md перезапуска не требуют (ARCHITECTURE.md — справочный документ, AGENTS.md подхватывается с новой сессией), но выполняются в том же проходе.

---

## Порядок выполнения

### Зависимости между рекомендациями

- **Рек. 2 и Рек. 3 связаны логически:** Рек. 2 убирает реалистичный триггер (агенты `view-image`, `generate-image`, `generate-image-gpt` в allowlist plankestrator), Рек. 3 устраняет сам латентный баг (fallback-переключение `currentAgent` при `identityLocked === true`). Выполнять **обе** — они страхуют друг друга.
- **Рек. 1, 4, 5, 6, 7 связаны физически:** все правят `orchestrator.md` — выполнять одним последовательным проходом по файлу (во избежание конфликтов правок и смещения строк).
- **Рек. 1 и Рек. 2 связаны физически:** обе правят `opencode.json` — выполнять одним последовательным проходом по файлу, **снизу вверх** (сначала L1440–1442, затем L1416–1427, затем L1227–1239), чтобы удаления не сбивали номера строк следующих правок.
- **Рек. 3 полностью независима** (единственный файл — `workflow-enforcement.ts`).
- **Рек. 4, 5, 6, 7 независимы друг от друга** по содержанию, но выполняются в рамках одного прохода по orchestrator.md вместе с Рек. 1.

### Фазы

1. **Фаза 1 (High) — конфигурация и плагин:**
   - Пакет A: `opencode.json` — Рек. 1 (permission-ключи обеих primary-секций) + Рек. 2 (task-allowlist plankestrator). Один последовательный проход, снизу вверх.
   - Пакет B (**параллельно с A**): `workflow-enforcement.ts` — Рек. 3.
2. **Фаза 2 — промпты (может выполняться параллельно с Фазой 1, файлы не пересекаются):**
   - Пакет C: `orchestrator.md` — Рек. 1 (frontmatter L15 + PROHIBITIONS L120) + Рек. 4 (L59) + Рек. 5 (L109) + Рек. 6 (L49) + Рек. 7 (L118–125). Один последовательный проход.
   - Пакет D (**параллельно с C**): `plankestrator.md` — Рек. 1 (frontmatter L12, L15 + PROHIBITIONS L110).
3. **Фаза 3 — документация (параллельно с Фазами 1–2):**
   - Пакет E: `ARCHITECTURE.md` (L180–185) + `AGENTS.md` (L207) — документальная часть Рек. 1.
4. **Фаза 4 — перезапуск opencode и верификация** (см. раздел «Верификация»). После всех правок — один перезапуск, затем контрольные проверки.

### Что можно выполнять параллельно

| Параллельно | Последовательно (внутри пакета) |
|-------------|----------------------------------|
| Пакет A (opencode.json) ∥ Пакет B (плагин) ∥ Пакет C (orchestrator.md) ∥ Пакет D (plankestrator.md) ∥ Пакет E (документация) | Все правки внутри каждого пакета — строго последовательно |

---

## Рекомендация 1 — Согласовать слои разрешений `todowrite`/`question` (Проблема №1, приоритет High)

### Цель

Все слои конфигурации (frontmatter агентов, opencode.json, ARCHITECTURE.md, AGENTS.md, runtime-гейт плагина) единообразны: `todowrite: deny` и `question: deny` для обоих primary agents; «мёртвые» гранты `unity-mcp.*` и семи `serena_*` удалены из обеих primary-секций opencode.json; списки PROHIBITIONS в промптах покрывают запрещённые инструменты (защита в глубину); вымышленный «layer 2» (`tools:` поле frontmatter) удалён из ARCHITECTURE.md. Выбранный путь — **путь deny** (соответствует lockdown-таблице ARCHITECTURE.md L166–178 и гейту плагина `PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}` на L466); альтернативный путь (сохранить инструменты → обновить таблицу ARCHITECTURE.md и добавить инструменты в `PRIMARY_AGENT_ALLOWED_TOOLS`) **не применяется**.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (frontmatter L15, PROHIBITIONS L120)
2. `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (frontmatter L12, L15, PROHIBITIONS L110)
3. `C:\Users\Admin\.config\opencode\opencode.json` (orchestrator: L1227–1239; plankestrator: L1416–1427)
4. `P:\Programming\Рефакторинг\ARCHITECTURE.md` (L180–185)
5. `P:\Programming\Рефакторинг\AGENTS.md` (L207)
6. `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` — **без изменений** на выбранном пути (L466 `PRIMARY_AGENT_ALLOWED_TOOLS` уже корректен; правка потребовалась бы только на альтернативном пути)

### Пошаговые действия

1. **orchestrator.md, frontmatter, строка 15:** заменить
   ```yaml
     todowrite: allow
   ```
   на
   ```yaml
     todowrite: deny
   ```
   (`question: deny` на строке 12 уже установлен — не трогать.)
2. **orchestrator.md, PROHIBITIONS, строка 120:** заменить
   ```
   - 🚫 No edit/write/patch/bash/webfetch/question — those tools belong to specialist agents.
   ```
   на
   ```
   - 🚫 No edit/write/patch/bash/webfetch/question/todowrite — those tools belong to specialist agents.
   ```
3. **plankestrator.md, frontmatter, строка 12:** заменить `  question: allow` на `  question: deny`.
4. **plankestrator.md, frontmatter, строка 15:** заменить `  todowrite: allow` на `  todowrite: deny`.
5. **plankestrator.md, PROHIBITIONS, строка 110:** заменить
   ```
   - 🚫 No edit/write/patch/bash/webfetch — those tools belong to specialist agents. Plan and research FILES are written by plan-writer-* / research-writer-* via Task, never by you.
   ```
   на
   ```
   - 🚫 No edit/write/patch/bash/webfetch/question/todowrite — those tools belong to specialist agents. Plan and research FILES are written by plan-writer-* / research-writer-* via Task, never by you.
   ```
6. **opencode.json, секция `orchestrator` (L1221–1239):**
   1. Строка 1230: заменить `"todowrite": "allow",` на `"todowrite": "deny",` (строка 1227 `"question": "deny"` уже корректна — не трогать).
   2. Удалить строки 1232–1239 целиком (8 ключей): `"unity-mcp.*": "allow",` и семь ключей `"serena_find_symbol"`, `"serena_find_referencing_symbols"`, `"serena_get_symbols_overview"`, `"serena_rename_symbol"`, `"serena_safe_delete_symbol"`, `"serena_replace_symbol_body"`, `"serena_insert_after_symbol"` (все со значением `"allow"`).
   3. Результат: после `"patch": "deny",` (L1231) сразу следует `"task": {` (L1240). Запятая после `"patch": "deny"` сохраняется — JSON остаётся валидным.
   4. **Внимание:** секции других агентов (subagents) содержат такие же ключи `unity-mcp.*` / `serena_*` легально — удалять ТОЛЬКО внутри секции `"orchestrator"`.
7. **opencode.json, секция `plankestrator` (L1409–1427):**
   1. Строка 1416: заменить `"question": "allow",` на `"question": "deny",`.
   2. Строка 1418: заменить `"todowrite": "allow",` на `"todowrite": "deny",`.
   3. Удалить строки 1420–1427 целиком (те же 8 ключей: `"unity-mcp.*"` + семь `serena_*`).
   4. Результат: после `"patch": "deny",` (L1419) сразу следует `"task": {` (L1428).
8. **ARCHITECTURE.md, строки 180–185:** убрать вымышленный «layer 2». Заменить блок
   ```
   **Defense in depth — this lock is enforced by 4 layers:**

   1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
   2. **`tools:` field in agent.md frontmatter** — secondary belt-and-suspenders
   3. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
   4. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
   ```
   на
   ```
   **Defense in depth — this lock is enforced by 3 layers:**

   1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
   2. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
   3. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
   ```
   Таблицу lockdown L166–178 **не менять** — после шагов 1–7 конфигурация будет ей соответствовать (`question: deny`, `todowrite: deny` у обоих агентов).
9. **AGENTS.md (проектный), строка 207:** заменить
   ```
   | `task` (delegate), `read`, `glob`, `grep` (inspection), `todowrite`, `question` | `bash`, `edit`, `write`, `patch`, `webfetch`, MCP action tools |
   ```
   на
   ```
   | `task` (delegate), `read`, `glob`, `grep` (inspection) | `bash`, `edit`, `write`, `patch`, `webfetch`, `todowrite`, `question`, MCP action tools |
   ```
   (Опционально, вне объёма отчёта: применить ту же замену в копии `deploy-package\project-files\AGENTS.md` L207.)

### Ожидаемый результат

- В frontmatter обоих агентов и в обеих primary-секциях opencode.json: `todowrite: deny`, `question: deny` — все четыре источника совпадают с таблицей ARCHITECTURE.md L166–178.
- В primary-секциях opencode.json отсутствуют ключи `unity-mcp.*` и `serena_*` (~9 «мёртвых» инструментов на каждого primary устранены); в секциях subagents они сохранены.
- Модель больше не видит `todowrite`/`question`/`unity-mcp.*`/`serena_*` в тулсете primary agents → исчезают runtime-исключения `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` (L466–510 плагина) на этих инструментах.
- PROHIBITIONS: orchestrator.md запрещает `todowrite` (строка 120), plankestrator.md запрещает `question` и `todowrite` (строка 110) — защита в глубину восстановлена.
- ARCHITECTURE.md описывает 3 реальных слоя защиты, без ссылки на несуществующее поле `tools:` frontmatter.
- Проверка: `grep -n "todowrite\|question"` по orchestrator.md, plankestrator.md → только `deny`; grep по primary-секциям opencode.json → нет `unity-mcp`/`serena_`; `JSON.parse(opencode.json)` без ошибок.

### Зависимости

- Правки opencode.json выполнять **одним проходом вместе с Рекомендацией 2**, снизу вверх (см. «Порядок выполнения»).
- Правки orchestrator.md выполнять одним проходом вместе с Рекомендациями 4–7.
- Не зависит от Рекомендации 3; после перезапуска opencode валидна совместно со всеми остальными.

---

## Рекомендация 2 — Сократить JSON task-allowlist plankestrator (Проблема №2, приоритет High)

### Цель

Task-allowlist plankestrator в opencode.json совпадает с plugin routing table и `OPENCODE_ROUTING_TABLE` plankestrator.md — ровно 9 агентов. Агенты `view-image`, `generate-image`, `generate-image-gpt` удалены из allowlist (они есть только в whitelist orchestrator). Устраняется риск молчаливой мутации `currentAgent` в `orchestrator` через routing-fallback плагина с последующей валидацией JSON plankestrator по схеме orchestrator (предупреждения «INVALID JSON OUTPUT» из-за отсутствия полей `plan_exists`/`plan_source`). Альтернативный путь (сохранить image-агентов → добавить их в `ROUTING_TABLES.plankestrator` плагина **и** в `OPENCODE_ROUTING_TABLE` plankestrator.md L26) **не применяется**.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\opencode.json` (строки 1440–1442, секция `plankestrator` → `permission` → `task`)

### Пошаговые действия

1. В секции `plankestrator.permission.task` (L1428–1443) удалить строки 1440–1442:
   ```json
             "view-image": "allow",
             "generate-image": "allow",
             "generate-image-gpt": "allow"
   ```
2. **Критично для валидности JSON:** строка 1439 `"devops-readonly": "allow",` становится последней перед закрывающей `}` — удалить её завершающую запятую:
   ```json
             "devops-readonly": "allow"
   ```
3. Итоговый блок `task` должен содержать 11 ключей (9 × `"allow"` + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`):
   ```json
           "task": {
             "*": "deny",
             "plankestrator-identity-probe": "allow",
             "orchestrator-identity-probe": "deny",
             "plan-writer-simple": "allow",
             "plan-writer-complex": "allow",
             "plan-reviewer-simple": "allow",
             "plan-reviewer-complex": "allow",
             "research-writer-simple": "allow",
             "research-writer-complex": "allow",
             "research-reviewer": "allow",
             "devops-readonly": "allow"
           }
   ```
4. **Внимание:** не трогать одноимённые ключи `view-image`/`generate-image`/`generate-image-gpt` в секции `orchestrator` (L1262, L1264, L1265) — там они легальны (24-агентный whitelist).

### Ожидаемый результат

- Ровно 9 записей `"allow"` в task-allowlist plankestrator — поагентно совпадают с `ROUTING_TABLES.plankestrator` плагина и `OPENCODE_ROUTING_TABLE` (plankestrator.md L26): plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly.
- `view-image`, `generate-image`, `generate-image-gpt` отсутствуют в секции plankestrator.
- opencode.json остаётся валидным JSON (проверка парсером обязательна — риск висячей запятой).
- Попытка plankestrator вызвать image-агента отклоняется на уровне конфигурации (`"*": "deny"`), а не проходит в routing-fallback плагина.

### Зависимости

- Выполняется одним проходом по opencode.json вместе с Рекомендацией 1 (шаги 6–7); **порядок внутри файла — снизу вверх**: сначала L1440–1442 (эта рекомендация), затем L1416–1427 (Рек. 1, plankestrator), затем L1227–1239 (Рек. 1, orchestrator).
- Логически связана с Рекомендацией 3: Рек. 2 устраняет триггер, Рек. 3 — сам латентный баг fallback'а. Выполнить обе.

---

## Рекомендация 3 — Защитить routing-fallback identity lock'ом (Проблема №3, приоритет High)

### Цель

Fallback в `tool.execute.before` (L643–656) не переключает `currentAgent`, когда сессия залочена (`identityLocked === true`), а бросает routing-table violation. Гарантия v3-лока («агент не может быть перепривязан после этого момента», ARCHITECTURE.md L541) соблюдается на обоих enforcement-хуках — и в `message.updated` (L337–353, уже корректен), и в `tool.execute.before`.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (строки 643–656, ветка fallback'а внутри `tool.execute.before`)

### Пошаговые действия

1. Найти блок (L643–656):
   ```ts
           if (otherAllowedAgents.includes(targetAgent)) {
             // Switch to the correct agent based on routing
             const previousAgent = currentAgent
             currentAgent = otherAgent
             // FIX: Set to TRUE — agent already outputted JSON at beginning of response
             hasOutputtedJSON.set(otherAgent, true)

             await client.app.log({
               body: {
                 service: "workflow-enforcement",
                 level: "warn",
                 message: `Agent corrected via routing fallback: was ${previousAgent}, now ${otherAgent} (called ${targetAgent})`
               }
             })
           } else {
   ```
2. Заменить его на (переменные `identityLocked`, `lockedAgentName`, `otherAgent`, `allowedAgents` уже доступны в этой области — они используются выше в том же хендлере, см. hard-gate L467–469):
   ```ts
           if (identityLocked && otherAllowedAgents.includes(targetAgent)) {
             // FIX: v3 identity lock — a locked session MUST NOT be re-bound by the
             // routing fallback. Treat as a hard routing-table violation instead.
             throw new Error(`
   WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)

   Locked Agent: ${lockedAgentName}
   Current Agent: ${currentAgent}
   Attempted Call: ${targetAgent}
   Allowed Agents: ${allowedAgents.join(", ")}

   "${targetAgent}" belongs to the ${otherAgent} whitelist, but this session is
   identity-locked to ${lockedAgentName} (v3 lock: the agent cannot be re-bound).
   Do NOT call agents outside your own routing table.

   Orchestrator handles: BUGFIX, DEVOPS, DEV, DOCS
   Plankestrator handles: PLAN, RESEARCH, RESEARCH+PLAN
             `)
           } else if (otherAllowedAgents.includes(targetAgent)) {
             // Switch to the correct agent based on routing (UNLOCKED sessions only —
             // race condition mitigation when message.updated has not fired yet)
             const previousAgent = currentAgent
             currentAgent = otherAgent
             // FIX: Set to TRUE — agent already outputted JSON at beginning of response
             hasOutputtedJSON.set(otherAgent, true)

             await client.app.log({
               body: {
                 service: "workflow-enforcement",
                 level: "warn",
                 message: `Agent corrected via routing fallback: was ${previousAgent}, now ${otherAgent} (called ${targetAgent})`
               }
             })
           } else {
   ```
3. Существующую ветку `else` (L657–672, «Neither whitelist includes targetAgent → genuine violation» с throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT`) **оставить без изменений**.
4. Обработчик дрейфа в `message.updated` (L337–353) **не менять** — он уже соблюдает лок.
5. `FORBIDDEN_VOCAB` (L88–99) **не менять** — см. Рекомендацию 5 (правится промпт, а не список токенов).

### Ожидаемый результат

- При `identityLocked === true` вызов Task с субагентом из whitelist **другого** primary бросает исключение `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)` вместо warn-лога «Agent corrected via routing fallback» и мутации `currentAgent`.
- Для незаблокированных сессий (`identityLocked === false`) прежнее поведение fallback'а (race-condition mitigation) сохранено.
- Файл остаётся валидным TypeScript: перезапуск opencode проходит, в логах есть `Workflow enforcement plugin initialized`, нет ошибок загрузки плагина.

### Зависимости

- Полностью независима от других рекомендаций по файлам — может выполняться **параллельно** со всеми остальными пакетами.
- Логически связана с Рекомендацией 2 (устраняет триггер) — рекомендуется выполнять обе в одной фазе High.
- Требует перезапуска opencode (плагины загружаются при старте).

---

## Рекомендация 4 — Исправить замечание о rework-loop (Проблема №4, приоритет Medium)

### Цель

Замечание в orchestrator.md L59 покрывает **все** строки пайплайнов, содержащие `consistency-checker` с rework-loop: 1-DEEP, 4 (DEV SIMPLE с планом — возврат к `worker`, ARCHITECTURE.md L257), 5, 6 (DEV SUPERCOMPLEX — per-step loop, ARCHITECTURE.md L282), 8. Риск того, что модель пропустит обязательный rework-loop для строк 4 и 6, устранён.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (строка 59)

### Пошаговые действия

1. Заменить строку 59:
   ```
   **Rework loop (rows 1-DEEP, 5, 8):** if consistency-checker reports critical issues, return to `rework` (or the agent named in its `escalate_to`), max 3 iterations, then `utility`.
   ```
   на (точная формулировка из отчёта):
   ```
   **Rework loop (rows 1-DEEP, 4, 5, 6, 8):** if consistency-checker reports critical issues, return to the agent named in its `escalate_to` (default `rework`; `worker` for row 4), max 3 iterations, then `utility`.
   ```

### Ожидаемый результат

- Строка 59 перечисляет rows «1-DEEP, 4, 5, 6, 8»; цель возврата — агент из `escalate_to` (по умолчанию `rework`, для строки 4 — `worker`); лимит 3 итерации, затем `utility`.
- Замечание согласовано с ARCHITECTURE.md: L244 (общий loop), L257 (DEV SIMPLE с планом → worker), L265 (DEV COMPLEX → rework), L282 (DEV SUPERCOMPLEX per-step → rework).
- Проверка: `grep -n "Rework loop" orchestrator.md` → новая формулировка; grep по `rows 1-DEEP, 4, 5, 6, 8` → ровно одно совпадение.

### Зависимости

- Независима по содержанию; выполняется в одном проходе по orchestrator.md с Рекомендациями 1 (L15, L120), 5 (L109), 6 (L49), 7 (L118–125).
- Перезапуск opencode (или новая сессия) для подхвата промпта.

---

## Рекомендация 5 — «Обезвредить» литеральные запрещённые токены в orchestrator.md L109 (Проблема №5, приоритет Low)

### Цель

Правило детекции `plan_exists=true` в orchestrator.md L109 больше не содержит литеральных строк `"## PLAN"` и `"# Implementation Plan"` — обе входят в `FORBIDDEN_VOCAB` orchestrator (workflow-enforcement.ts L91). Ложноположительные ошибки `FORBIDDEN VOCABULARY DETECTED` (обработка L414–432) при дословном цитировании правила моделью исключены. Семантика правила сохранена полностью.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (строка 109)

Список `FORBIDDEN_VOCAB` в `workflow-enforcement.ts` (L88–99) **не менять**.

### Пошаговые действия

1. Заменить строку 109:
   ```
   **plan_exists=true** if conversation contains: plankestrator JSON with `"type": "PLAN"` / `"state": "COMPLETE"`; a "## PLAN" / "# Implementation Plan" heading; or user references a plan ("implement the plan", "the plan above"). Then `plan_source` = where it came from. Applies to DEV only.
   ```
   на (описание заголовков без литеральных токенов — приём из отчёта: «an H2 heading whose text is PLAN»):
   ```
   **plan_exists=true** if conversation contains: plankestrator JSON with `"type": "PLAN"` / `"state": "COMPLETE"`; a markdown plan heading (an H2 heading whose text is PLAN, or an H1 heading whose text is Implementation Plan); or user references a plan ("implement the plan", "the plan above"). Then `plan_source` = where it came from. Applies to DEV only.
   ```
2. Убедиться, что в новой строке отсутствуют подстроки `## PLAN` и `# Implementation Plan` (включая решётку с пробелом) — проверка grep'ом по файлу.

### Ожидаемый результат

- В orchestrator.md нет вхождений литералов `## PLAN` и `# Implementation Plan` (проверка: grep по этим строкам возвращает 0 совпадений в orchestrator.md).
- Правило классификации `plan_exists=true` функционально идентично прежнему.
- При цитировании правила в сообщениях orchestrator плагин не логирует `FORBIDDEN VOCABULARY DETECTED` (level: error) — шумные error-логи и ложные сигналы дрейфа идентичности исчезают.

### Зависимости

- Независима; выполняется в одном проходе по orchestrator.md с Рекомендациями 1, 4, 6, 7.
- Не требует правок плагина (в отличие от Рек. 3 — разные участки файла, конфликтов нет).
- Перезапуск opencode (или новая сессия) для подхвата промпта.

---

## Рекомендация 6 — Исправить ячейку `plan_exists` строки 5 таблицы пайплайнов (Проблема №6, приоритет Low)

### Цель

Ячейка `plan_exists` в строке 5 (DEV COMPLEX) таблицы orchestrator.md L49 читается как `true`, а не `any`, и согласована с правилом классификации L116 («plan_exists=false + complexity=COMPLEX (DEV) → OUT OF SCOPE, send user to plankestrator»). Вводящая в заблуждение недостижимая комбинация устранена из документации промпта.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (строка 49, ячейка `plan_exists` таблицы L43–52)

### Пошаговые действия

1. В строке 49 заменить только ячейку `any` на `true`:
   ```
   | 5 | DEV | COMPLEX | any | `["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]` |
   ```
   на
   ```
   | 5 | DEV | COMPLEX | true | `["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]` |
   ```
2. Ячейки `any` в строках 7 (DOCS SIMPLE, L51) и 8 (DOCS DEEP, L52) **не менять** — правило L116 относится только к DEV.

### Ожидаемый результат

- Строка 5 таблицы: `| 5 | DEV | COMPLEX | true | ... |`.
- Таблица не противоречит L116: DEV COMPLEX при `plan_exists=false` недостижим (маршрутизируется в OUT OF SCOPE → plankestrator).
- Проверка: grep `| 5 | DEV | COMPLEX | true |` → одно совпадение.

### Зависимости

- Независима; выполняется в одном проходе по orchestrator.md с Рекомендациями 1, 4, 5, 7.
- Перезапуск opencode (или новая сессия) для подхвата промпта.

---

## Рекомендация 7 — Усилить PROHIBITIONS orchestrator (опциональное усиление, приоритет Low)

### Цель

Список PROHIBITIONS orchestrator.md (L118–125) содержит два явных запрета по образцу plankestrator.md (L112–113): обязательность dev-reviewer / consistency-checker и ограничение «один Task-вызов за ход».

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (секция `## PROHIBITIONS — VIOLATION = FAILURE`, L118–125)

### Пошаговые действия

1. Вставить два новых пункта после строки 124 (`- 🚫 No read/glob/grep during pipeline execution (Turns 2..N).`), перед строкой 125 (`- 🚫 Never route to plankestrator, ...`):
   ```
   - 🚫 No skipping dev-reviewer / consistency-checker — they are mandatory pipeline elements.
   - 🚫 No more than ONE Task call per turn. One turn = one pipeline step.
   ```
   (Формулировки — по образцу plankestrator.md L112 «No skipping the reviewer. Reviewers are mandatory pipeline elements.» и L113 «No more than ONE Task call per turn. One turn = one pipeline step.»)
2. Если правка строки 120 (Рек. 1, шаг 2) ещё не выполнена — выполнить её в этом же проходе.

### Ожидаемый результат

- Секция PROHIBITIONS orchestrator.md содержит 8 пунктов (было 6): добавлены запреты на пропуск dev-reviewer/consistency-checker и на более одного Task-вызова за ход.
- Проверка: grep по `No skipping dev-reviewer` и `No more than ONE Task call per turn` в orchestrator.md → по одному совпадению.

### Зависимости

- Независима по содержанию; выполняется в одном проходе по orchestrator.md с Рекомендациями 1, 4, 5, 6 (обе правки касаются секции PROHIBITIONS — не конфликтовать по строкам).
- Перезапуск opencode (или новая сессия) для подхвата промпта.

---

## Верификация

Выполняется после завершения всех фаз и **одного перезапуска opencode**.

### 1. Статические проверки (до перезапуска)

1. **Валидность JSON** (критично после удалений строк и правки запятых):
   ```
   node -e "JSON.parse(require('fs').readFileSync('C:/Users/Admin/.config/opencode/opencode.json','utf8')); console.log('JSON OK')"
   ```
   Ожидание: `JSON OK`, без `SyntaxError`.
2. **orchestrator.md:**
   - frontmatter: `todowrite: deny` (L15), `question: deny` (L12);
   - строка 49: `| 5 | DEV | COMPLEX | true |`;
   - строка 59: `**Rework loop (rows 1-DEEP, 4, 5, 6, 8):**` с `escalate_to` / default `rework` / `worker` for row 4;
   - строка 109: отсутствуют литералы `## PLAN` и `# Implementation Plan` (grep → 0 совпадений в файле);
   - PROHIBITIONS: пункт с `question/todowrite` (L120), пункты «No skipping dev-reviewer / consistency-checker» и «No more than ONE Task call per turn» — всего 8 пунктов.
3. **plankestrator.md:**
   - frontmatter: `question: deny` (L12), `todowrite: deny` (L15);
   - PROHIBITIONS L110: содержит `question/todowrite`;
   - `OPENCODE_ROUTING_TABLE` (L26) не изменилась — 9 агентов.
4. **opencode.json, секция `orchestrator`:** `"question": "deny"`, `"todowrite": "deny"`; нет ключей `unity-mcp.*` и `serena_*`; task-блок сохраняет 24 агента (включая `view-image`, `generate-image`, `generate-image-gpt`, `git-commit`).
5. **opencode.json, секция `plankestrator`:** `"question": "deny"`, `"todowrite": "deny"`; нет ключей `unity-mcp.*` и `serena_*`; task-блок: ровно 9 записей `"allow"` (plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly) + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`; записи `view-image`/`generate-image`/`generate-image-gpt` отсутствуют.
6. **Секции subagents в opencode.json не затронуты:** ключи `unity-mcp.*`/`serena_*` сохранены у всех агентов вне двух primary-секций (выборочная проверка, например `plan-writer-simple`, `mcp-search`).
7. **workflow-enforcement.ts:**
   - в ветке fallback'а (`tool.execute.before`) первая проверка — `if (identityLocked && otherAllowedAgents.includes(targetAgent))` с throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)`;
   - переключение `currentAgent = otherAgent` осталось только в ветке для незаблокированных сессий;
   - `PRIMARY_AGENT_ALLOWED_TOOLS` (L466) не изменён: `{task, read, glob, grep}`;
   - `FORBIDDEN_VOCAB` (L88–99) не изменён;
   - синтаксис TypeScript валиден (файл загружается без ошибок — проверяется на шаге 8).
8. **ARCHITECTURE.md:** «enforced by **3** layers», пункт про `tools:` field frontmatter удалён, нумерация 1–3; таблица L166–178 не изменена.
9. **AGENTS.md (L207):** `todowrite`, `question` перемещены в колонку Forbidden.

### 2. Перезапуск и проверки загрузки

1. Перезапустить opencode (все изменения `~/.config/opencode` — opencode.json, agents/*.md, plugins/*.ts — подхватываются только при перезапуске/новой сессии).
2. В логах присутствует `Workflow enforcement plugin initialized` — плагин загрузился без ошибок компиляции.

### 3. Функциональные проверки (в новых сессиях)

1. **Сессия orchestrator:**
   - в тулсете модели отсутствуют `todowrite`, `question`, `unity-mcp.*`, `serena_*` (инструменты не инжектируются — deny на уровне merged permission ruleset);
   - штатный пайплайн работает: identity line + валидный JSON (8 полей) + один Task-вызов за ход; в логах нет `PRIMARY AGENT ACTION TOOL VIOLATION` и нет `INVALID JSON OUTPUT`.
2. **Сессия plankestrator:**
   - штатный пайплайн работает (JSON из 7 полей валиден);
   - **проверка Рек. 2 + Рек. 3:** попытка вызвать Task с `subagent_type: "view-image"` отклоняется: на уровне конфига (`"*": "deny"`), а если вызов доходит до плагина — throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)`;
   - в логах **нет** warn `Agent corrected via routing fallback`, `currentAgent` остаётся `plankestrator`, `lockedAgentName` не меняется; последующие JSON plankestrator валидируются по схеме plankestrator (нет предупреждений об отсутствии `plan_exists`/`plan_source`).
3. **Проверка Рек. 5:** в сессии orchestrator процитировать/спровоцировать текст правила `plan_exists` — в логах нет error `FORBIDDEN VOCABULARY DETECTED`.
4. **Проверка Рек. 4 (наблюдательная):** при прогоне DEV SIMPLE с планом (строка 4) или DEV SUPERCOMPLEX (строка 6) с критическими замечаниями consistency-checker orchestrator выполняет rework-loop (возврат к `worker` для строки 4 / к `rework` для строки 6, max 3 итерации, затем `utility`).

### 4. Финальная консистентность

- Прогнать `consistency-checker` против ARCHITECTURE.md: конфигурация обоих primary agents соответствует lockdown-таблице L166–178, routing tables идентичны во всех трёх источниках (orchestrator — 24 агента, plankestrator — 9 агентов), описание слоёв защиты (3 layers) соответствует реальности.

**Критерий успеха всего плана:** все проверки раздела «Верификация» пройдены; в контрольных сессиях отсутствуют error-логи `PRIMARY AGENT ACTION TOOL VIOLATION`, `IDENTITY DRIFT REJECTED`, `FORBIDDEN VOCABULARY DETECTED`, `INVALID JSON OUTPUT` и warn-лог `Agent corrected via routing fallback` для залоченных сессий.

---

## Примечания для исполнителя

1. **Смещение номеров строк:** все удаления в opencode.json (8 строк в секции orchestrator + 8 строк в секции plankestrator + 3 строки task-allowlist) смещают последующие строки. Правки выполнять либо точной заменой строк (string replace), либо снизу вверх в порядке: L1440–1442 → L1416–1427 → L1227–1239. Аналогично для orchestrator.md при правке по номерам: L118–125 → L109 → L59 → L49 → L15.
2. **Запятые в JSON:** единственная правка запятой — строка 1439 (`"devops-readonly": "allow",` → без запятой, Рек. 2, шаг 2). Удаления L1232–1239 и L1420–1427 правки запятых не требуют (после `"patch": "deny",` следует `"task": {`).
3. **Не выходить за объём:** секции subagents в opencode.json, списки `FORBIDDEN_VOCAB`, `PRIMARY_AGENT_ALLOWED_TOOLS`, обработчик `message.updated` (L337–353), таблица ARCHITECTURE.md L166–178, `OPENCODE_ROUTING_TABLE` plankestrator.md L26 — не менять.
4. **Требование перезапуска:** рекомендации 1–7 — один общий перезапуск opencode после всех правок (Фаза 4). До перезапуска изменения конфигурации, промптов и плагина в силу не вступают.
