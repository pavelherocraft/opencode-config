# Исследование: Вариант B — разрешить `view-image` в plankestrator

**Дата:** 2026-09-07
**Основание:** `P:\Programming\Рефакторинг\REMEDIATION_PLAN.md` (Рек. 2, альтернативный путь из L174) + `VALIDATION_REPORT.md` (Проблема №2, Рек. №2 — «если генерация изображений из планировочных сессий — желаемая фича»)
**Суть Варианта B:** вместо удаления `view-image` из task-allowlist plankestrator — легализовать его, добавив во **все** слои routing table (промпт, плагин, ARCHITECTURE.md), а из allowlist удалить только `generate-image` / `generate-image-gpt` (инструменты генерации, не анализа — в планировочных сессиях не нужны).

---

## 1. Текущее состояние view-image в конфигурации

### 1.1. Orchestrator — view-image легален во всех слоях (эталон согласованности)

| Слой | Файл | Строка | Значение |
|------|------|--------|----------|
| Промпт | `C:\Users\Admin\.config\opencode\agents\orchestrator.md` | L26 | `view-image` входит в `OPENCODE_ROUTING_TABLE` (24 агента) |
| Плагин | `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | L27 | `"view-image",` в `ROUTING_TABLES.orchestrator` (L7–32) |
| JSON | `C:\Users\Admin\.config\opencode\opencode.json` | L1262 | `"view-image": "allow",` в секции `orchestrator` (начало секции L1218); также `generate-image` L1264, `generate-image-gpt` L1265 |
| Документация | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | L30 | `\| 20 \| view-image \| Image analysis \|` в таблице «orchestrator Whitelist (24 agents)» (L7–34) |

**Вывод:** для orchestrator менять ничего не нужно — все четыре слоя уже содержат view-image.

### 1.2. Plankestrator — view-image разрешён ТОЛЬКО в opencode.json (рассинхрон, Проблема №2)

| Слой | Файл | Строка | Значение |
|------|------|--------|----------|
| Промпт | `C:\Users\Admin\.config\opencode\agents\plankestrator.md` | L26 | `OPENCODE_ROUTING_TABLE` — 9 агентов, **view-image отсутствует** |
| Плагин | `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | L33–43 | `ROUTING_TABLES.plankestrator` — 9 агентов, последний `"devops-readonly"` на **L42** (без запятой), закрывающая `]` на L43. **view-image отсутствует** |
| JSON | `C:\Users\Admin\.config\opencode\opencode.json` | **L1440** | `"view-image": "allow",` (с запятой); L1441 `"generate-image": "allow",`; L1442 `"generate-image-gpt": "allow"` (последний, без запятой). Секция `plankestrator` L1406, блок `task` L1428–1443, `"devops-readonly": "allow",` на L1439 |
| Документация | `P:\Programming\Рефакторинг\ARCHITECTURE.md` | L36–48 | «plankestrator Whitelist (9 agents)», последняя строка таблицы L48: `\| 9 \| devops-readonly \| DevOps read-only \|`. **view-image отсутствует** |

### 1.3. Сводные счётчики и копии документации

| Файл | Строки | Содержимое |
|------|--------|------------|
| `ARCHITECTURE.md` | L50–56 | Agent Count Summary: L55 `\| plankestrator \| 9 \| 10 (plankestrator + 9 subagents) \|`; L56 Grand Total `**33**` / `**35**`; L58 примечание «33 unique subagents + 2 primary = 35» |
| `P:\Programming\Рефакторинг\AGENTS.md` | L240–252 | «plankestrator Whitelist (9 agents)», последняя строка L252 `\| devops-readonly \| DevOps read-only \|` |
| `P:\Programming\Рефакторинг\MCP_SETUP.md` | L393–394 | «Task Whitelist (9 agents):» + список; L691–705 — вторая копия таблицы whitelist; L911–912 — routing tables плагина в документации |
| `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` | L33–45 | Копия: «plankestrator Whitelist (9 agents)», L45 `\| 9 \| devops-readonly \|` |
| `P:\Programming\Рефакторинг\opencode-config\AGENTS.md` | L229–241 | Копия таблицы (9 agents) |
| `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md` | L154, L206, L848–860 | Копии routing table плагина в документации |
| `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` | L30–40 | Копия плагина: plankestrator — 9 агентов, без view-image |
| `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` | L10–14 | **Противоречие внутри deploy-package:** L10–11 — «plankestrator Whitelist (9 agents)» без view-image, но L13–14 — секция «Shared Utility Agents»: «view-image is a shared utility agent available to BOTH primary agents… also granted `task.view-image: allow` in the plankestrator permission block in opencode.json». Т.е. deploy-package уже описывает Вариант B как целевой дизайн, не отражённый в routing tables |

### 1.4. Смежные факты

- `plankestrator-identity-probe` уже имеет `view-image` в task-allowlist (MCP_SETUP.md L418) — прецедент «планировочный субагент + view-image» существует.
- `research-writer-simple.md` и `research-writer-complex.md` имеют `"view-image": "allow"` (L16 в обоих файлах) — writer-агенты plankestrator-пайплайнов уже могут вызывать view-image напрямую. Вариант B добавляет эту возможность самому роутеру.
- Плагин: обратный поиск `detectAgentFromSubagent` (L870–877) итерирует `Object.entries(ROUTING_TABLES)` и возвращает **первое** совпадение — orchestrator идёт первым. Важно: функция используется **только** как hint-диагностика при `!currentAgent` (вызов на L537–556, комментарий «REMOVED: state mutation from reverse routing lookup … NO state mutation» на L518–536) — результат попадает лишь в info-лог «Reverse routing hint (not enforced)». Это важно для оценки рисков (раздел 4).

---

## 2. Необходимые изменения для Варианта B

### Изменение 1 — `plankestrator.md` (промпт)

**Файл:** `C:\Users\Admin\.config\opencode\agents\plankestrator.md`, **строка 26**.

Заменить:
```
OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly"]
```
на (view-image добавлен в конец списка; примечание: в orchestrator.md L26 view-image стоит на позиции 20 из 24 — после основных рабочих агентов, но НЕ последним; для plankestrator выбрана позиция в конце как простейшая и не влияющая на существующие ссылки):
```
OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly", "view-image"]
```

**Рекомендуемое дополнение (семантика):** routing table разрешает вызов, но промпт plankestrator не описывает, *когда* вызывать view-image. Без правила модель может вызывать его непредсказуемо. Рекомендуется добавить в `## TURN ALGORITHM` (Turn 1, пункт 2, L58) уточнение: view-image допустим как вспомогательный вызов для анализа изображений при классификации (по образцу «read/glob/grep to classify ONLY»), либо явный пункт в CLASSIFICATION RULES. Это выходит за рамки чистой синхронизации таблиц — требует решения.

### Изменение 2 — `workflow-enforcement.ts` (плагин)

**Файл:** `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`, **строки 42–43** (внутри `ROUTING_TABLES.plankestrator`, L33–43).

Заменить:
```ts
    "devops-readonly"
  ]
```
на:
```ts
    "devops-readonly",
    "view-image"
  ]
```
(запятая после `"devops-readonly"` на L42 обязательна; новая строка вставляется перед закрывающей `]` на L43).

Больше в плагине ничего менять не нужно: `REQUIRED_JSON_FIELDS` (L49–52), `VALID_VALUES`, `PRIMARY_AGENT_ALLOWED_TOOLS` (L466), `FORBIDDEN_VOCAB` (L88–99) не затрагиваются. Fallback-логика (L636–656) начнёт работать корректно автоматически: view-image будет находиться в `allowedAgents` текущего агента, и ветка `otherAgent` для него больше не сработает.

**То же изменение** применить к копии `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` (L39–40).

### Изменение 3 — `ARCHITECTURE.md` (источник истины)

**Файл:** `P:\Programming\Рефакторинг\ARCHITECTURE.md`.

1. **L36:** `### plankestrator Whitelist (9 agents)` → `### plankestrator Whitelist (10 agents)`.
2. **После L48** вставить строку таблицы:
   ```
   | 10 | view-image | Image analysis |
   ```
3. **L55:** `| plankestrator | 9 | 10 (plankestrator + 9 subagents) |` → `| plankestrator | 10 | 11 (plankestrator + 10 subagents) |`.
4. **L56:** Grand Total: `| **Grand Total** | **33** | **35** |` → `| **Grand Total** | **34** | **35** |` (сумма whitelist-записей 24+10=34; уникальных агентов по-прежнему 35, т.к. view-image уже посчитан в whitelist orchestrator).
5. **L58:** примечание уточнить: «33 unique subagents + 2 primary agents = 35 unique agents total» → «34 whitelist entries (view-image shared by both primaries), 33 unique subagents + 2 primary agents = 35 unique agents total».
6. **Опционально (рекомендуется):** добавить секцию «Shared Utility Agents» по образцу `deploy-package\project-files\ARCHITECTURE.md` L13–14, зафиксировав, что view-image — общий агент обоих primary. Это снимет вопрос «почему один субагент в двух таблицах».

**Ответ на вопрос задачи:** в ARCHITECTURE.md view-image для orchestrator уже есть (L30) — добавлять нужно **только** в таблицу plankestrator. Дублировать строку в таблице orchestrator не нужно.

### Изменение 4 — `opencode.json` (отмена части Рек. 2)

**Файл:** `C:\Users\Admin\.config\opencode\opencode.json`, секция `plankestrator.permission.task` (L1428–1443).

- **L1440** `"view-image": "allow",` — **НЕ удалять** (отмена соответствующей части Рек. 2).
- **L1441–1442** (`"generate-image": "allow",` и `"generate-image-gpt": "allow"`) — **удалить** (эта часть Рек. 2 сохраняется: инструменты генерации изображений в планировочных сессиях не нужны).
- **Критично для валидности JSON:** после удаления L1441–1442 строка L1440 становится последней — убрать завершающую запятую: `"view-image": "allow"`. (В исходной Рек. 2 правка запятой относилась к L1439 `"devops-readonly"` — теперь она смещается на L1440.)
- Итоговый блок `task` — 12 ключей (10 × `"allow"` + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`):
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
          "devops-readonly": "allow",
          "view-image": "allow"
        }
  ```
- **Не трогать** одноимённые ключи в секции `orchestrator` (L1262, L1264, L1265).

### Изменение 5 — синхронизация копий документации

| Файл | Правка |
|------|--------|
| `P:\Programming\Рефакторинг\AGENTS.md` | L240 → «(10 agents)»; после L252 добавить `\| view-image \| Image analysis \|` |
| `P:\Programming\Рефакторинг\MCP_SETUP.md` | L393 → «Task Whitelist (10 agents):», L394 — добавить view-image в список; L691 → «(10 agents)», после L705 — строка таблицы; L911–912 — добавить `"view-image"` в plankestrator-таблицу плагина |
| `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` | L33 → «(10 agents)», после L45 — `\| 10 \| view-image \| Image analysis \|` |
| `P:\Programming\Рефакторинг\opencode-config\AGENTS.md` | L229 → «(10 agents)», после L241 — строка таблицы |
| `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md` | L154 → «(10 agents)» + строка таблицы; L206/L860 — `"view-image"` в копиях routing table |
| `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` | Аналогично AGENTS.md (заголовок «plankestrator Whitelist (9 agents)» — L237, последняя строка таблицы L249) |
| `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` | L10–11 → «(10 agents)» + view-image в список; L13–14 («Shared Utility Agents») — **уже корректно описывает Вариант B**, привести в соответствие с фактом (view-image теперь в routing table plankestrator, а не только в permission block) |
| `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` | См. Изменение 2 |

---

## 3. Затронутые рекомендации из REMEDIATION_PLAN.md

### 3.1. Рек. 2 (L170–220) — скорректировать

| Элемент | Текущее содержание | Новое содержание |
|---------|-------------------|------------------|
| Заголовок/Цель (L172–174) | «Сократить JSON task-allowlist plankestrator… ровно 9 агентов. Агенты `view-image`, `generate-image`, `generate-image-gpt` удалены… Альтернативный путь … **не применяется**» | «…ровно 10 агентов. Удалены только `generate-image`, `generate-image-gpt`. **Применяется альтернативный путь для `view-image`**: он добавлен в `ROUTING_TABLES.plankestrator` плагина и в `OPENCODE_ROUTING_TABLE` plankestrator.md L26 (см. Рек. 2b)» |
| Шаг 1 (L182–187) | Удалить L1440–1442 (3 строки) | Удалить **только L1441–1442** (2 строки: generate-image, generate-image-gpt) |
| Шаг 2 (L188–191) | Правка запятой на L1439 (`"devops-readonly": "allow",` → без запятой) | Правка запятой на **L1440** (`"view-image": "allow",` → без запятой); L1439 не трогать |
| Шаг 3 (L192–207) | Итоговый блок — 11 ключей (9 allow) | Итоговый блок — **12 ключей (10 allow)**, с `"view-image": "allow"` последним |
| Ожидаемый результат (L212–215) | «Ровно 9 записей allow… view-image отсутствует… Попытка вызвать image-агента отклоняется» | «Ровно 10 записей allow, включая view-image; generate-image/generate-image-gpt отсутствуют. Вызов view-image проходит на всех слоях; вызов generate-image* отклоняется (`"*": "deny"`)» |
| Сводная таблица (L30) | «task-allowlist plankestrator шире routing table» — opencode.json (L1440–1442) | Файлы: opencode.json (**L1441–1442**) |
| Зависимости (L45, L219–220) | «Рек. 2 убирает реалистичный триггер (агенты view-image, generate-image, generate-image-gpt)» | «Рек. 2 убирает триггер для generate-image*; триггер view-image устранён легализацией (Рек. 2b)» |

### 3.2. Новая рекомендация — Рек. 2b «Легализовать view-image в routing tables plankestrator»

Предлагаемое содержание (вставить после Рек. 2):

- **Цель:** `ROUTING_TABLES.plankestrator` плагина, `OPENCODE_ROUTING_TABLE` plankestrator.md и whitelist plankestrator в ARCHITECTURE.md содержат `view-image` (10 агентов) — все три источника routing table идентичны, как требует финальная проверка консистентности (L500).
- **Файлы:**
  1. `workflow-enforcement.ts` (L42–43) — Изменение 2;
  2. `plankestrator.md` (L26) — Изменение 1;
  3. `ARCHITECTURE.md` (L36, после L48, L55, L56, L58) — Изменение 3;
  4. Копии документации — Изменение 5.
- **Зависимости:** физически не пересекается с Рек. 1 (другие строки opencode.json не затрагиваются — Рек. 2b вообще не правит opencode.json); логически заменяет часть Рек. 2. Правку плагина выполнять в том же пакете B, что и Рек. 3 (один файл, править снизу вверх: сначала L643+ Рек. 3, затем L42–43 Рек. 2b — либо точными заменами строк). Требует перезапуска opencode (плагин + промпт).
- **Решение, требующее принятия:** добавлять ли в промпт plankestrator правило, когда допустим вызов view-image (см. Изменение 1, «Рекомендуемое дополнение»).

### 3.3. Секция «Верификация» (L448–502) — обновить

| Строка | Текущая проверка | Новая проверка |
|--------|------------------|----------------|
| L468 (п. 3) | «`OPENCODE_ROUTING_TABLE` (L26) не изменилась — 9 агентов» | «`OPENCODE_ROUTING_TABLE` (L26) — **10 агентов**, включая view-image последним» |
| L470 (п. 5) | «task-блок: ровно 9 записей allow… записи view-image/generate-image/generate-image-gpt отсутствуют» | «task-блок: ровно **10** записей allow (9 прежних + view-image); записи **generate-image/generate-image-gpt** отсутствуют; view-image присутствует» |
| L472–477 (п. 7, плагин) | — | Добавить: «`ROUTING_TABLES.plankestrator` (L33–44) содержит `"view-image"` после `"devops-readonly"` — 10 агентов» |
| L493 (функциональная п. 2) | «попытка вызвать Task с `subagent_type: "view-image"` отклоняется…» | **Переписать полностью:** позитивный тест — вызов view-image из сессии plankestrator **проходит** (конфиг + плагин), `currentAgent` остаётся `plankestrator`, warn «Agent corrected via routing fallback» отсутствует; негативный тест Рек. 2+3 — вызов `generate-image`: отклонён конфигом (`"*": "deny"`), а при достижении плагина — throw `WORKFLOW VIOLATION … (identity lock active)` |
| L500 (п. 4) | «plankestrator — 9 агентов» | «plankestrator — **10 агентов**; routing tables идентичны во всех трёх источниках; view-image — общий агент обоих primary» |
| L508 (примечание 1) | Порядок правок opencode.json «L1440–1442 → …» | «L1441–1442 → …» (удаляются 2 строки, не 3) |
| L509 (примечание 2) | «единственная правка запятой — строка 1439» | «единственная правка запятой — строка **1440**» |
| L510 (примечание 3) | «`OPENCODE_ROUTING_TABLE` plankestrator.md L26 — не менять» | **Удалить этот пункт** из списка «не менять» — L26 теперь меняется (Рек. 2b); уточнить: «не менять `OPENCODE_ROUTING_TABLE` orchestrator.md» |

### 3.4. Части плана, которые НЕ затрагиваются

- Рек. 1 (L71–166) — полностью, кроме порядка прохода по opencode.json (смещение строк после удаления 2 строк вместо 3 — по-прежнему «снизу вверх»).
- Рек. 3 (L224–305) — без изменений; она по-прежнему обязательна: после Варианта B вызов `generate-image` из залоченной сессии plankestrator — это fallback на whitelist orchestrator, и Рек. 3 превращает его в жёсткое нарушение.
- Рек. 4–7 (orchestrator.md) — без изменений.

---

## 4. Риски и побочные эффекты

### 4.1. Неоднозначность обратного поиска (основной технический риск)

`detectAgentFromSubagent` (workflow-enforcement.ts L870–877) возвращает **первого** primary, чей whitelist содержит субагента; orchestrator итерируется первым. После Варианта B view-image входит в **обе** таблицы → для **незалоченной** сессии plankestrator (гонка до срабатывания `session.created`/`message.updated`) обратный поиск по вызову view-image вернёт `"orchestrator"`. Это задокументированная known issue (PLUGIN.md **L763**: «reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables)»; копии: opencode-config\PLUGIN.md L736, deploy-package\project-files\PLUGIN.md L757).

**Уточнение механизма (проверено по коду):** `detectAgentFromSubagent` вызывается только при `!currentAgent` (L537–556) и, согласно комментарию в коде «REMOVED: state mutation from reverse routing lookup» (L518–536), **не мутирует состояние** — результат попадает только в info-лог «Reverse routing hint (not enforced)». Практический эффект неоднозначности после Варианта B — вводящая в заблуждение диагностическая строка в логе, а не перепривязка идентичности. Перепривязку `currentAgent` даёт только routing-fallback (L643–656) — отдельный механизм, который для view-image после Варианта B вообще не срабатывает (агент в собственной таблице), а для прочих агентов guarded Рек. 3.

**Смягчение:** identity lock v3 срабатывает на `session.created` (плагин читает `session.agent`, L735–737; лок устанавливается на L188–193) — окно гонки узкое; identity-probe и IDENTITY VERIFIED line дополнительно фиксируют агента. Для залоченных сессий ни hint-поиск, ни fallback не могут перепривязать агента (hint — никогда, fallback — после Рек. 3). **Остаточный риск — Low** (только диагностический шум в логе), но его стоит упомянуть в PLUGIN.md как подтверждённый случай known issue.

### 4.2. Отсутствие семантики вызова view-image в промпте plankestrator

Routing table разрешает вызов, но ни `PIPELINE TABLE` (L43–50), ни `TURN ALGORITHM`, ни `CLASSIFICATION RULES` plankestrator.md не описывают, когда view-image уместен. Пайплайны PLAN/RESEARCH не включают view-image как элемент. Модель получает «висячее» разрешение — возможны непредсказуемые вызовы вне state machine (нарушение «No more than ONE Task call per turn» / «No pipeline changes» трактуется неоднозначно). **Рекомендация:** явное правило в промпте (см. Изменение 1).

### 4.3. Расхождение счётчиков

После правки сумма whitelist-записей (34) перестаёт совпадать с числом уникальных субагентов (33). Все места, где фигурируют «9 agents» / «33» / «35» (ARCHITECTURE.md L36/L55/L56/L58, AGENTS.md L240, MCP_SETUP.md L393/L691, opencode-config/*, deploy-package/*), должны быть обновлены согласованно — иначе consistency-checker (читает ARCHITECTURE.md как источник истины) начнёт фиксировать несоответствия. Скрипт `deploy-package\scripts\verify.ps1` (L110–114 — список `$requiredAgents`, проверка существования файлов агентов, включая view-image; L113 — строка с `"consistency-checker", "view-image"`) правкой не затронут: он не проверяет routing tables.

### 4.4. Внутреннее противоречие deploy-package (положительный эффект)

`deploy-package\project-files\ARCHITECTURE.md` L13–14 уже декларирует view-image как shared-агента обоих primary — но это противоречит её же L10–11 и копии плагина в deploy-package (L30–40, без view-image). Вариант B **устраняет** это противоречие, приводя фактическую конфигурацию к уже задокументированному дизайну. При деплое пакета без правки копии плагина рассинхрон сохранится — копия `deploy-package\plugins\workflow-enforcement.ts` обязательна к обновлению.

### 4.5. Изменение характера связки Рек. 2 + Рек. 3

Исходная логика (L45): «Рек. 2 убирает триггер, Рек. 3 устраняет баг — страхуют друг друга». После Варианта B: триггер view-image устранён легализацией (вызов проходит по собственной таблице, fallback не срабатывает), триггеры generate-image* устранены удалением из allowlist. Рек. 3 остаётся единственной защитой от fallback-мутации для generate-image* и любых будущих рассинхронов — её приоритет **не снижается**.

### 4.6. Что НЕ является риском

- Валидация JSON plankestrator не меняется (`REQUIRED_JSON_FIELDS.plankestrator`, L51 — 7 полей, без `plan_exists`/`plan_source`).
- Hard-gate `PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}` (L466) не затрагивается — view-image вызывается через `task`, который разрешён.
- `FORBIDDEN_VOCAB` (L88–99) не содержит упоминаний view-image — проверок дрейфа правка не касается.
- Секция orchestrator во всех файлах не меняется (view-image там уже везде есть).

---

## Приложение. Сверка ответов на вопросы задачи

1. **Строка в workflow-enforcement.ts для добавления view-image:** вставка после **L42** (`"devops-readonly"`), перед закрывающей `]` на L43, внутри `ROUTING_TABLES.plankestrator` (L33–43). Нужна запятая после `"devops-readonly"`.
2. **Строка в ARCHITECTURE.md для обновления whitelist plankestrator:** заголовок **L36** («9 agents» → «10 agents»), новая строка таблицы **после L48**, плюс счётчики L55, L56, L58.
3. **Отменяемая часть Рек. 2:** удаление L1440 (`"view-image": "allow",`) — отменить; удаление L1441–1442 (generate-image*) — оставить; правка запятой переносится с L1439 на L1440.
4. **Согласованность orchestrator:** view-image уже в routing table orchestrator — плагин **L27**, промпт orchestrator.md **L26**, opencode.json **L1262**, ARCHITECTURE.md **L30**. Плагин уже разрешает view-image для orchestrator (L27) — правок не требуется. В ARCHITECTURE.md view-image нужно добавить **только для plankestrator** (для orchestrator он уже есть); рекомендуется дополнительно оформить секцию «Shared Utility Agents», фиксирующую общий статус агента.
