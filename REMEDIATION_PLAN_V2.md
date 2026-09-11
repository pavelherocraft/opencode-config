# План доработок V2: устранение 6 проблем валидации конфигурации primary agents + Вариант B (view-image в plankestrator)

**Дата:** 2026-09-07
**Источники:**

- `P:\Programming\Рефакторинг\VALIDATION_REPORT.md` (проблемы №1–№6)
- `P:\Programming\Рефакторинг\REMEDIATION_PLAN.md` (V1 — базовый план, Рек. 1–7)
- `P:\Programming\Рефакторинг\VIEW_IMAGE_RESEARCH.md` (исследование Варианта B — новая Рек. 2b, корректура Рек. 2)

**Назначение:** пошаговый исполнимый план для передачи orchestrator. **Заменяет REMEDIATION_PLAN.md (V1)** — V1 остаётся исторической справкой.
**Объём:** 8 рекомендаций (1, 2, 2b, 3, 4, 5, 6, 7), устраняющих 6 проблем (№1–№6 из отчёта); для Проблемы №2 применяется **Вариант B**: `view-image` легализуется в plankestrator (Рек. 2b), из allowlist удаляются только `generate-image` / `generate-image-gpt` (Рек. 2).

**Целевые файлы:**

| Файл | Положение / строки правок |
|------|---------------------------|
| `C:\Users\Admin\.config\opencode\agents\orchestrator.md` | 125 строк (L15, L49, L59, L109, L118–125) |
| `C:\Users\Admin\.config\opencode\agents\plankestrator.md` | 117 строк (L12, L15, L26, вставка после L58, L110) |
| `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` | 1020 строк (L42–43, L643–656) |
| `C:\Users\Admin\.config\opencode\opencode.json` | 1588 строк (L1227–1239, L1416–1427, L1440–1442) |
| `P:\Programming\Рефакторинг\ARCHITECTURE.md` | 668 строк (L36, после L48, L55, L56, L58, L180–185) |
| `P:\Programming\Рефакторинг\AGENTS.md` | L207 (таблица разрешений), L240–252 (plankestrator whitelist) |
| `P:\Programming\Рефакторинг\MCP_SETUP.md` | L393–394, L691–705, L911–915 |
| `P:\Programming\Рефакторинг\PLUGIN.md` | L763 (опционально: примечание к known issue) |
| `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` | L33, после L45 |
| `P:\Programming\Рефакторинг\opencode-config\AGENTS.md` | L229, после L241 |
| `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md` | L154, L206, L736 (опционально), L848–860 |
| `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` | L207 (опционально), L237, после L249 |
| `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` | L10–11, L13–14 |
| `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md` | L154, L168, L206, L881 (обязательно — копии whitelist/routing table), L757 (опционально) |
| `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` | L30–40 (таблица plankestrator: L39–40) |

> **Уточнение к отчёту (проверено по фактическим файлам, унаследовано из V1):** отчёт называет `AGENTS.md` «глобальным», однако таблица «Tool allowance for primary agents» с `todowrite`, `question` в колонке Allowed фактически находится в **проектном** `P:\Programming\Рефакторинг\AGENTS.md` (строка 207). В глобальном `C:\Users\Admin\.config\opencode\AGENTS.md` упоминаний `todowrite` нет. Существует также копия таблицы в `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` (строка 207) — вне объёма отчёта, рекомендуется синхронизировать для консистентности.

> **Все номера строк ниже сверены с фактическими файлами** (для Рек. 1–7 — по V1 и VALIDATION_REPORT.md; для Рек. 2b — по VIEW_IMAGE_RESEARCH.md, разделы 1.2–1.4, 2, 4). При правке рекомендуется использовать точное совпадение строк (string replace), а не номера строк: после удалений/вставок номера смещаются (в plankestrator.md вставка семантического правила после ~L58 сдвигает PROHIBITIONS L110 вниз; в ARCHITECTURE.md/AGENTS.md вставки строк таблиц сдвигают счётчики). Если правки идут по номерам строк в одном файле — выполнять **снизу вверх**.

---

## Изменения по сравнению с V1 (REMEDIATION_PLAN.md)

| Элемент | V1 | V2 (настоящий план) |
|---------|----|--------------------|
| Рек. 2 | Удалить 3 строки L1440–1442 (`view-image`, `generate-image`, `generate-image-gpt`); правка запятой на L1439 (`devops-readonly`); итог — 11 ключей (9 allow), «ровно 9 агентов» | Удалить только 2 строки **L1441–1442** (`generate-image`, `generate-image-gpt`); `view-image` (L1440) **сохранить**, запятую снять с него; L1439 не трогать; итог — **12 ключей (10 allow)**, «ровно 10 агентов» |
| Рек. 2b | Отсутствовала; альтернативный путь «не применяется» (V1 L174) | **Новая рекомендация:** легализация `view-image` — плагин (L42–43), промпт plankestrator.md (L26 + семантическое правило после L58), ARCHITECTURE.md (L36, после L48, L55, L56, L58 + опц. «Shared Utility Agents»), AGENTS.md (L240–252), MCP_SETUP.md, opencode-config/\*, deploy-package/\* |
| Routing tables plankestrator | 9 агентов во всех источниках | **10 агентов** (`view-image` — общий агент обоих primary) |
| Порядок выполнения | Пакеты A ∥ B ∥ C ∥ D ∥ E; Фаза 4 — перезапуск | Runtime-часть Рек. 2b (пакеты B, D) **до** Рек. 2 (пакет A) — оборонительный порядок; новый **пакет F** (копии документации); Фаза 3 — перезапуск |
| Верификация | Негативный тест: вызов `view-image` из plankestrator отклоняется | **Позитивный** тест: вызов `view-image` из plankestrator проходит; **негативный** тест: `generate-image*` отклоняется; добавлены проверки routing table плагина, семантического правила, счётчиков во всех копиях |
| Рек. 1, 3, 4, 5, 6, 7 | — | Сохранены **без изменений** (в Рек. 3 — одна редакторская [Примечание V2] о совместном пакете B с Рек. 2b; в Рек. 1 — [Примечание V2] о совместных проходах с Рек. 2b по plankestrator.md/ARCHITECTURE.md/AGENTS.md) |

---

## Сводная таблица

| Рек. | Проблема | Приоритет | Файлы | Требует перезапуска opencode |
|------|----------|-----------|-------|------------------------------|
| 1 | №1 (противоречие слоёв разрешений) | High | orchestrator.md, plankestrator.md, opencode.json, ARCHITECTURE.md, AGENTS.md | Да (frontmatter + opencode.json) |
| 2 | №2, часть 1 (удалить `generate-image*` из task-allowlist plankestrator) | High | opencode.json (L1441–1442 + запятая L1440) | Да |
| 2b | №2, часть 2 (легализовать `view-image` в routing tables plankestrator — Вариант B) | High | workflow-enforcement.ts (L42–43), plankestrator.md (L26, после L58), ARCHITECTURE.md (L36, после L48, L55–58), AGENTS.md (L240–252), MCP_SETUP.md (L393–394, L691–705, L911–915), opencode-config/\* , deploy-package/\* | Да (плагин + промпт); копии документации — нет |
| 3 | №3 (routing-fallback игнорирует identity lock) | High | workflow-enforcement.ts (L643–656) | Да (плагин загружается при старте) |
| 4 | №4 (rework-loop не покрывает строки 4 и 6) | Medium | orchestrator.md (L59) | Да (промпт перечитывается в новой сессии) |
| 5 | №5 (литеральные запрещённые токены в L109) | Low | orchestrator.md (L109) | Да |
| 6 | №6 (`plan_exists: any` в строке 5) | Trivial/Low | orchestrator.md (L49) | Да |
| 7 | Усиление PROHIBITIONS orchestrator | Low | orchestrator.md (L118–125) | Да |

**Итог: один перезапуск opencode после завершения всех правок покрывает все рекомендации.** Правки ARCHITECTURE.md, AGENTS.md, MCP_SETUP.md, PLUGIN.md и копий документации (opencode-config/\*, deploy-package/\*) перезапуска не требуют (справочные документы), но выполняются в том же проходе.

---

## Порядок выполнения

### Зависимости между рекомендациями

- **Рек. 2b — ДО Рек. 2 (новое правило Варианта B).** Физической зависимости нет: Рек. 2b вообще не правит `opencode.json`, Рек. 2 не трогает плагин/промпт/документацию; так как все изменения вступают в силу только после единственного перезапуска (Фаза 3), формально допустимо и параллельное выполнение. Рекомендуемый порядок — **оборонительный**: если выполнение прервётся и opencode будет перезапущен на промежуточном состоянии, то состояние «2b выполнена, Рек. 2 — нет» строго лучше исходного (view-image легализован во всех слоях; триггер generate-image\* остаётся как раньше), тогда как состояние «Рек. 2 выполнена, 2b — нет» сохраняет рассинхрон view-image (в allowlist есть, в routing tables нет — исходная Проблема №2), а с действующей Рек. 3 превращает вызов view-image из сессии plankestrator в жёсткое нарушение вместо легального вызова. Правило: **пакет A стартует после завершения пакетов B и D.**
- **Рек. 2, 2b и 3 связаны логически (обновлённая формулировка V1 L45):** Рек. 2 убирает триггер для `generate-image*` (удаление из allowlist); триггер `view-image` устранён легализацией (Рек. 2b — вызов проходит по собственной таблице, fallback не срабатывает); Рек. 3 устраняет сам латентный баг fallback-переключения `currentAgent` при `identityLocked === true` и остаётся **единственной** защитой от fallback-мутации для `generate-image*` и любых будущих рассинхронов — её приоритет не снижается. Выполнять **все три** — они страхуют друг друга.
- **Рек. 2b и Рек. 3 связаны физически:** обе правят `workflow-enforcement.ts` — один проход пакета B, **снизу вверх**: сначала L643–656 (Рек. 3), затем L42–43 (Рек. 2b).
- **Рек. 2b и Рек. 1 связаны физически:** `plankestrator.md` (пакет D, снизу вверх: L110 → ~L58 → L26 → L15 → L12), `ARCHITECTURE.md` (пакет E, снизу вверх: L180–185 → L58 → L56 → L55 → после L48 → L36), `AGENTS.md` (пакет E, снизу вверх: после L252 → L240 → L207).
- **Рек. 1 и Рек. 2 связаны физически:** обе правят `opencode.json` — один последовательный проход пакета A, **снизу вверх** (сначала L1441–1442 + запятая L1440, затем L1416–1427, затем L1227–1239), чтобы удаления не сбивали номера строк следующих правок.
- **Рек. 1, 4, 5, 6, 7 связаны физически:** все правят `orchestrator.md` — выполнять одним последовательным проходом по файлу (пакет C, во избежание конфликтов правок и смещения строк).
- **Рек. 4, 5, 6, 7 независимы друг от друга** по содержанию, но выполняются в рамках одного прохода по orchestrator.md вместе с Рек. 1.

### Фазы

1. **Фаза 1 (High) — enforcement-слои и промпты:**
   - **Шаг 1.1 (пакеты B, D, C — параллельно):**
     - Пакет B: `workflow-enforcement.ts` — Рек. 3 (L643–656) + Рек. 2b (L42–43). Один последовательный проход, снизу вверх.
     - Пакет D: `plankestrator.md` — Рек. 1 (frontmatter L12, L15 + PROHIBITIONS L110) + Рек. 2b (OPENCODE_ROUTING_TABLE L26 + семантическое правило — вставка после L58). Один последовательный проход, снизу вверх.
     - Пакет C: `orchestrator.md` — Рек. 1 (frontmatter L15 + PROHIBITIONS L120) + Рек. 4 (L59) + Рек. 5 (L109) + Рек. 6 (L49) + Рек. 7 (L118–125). Один последовательный проход, снизу вверх.
   - **Шаг 1.2 (после завершения пакетов B и D — правило «Рек. 2b до Рек. 2»):**
     - Пакет A: `opencode.json` — Рек. 2 (L1441–1442 + запятая L1440) + Рек. 1 (permission-ключи обеих primary-секций: L1416–1427, L1227–1239). Один последовательный проход, снизу вверх.
2. **Фаза 2 — документация (может выполняться параллельно с Фазой 1, файлы не пересекаются):**
   - Пакет E: `ARCHITECTURE.md` (Рек. 1: L180–185; Рек. 2b: L36, после L48, L55, L56, L58 + опциональная секция «Shared Utility Agents») + `AGENTS.md` (Рек. 2b: L240–252; Рек. 1: L207).
   - Пакет F (**параллельно с E**): копии документации — Рек. 2b (MCP_SETUP.md, opencode-config/ARCHITECTURE.md, opencode-config/AGENTS.md, opencode-config/PLUGIN.md, deploy-package/project-files/AGENTS.md, deploy-package/project-files/ARCHITECTURE.md, deploy-package/plugins/workflow-enforcement.ts; опционально PLUGIN.md L763 и копии L736/L757).
3. **Фаза 3 — перезапуск opencode и верификация** (см. раздел «Верификация»). После всех правок — один перезапуск, затем контрольные проверки.

### Что можно выполнять параллельно

| Параллельно | Последовательно |
|-------------|------------------|
| Шаг 1.1: Пакет B ∥ Пакет D ∥ Пакет C. Фаза 2: Пакет E ∥ Пакет F (и совместно со всеми пакетами Фазы 1 — файлы не пересекаются) | Все правки внутри каждого пакета — строго последовательно, снизу вверх. **Пакет A — только после завершения пакетов B и D** (Рек. 2b до Рек. 2) |

---

## Рекомендация 1 — Согласовать слои разрешений `todowrite`/`question` (Проблема №1, приоритет High)

*(Сохранена из V1 без изменений.)*

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
- *[Примечание V2: правки plankestrator.md (шаги 3–5), ARCHITECTURE.md (шаг 8) и AGENTS.md (шаг 9) выполняются в тех же проходах, что и Рек. 2b — пакеты D и E, снизу вверх; см. «Порядок выполнения». Содержательно Рек. 1 не изменяется.]*

---

## Рекомендация 2 — Сократить JSON task-allowlist plankestrator: удалить только `generate-image*` (Проблема №2, часть 1, приоритет High)

*(Скорректирована по Варианту B — VIEW_IMAGE_RESEARCH.md, раздел 3.1. В V1 удалялись 3 агента; теперь `view-image` сохраняется и легализуется Рек. 2b.)*

### Цель

Task-allowlist plankestrator в opencode.json совпадает с plugin routing table и `OPENCODE_ROUTING_TABLE` plankestrator.md — ровно **10 агентов** (после легализации `view-image` по Рек. 2b). Из allowlist удалены **только** агенты `generate-image`, `generate-image-gpt` (инструменты генерации изображений в планировочных сессиях не нужны — они остаются только в whitelist orchestrator). `view-image` (L1440) **сохраняется**: для него применяется альтернативный путь из V1 (L174) — он добавляется в `ROUTING_TABLES.plankestrator` плагина **и** в `OPENCODE_ROUTING_TABLE` plankestrator.md L26 (см. Рек. 2b). Устраняется риск молчаливой мутации `currentAgent` в `orchestrator` через routing-fallback плагина с последующей валидацией JSON plankestrator по схеме orchestrator (предупреждения «INVALID JSON OUTPUT» из-за отсутствия полей `plan_exists`/`plan_source`): для `generate-image*` — удалением из allowlist (плюс Рек. 3), для `view-image` — легализацией (Рек. 2b).

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\opencode.json` (строки 1441–1442 + правка запятой на строке 1440; секция `plankestrator` → `permission` → `task`, блок L1428–1443)

### Пошаговые действия

1. В секции `plankestrator.permission.task` (L1428–1443) удалить строки **1441–1442**:
   ```json
             "generate-image": "allow",
             "generate-image-gpt": "allow"
   ```
   Строку **1440** `"view-image": "allow",` — **НЕ удалять** (отмена соответствующей части Рек. 2 из V1; Вариант B).
2. **Критично для валидности JSON:** после удаления L1441–1442 строка 1440 становится последней перед закрывающей `}` — удалить её завершающую запятую:
   ```json
             "view-image": "allow"
   ```
   Строку 1439 `"devops-readonly": "allow",` — **не трогать** (правка запятой на L1439 из V1 отменена — она сместилась на L1440).
3. Итоговый блок `task` должен содержать **12 ключей** (10 × `"allow"` + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`):
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
4. **Внимание:** не трогать одноимённые ключи `view-image`/`generate-image`/`generate-image-gpt` в секции `orchestrator` (L1262, L1264, L1265) — там они легальны (24-агентный whitelist).

### Ожидаемый результат

- Ровно **10** записей `"allow"` в task-allowlist plankestrator — поагентно совпадают с `ROUTING_TABLES.plankestrator` плагина и `OPENCODE_ROUTING_TABLE` (plankestrator.md L26) **после выполнения Рек. 2b**: plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly, view-image.
- `generate-image`, `generate-image-gpt` отсутствуют в секции plankestrator; `view-image` присутствует (последний ключ, без запятой).
- opencode.json остаётся валидным JSON (проверка парсером обязательна — риск висячей запятой).
- Вызов `view-image` из plankestrator проходит на всех слоях (конфиг + routing table плагина); попытка plankestrator вызвать `generate-image*` отклоняется на уровне конфигурации (`"*": "deny"`), а при достижении плагина в залоченной сессии — throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)` (Рек. 3).

### Зависимости

- **Выполняется ПОСЛЕ Рек. 2b** (оборонительный порядок «сначала легализовать view-image в routing tables, потом сокращать allowlist»; формально физической зависимости нет — файлы не пересекаются, см. «Порядок выполнения»).
- Выполняется одним проходом по opencode.json вместе с Рекомендацией 1 (шаги 6–7); **порядок внутри файла — снизу вверх**: сначала L1441–1442 + запятая L1440 (эта рекомендация), затем L1416–1427 (Рек. 1, plankestrator), затем L1227–1239 (Рек. 1, orchestrator).
- Логически связана с Рекомендациями 2b и 3: Рек. 2 устраняет триггер для generate-image\*, Рек. 2b устраняет триггер view-image (легализацией), Рек. 3 — сам латентный баг fallback'а. Выполнить все три.

---

## Рекомендация 2b — Легализовать `view-image` в routing tables plankestrator (Проблема №2, часть 2 — Вариант B, приоритет High)

*(Новая рекомендация — VIEW_IMAGE_RESEARCH.md, разделы 2 и 3.2.)*

### Цель

`ROUTING_TABLES.plankestrator` плагина, `OPENCODE_ROUTING_TABLE` plankestrator.md и whitelist plankestrator в ARCHITECTURE.md содержат `view-image` (**10 агентов**) — все три источника routing table идентичны, как требует финальная проверка консистентности. Копии документации синхронизированы (счётчики «9 agents» → «10 agents», «33» → «34» whitelist-записей, «35» уникальных агентов — без изменений). Промпт plankestrator содержит **семантическое правило** вызова view-image (устранение риска 4.2 исследования — «висячее» разрешение без описания, когда вызывать). Внутреннее противоречие deploy-package (project-files/ARCHITECTURE.md L13–14 декларирует view-image как shared-агента обоих primary, но L10–11 и копия плагина L30–40 — без него) — **устраняется**: конфигурация приводится к уже задокументированному дизайну.

### Обоснование (прецеденты и текущее состояние — исследование, разделы 1.2, 1.4)

- **Текущий рассинхрон (Проблема №2):** в plankestrator `view-image` разрешён ТОЛЬКО в opencode.json (L1440 `"view-image": "allow",`); в промпте (L26 — 9 агентов), плагине (L33–43 — 9 агентов, `"devops-readonly"` на L42 без запятой, `]` на L43) и ARCHITECTURE.md (L36–48 — «9 agents», последняя строка L48 `| 9 | devops-readonly | DevOps read-only |`) — отсутствует.
- Для orchestrator view-image легален во всех четырёх слоях (эталон согласованности): промпт orchestrator.md **L26**, плагин **L27** (`ROUTING_TABLES.orchestrator`, L7–32), opencode.json **L1262**, ARCHITECTURE.md **L30** (`| 20 | view-image | Image analysis |` в таблице «orchestrator Whitelist (24 agents)», L7–34). **Для orchestrator менять ничего не нужно.**
- `plankestrator-identity-probe` уже имеет `view-image` в task-allowlist (MCP_SETUP.md L418) — прецедент «планировочный субагент + view-image» существует.
- `research-writer-simple.md` и `research-writer-complex.md` имеют `"view-image": "allow"` (L16 в обоих файлах) — writer-агенты plankestrator-пайплайнов уже могут вызывать view-image напрямую. Вариант B добавляет эту возможность самому роутеру.

### Файлы для изменения

1. `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (L42–43, внутри `ROUTING_TABLES.plankestrator` L33–43)
2. `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (L26 + вставка семантического правила после L58 в `## TURN ALGORITHM`, Turn 1)
3. `P:\Programming\Рефакторинг\ARCHITECTURE.md` (L36, после L48, L55, L56, L58 + опциональная секция «Shared Utility Agents»)
4. `P:\Programming\Рефакторинг\AGENTS.md` (L240, после L252)
5. `P:\Programming\Рефакторинг\MCP_SETUP.md` (L393–394, L691–705, L911–915)
6. `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` (L33, после L45)
7. `P:\Programming\Рефакторинг\opencode-config\AGENTS.md` (L229, после L241)
8. `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md` (L154, L206, L848–860)
9. `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` (L237, после L249)
10. `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` (L10–11, L13–14)
11. `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` (L39–40)
12. `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md` (L154 — заголовок «(9 agents)», после L168 — строка таблицы; L206 и L881 — `'devops-readonly'` в двух копиях routing table)
13. *(Опционально, Low)* `P:\Programming\Рефакторинг\PLUGIN.md` (L763) + копии `opencode-config\PLUGIN.md` (L736), `deploy-package\project-files\PLUGIN.md` (L757) — примечание к known issue (шаг 7)

`opencode.json` в этой рекомендации **не правится** — ключ `"view-image": "allow"` (L1440) сохраняется силами Рек. 2.

### Пошаговые действия

1. **workflow-enforcement.ts, строки 42–43** (внутри `ROUTING_TABLES.plankestrator`, L33–43). Заменить:
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
   Запятая после `"devops-readonly"` на L42 **обязательна**; новая строка вставляется перед закрывающей `]` на L43 (массив станет L33–44).
   Больше в плагине ничего менять не нужно: `REQUIRED_JSON_FIELDS` (L49–52), `VALID_VALUES`, `PRIMARY_AGENT_ALLOWED_TOOLS` (L466), `FORBIDDEN_VOCAB` (L88–99), `detectAgentFromSubagent` (L870–877) не затрагиваются. Fallback-логика (L636–656) начнёт работать корректно автоматически: view-image будет находиться в `allowedAgents` текущего агента, и ветка `otherAgent` для него больше не сработает.
   **Порядок:** правка выполняется в том же проходе пакета B, что и Рек. 3, **снизу вверх**: сначала L643–656 (Рек. 3), затем L42–43 (этот шаг).
2. **deploy-package\plugins\workflow-enforcement.ts, строки 39–40:** применить то же изменение к копии плагина (`"devops-readonly"` на L39 — добавить запятую, вставить `"view-image"` перед `]` на L40; таблица plankestrator в копии — L30–40). Копия **обязательна** к обновлению: при деплое пакета без этой правки рассинхрон сохранится (риск 4.4 исследования).
3. **plankestrator.md, строка 26.** Заменить:
   ```
   OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly"]
   ```
   на (view-image добавлен в конец списка; примечание исследования: в orchestrator.md L26 view-image стоит на позиции 20 из 24 — после основных рабочих агентов, но НЕ последним; для plankestrator выбрана позиция в конце как простейшая и не влияющая на существующие ссылки):
   ```
   OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly", "view-image"]
   ```
4. **plankestrator.md, семантическое правило** — вставка в `## TURN ALGORITHM` (Turn 1, новый пункт после пункта 2 на L58 — по образцу «read/glob/grep to classify ONLY»; нумерацию пункта привести по факту файла; альтернативное размещение — явный пункт в CLASSIFICATION RULES). Формулировка — см. подраздел «Семантическое правило» ниже.
   **Порядок:** правки plankestrator.md выполняются в том же проходе пакета D, что и Рек. 1 (шаги 3–5), **снизу вверх**: L110 (Рек. 1, PROHIBITIONS) → вставка после ~L58 (этот шаг) → L26 (шаг 3) → L15 (Рек. 1) → L12 (Рек. 1). После вставки номера строк ниже ~L58 (включая PROHIBITIONS L110–113) смещаются — поэтому правка L110 выполняется до вставки, либо точной заменой строк.
5. **ARCHITECTURE.md** (пакет E, снизу вверх: сначала L180–185 Рек. 1, затем пункты ниже):
   1. **L58:** примечание уточнить: «33 unique subagents + 2 primary agents = 35 unique agents total» → «34 whitelist entries (view-image shared by both primaries), 33 unique subagents + 2 primary agents = 35 unique agents total».
   2. **Опционально (рекомендуется), сразу после L58:** добавить секцию «Shared Utility Agents» по образцу `deploy-package\project-files\ARCHITECTURE.md` L13–14, зафиксировав, что view-image — общий агент обоих primary. Это снимет вопрос «почему один субагент в двух таблицах».
   3. **L56:** Grand Total: `| **Grand Total** | **33** | **35** |` → `| **Grand Total** | **34** | **35** |` (сумма whitelist-записей 24+10=34; уникальных агентов по-прежнему 35, т.к. view-image уже посчитан в whitelist orchestrator).
   4. **L55:** `| plankestrator | 9 | 10 (plankestrator + 9 subagents) |` → `| plankestrator | 10 | 11 (plankestrator + 10 subagents) |`.
   5. **После L48** вставить строку таблицы:
      ```
      | 10 | view-image | Image analysis |
      ```
   6. **L36:** `### plankestrator Whitelist (9 agents)` → `### plankestrator Whitelist (10 agents)`.
   7. В таблице orchestrator view-image **уже есть** (L30) — дублировать/менять ничего не нужно; таблицу orchestrator (L7–34) не трогать.
6. **Копии документации** (пакет F — параллельно с фазой 1; исследование, Изменение 5):

   | Файл | Правка |
   |------|--------|
   | `P:\Programming\Рефакторинг\AGENTS.md` *(пакет E)* | L240 → «(10 agents)»; после L252 добавить `\| view-image \| Image analysis \|` |
| `P:\Programming\Рефакторинг\MCP_SETUP.md` | L393 → «Task Whitelist (10 agents):», L394 — добавить view-image в список; L691 → «(10 agents)», после L705 — строка таблицы; L911–915 (plankestrator-таблица плагина) — добавить `"view-image"` после `"devops-readonly"` (L914) |
| `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md` | L33 → «(10 agents)», после L45 — `\| 10 \| view-image \| Image analysis \|`; **счётчики Agent Count Summary (L47–55):** L52 → `\| plankestrator \| 10 \| 11 (plankestrator + 10 subagents) \|`, L53 Grand Total → `\*\*31\*\* \| \*\*32\*\*` (в этой копии orchestrator — 21 агент: 21+10=31 записи; уникальные агенты 32 — без изменений, view-image уже посчитан в whitelist orchestrator), примечание L55 — без изменений |
   | `P:\Programming\Рефакторинг\opencode-config\AGENTS.md` | L229 → «(10 agents)», после L241 — строка таблицы |
   | `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md` | L154 → «(10 agents)» + строка таблицы; L206/L860 — `"view-image"` в копиях routing table |
   | `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md` | Аналогично AGENTS.md (заголовок «plankestrator Whitelist (9 agents)» — L237, последняя строка таблицы L249) |
   | `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md` | L10–11 → «(10 agents)» + view-image в список; L13–14 («Shared Utility Agents») — **уже корректно описывает Вариант B**, привести в соответствие с фактом (view-image теперь в routing table plankestrator, а не только в permission block) |
   | `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts` | См. шаг 2 |
| `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md` | L154 → «(10 agents)», после L168 — строка таблицы `\| view-image \| Image analysis \|`; L206 и L881 — добавить `'view-image'` после `'devops-readonly'` в обеих копиях routing table (аналогично opencode-config\PLUGIN.md) |

7. *(Опционально, Low)* **PLUGIN.md, L763** (копии: `opencode-config\PLUGIN.md` L736, `deploy-package\project-files\PLUGIN.md` L757): дополнить known issue «reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables)» примечанием о подтверждённом случае: после Варианта B `view-image` присутствует в обеих таблицах; эффект ограничен info-логом «Reverse routing hint (not enforced)» — без мутации состояния (см. «Риски» ниже).

### Семантическое правило: когда plankestrator вызывает view-image

**Обоснование необходимости (риск 4.2 исследования):** routing table разрешает вызов, но ни `PIPELINE TABLE` (plankestrator.md L43–50), ни `TURN ALGORITHM`, ни `CLASSIFICATION RULES` не описывают, когда view-image уместен. Пайплайны PLAN/RESEARCH не включают view-image как элемент. Без явного правила модель получает «висячее» разрешение — возможны непредсказуемые вызовы вне state machine (нарушение «No more than ONE Task call per turn» / «No pipeline changes» трактуется неоднозначно).

**Условия вызова (конъюнкция обоих):**

1. Запрос пользователя (PLAN / RESEARCH / RESEARCH+PLAN) ссылается на изображение: скриншот, диаграмма, UI-макет, фото текста ошибки.
2. Содержимое изображения **необходимо для фазы CLASSIFY**: (а) классификации запроса — тип (PLAN / RESEARCH / RESEARCH+PLAN / OUT OF SCOPE) и сложность (SIMPLE / COMPLEX), либо (б) составления Task-промпта первому агенту пайплайна (plan-writer-\* / research-writer-\*).

*Пример:* к запросу «составь план исправления» приложен скриншот ошибки — view-image извлекает текст ошибки, plankestrator определяет BUGFIX → OUT OF SCOPE (перенаправление к orchestrator).

**Запреты (когда НЕ вызывать):**

- изображений нет, либо их содержимое уже описано текстом / не влияет на классификацию;
- для генерации изображений (`generate-image*` — только агенты orchestrator);
- как подмену writer/reviewer-агентов: view-image — **не элемент пайплайнов** PLAN/RESEARCH; глубокий анализ изображений для содержимого плана/исследования делегируется writer-агентам (`research-writer-*` уже имеют `task.view-image: allow`, L16 в обоих файлах);
- в ходах исполнения пайплайна (Turns 2..N) — только на этапе классификации.

**Порядок ходов (инварианты сохраняются):**

- вызов view-image — **отдельный (вспомогательный) ход**, не шаг пайплайна: инвариант «No more than ONE Task call per turn» (plankestrator.md L113) соблюдается — вызов view-image занимает собственный ход;
- state machine **не продвигается**: в следующем ходе plankestrator выводит классификационный JSON и вызывает первого агента пайплайна как обычно;
- JSON-вывод хода с view-image обязателен по штатной схеме plankestrator (7 полей), `state` — текущий (CLASSIFY).

**Предлагаемая формулировка для plankestrator.md** (вставить в `## TURN ALGORITHM`, Turn 1, новым пунктом после пункта 2 — L58; нумерацию привести по факту файла):

```
**view-image (auxiliary inspection, CLASSIFY stage only):** if the request references an image (screenshot, diagram, UI mockup, error photo) whose content is REQUIRED to classify it (type / complexity / scope) or to compose the Task prompt for the first pipeline agent, call `view-image` (Task, subagent_type: "view-image") as its OWN separate turn BEFORE the classification turn. Rules: (1) it is an inspection helper, NOT a pipeline step — the state machine does not advance, and the next turn outputs the classification JSON and calls the first pipeline agent as usual; (2) "No more than ONE Task call per turn" still holds — the view-image call occupies its own turn; (3) skip the call if the image content is already described in text or is irrelevant to classification; (4) never use view-image for image GENERATION (generate-image* are orchestrator-only) or as a substitute for plan-writer-* / research-writer-* — deep image analysis for plan/research CONTENT is delegated to the writer agents (research-writer-* already have task.view-image: allow).
```

### Ожидаемый результат

- `ROUTING_TABLES.plankestrator` плагина (L33–44) — **10 агентов**, `"view-image"` после `"devops-readonly"`; то же в копии deploy-package (L30–41).
- `OPENCODE_ROUTING_TABLE` plankestrator.md (L26) — **10 агентов**, `"view-image"` последним; TURN ALGORITHM содержит семантическое правило (CLASSIFY stage only).
- ARCHITECTURE.md: «plankestrator Whitelist (**10** agents)» (L36), строка `| 10 | view-image | Image analysis |` (после L48), счётчики L55 (`10 | 11`), L56 (`**34** | **35**`), L58 (примечание о 34 whitelist entries / shared) обновлены; таблица orchestrator не изменена (24 агента).
- Все три источника routing table идентичны (плагин, промпт, ARCHITECTURE.md) — финальная проверка консистентности проходит; копии документации (AGENTS.md, MCP_SETUP.md, opencode-config/\*, deploy-package/\*) синхронизированы.
- Внутреннее противоречие deploy-package (project-files/ARCHITECTURE.md L10–14 против копии плагина) устранено.
- Вызов view-image из plankestrator проходит hard-gate: `PRIMARY_AGENT_ALLOWED_TOOLS` (L466) не изменяется — view-image вызывается через `task`, который разрешён; fallback-ветка `otherAgent` для view-image больше не срабатывает (агент в собственной таблице).

### Риски и смягчения (исследование, раздел 4)

1. **Неоднозначность обратного поиска (4.1, остаточный риск — Low).** `detectAgentFromSubagent` (workflow-enforcement.ts L870–877) возвращает **первого** primary, чей whitelist содержит субагента; orchestrator итерируется первым. После Варианта B view-image входит в **обе** таблицы → для **незалоченной** сессии plankestrator (гонка до срабатывания `session.created`/`message.updated`) обратный поиск по вызову view-image вернёт `"orchestrator"`. Задокументированная known issue: PLUGIN.md **L763** («reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables)»; копии: opencode-config\PLUGIN.md L736, deploy-package\project-files\PLUGIN.md L757). **Уточнение механизма (проверено по коду):** функция вызывается только при `!currentAgent` (L537–556) и, согласно комментарию «REMOVED: state mutation from reverse routing lookup … NO state mutation» (L518–536), **не мутирует состояние** — результат попадает только в info-лог «Reverse routing hint (not enforced)». Практический эффект — вводящая в заблуждение диагностическая строка в логе, а не перепривязка идентичности. **Смягчение:** identity lock v3 срабатывает на `session.created` (плагин читает `session.agent`, L735–737; лок устанавливается на L188–193) — окно гонки узкое; identity-probe и IDENTITY VERIFIED line дополнительно фиксируют агента; для залоченных сессий ни hint-поиск, ни fallback не могут перепривязать агента (hint — никогда, fallback — после Рек. 3). Опциональное смягчение — примечание в PLUGIN.md (шаг 7).
2. **Отсутствие семантики вызова (4.2)** — устраняется семантическим правилом (шаг 4).
3. **Расхождение счётчиков (4.3):** после правки сумма whitelist-записей (34) перестаёт совпадать с числом уникальных субагентов (33). Все места с «9 agents» / «33» / «35» (ARCHITECTURE.md L36/L55/L56/L58, AGENTS.md L240, MCP_SETUP.md L393/L691, opencode-config/\*, deploy-package/\*) должны быть обновлены согласованно — иначе consistency-checker (читает ARCHITECTURE.md как источник истины) начнёт фиксировать несоответствия. Скрипт `deploy-package\scripts\verify.ps1` (L110–114 — список `$requiredAgents`, проверка существования файлов агентов, включая view-image; L113 — строка с `"consistency-checker", "view-image"`) правкой **не затронут**: он не проверяет routing tables.
4. **Внутреннее противоречие deploy-package (4.4)** — Вариант B устраняет его (положительный эффект); копия `deploy-package\plugins\workflow-enforcement.ts` обязательна к обновлению (шаг 2).
5. **Что НЕ является риском (4.6):** валидация JSON plankestrator не меняется (`REQUIRED_JSON_FIELDS.plankestrator`, L51 — 7 полей, без `plan_exists`/`plan_source`); hard-gate `PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}` (L466) не затрагивается; `FORBIDDEN_VOCAB` (L88–99) не содержит упоминаний view-image — проверок дрейфа правка не касается; секция orchestrator во всех файлах не меняется (view-image там уже везде есть).

### Зависимости

- **Не правит opencode.json** → физически не пересекается с Рек. 1/Рек. 2 в этом файле; логически заменяет часть Рек. 2 (альтернативный путь V1).
- Правка плагина — в том же пакете B, что и Рек. 3 (один файл, снизу вверх: сначала L643+ Рек. 3, затем L42–43 Рек. 2b, либо точными заменами строк).
- Правки промпта — в том же пакете D, что и Рек. 1 (один файл, снизу вверх: L110 → ~L58 → L26 → L15 → L12).
- Правки ARCHITECTURE.md / AGENTS.md — в пакете E вместе с документальной частью Рек. 1; копии — пакет F (параллельно).
- **Выполняется ДО Рек. 2** (пакет A стартует после завершения пакетов B и D — см. «Порядок выполнения»).
- Требует перезапуска opencode (плагин + промпт); копии документации перезапуска не требуют.

---

## Рекомендация 3 — Защитить routing-fallback identity lock'ом (Проблема №3, приоритет High)

*(Сохранена из V1 без изменений; добавлено одно редакторское [Примечание V2] в «Зависимостях».)*

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
  *[Примечание V2: после добавления Рек. 2b утверждение верно только для пакетов A, C, E, F — Рек. 2b правит тот же файл (L42–43). Обе правки выполняются одним проходом пакета B, снизу вверх: сначала L643–656 (Рек. 3), затем L42–43 (Рек. 2b). Содержательно Рек. 3 не изменяется; после Варианта B она остаётся единственной защитой от fallback-мутации для `generate-image*` и любых будущих рассинхронов — приоритет не снижается (исследование, риск 4.5).]*
- Логически связана с Рекомендацией 2 (устраняет триггер) — рекомендуется выполнять обе в одной фазе High.
- Требует перезапуска opencode (плагины загружаются при старте).

---

## Рекомендация 4 — Исправить замечание о rework-loop (Проблема №4, приоритет Medium)

*(Сохранена из V1 без изменений.)*

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

*(Сохранена из V1 без изменений.)*

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

*(Сохранена из V1 без изменений.)*

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

*(Сохранена из V1 без изменений.)*

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

Выполняется после завершения всех фаз и **одного перезапуска opencode** (Фаза 3).

### 1. Статические проверки (до перезапуска)

1. **Валидность JSON** (критично после удалений строк и правки запятых):
   ```
   node -e "JSON.parse(require('fs').readFileSync('C:/Users/Admin/.config/opencode/opencode.json','utf8')); console.log('JSON OK')"
   ```
   Ожидание: `JSON OK`, без `SyntaxError`.
2. **orchestrator.md** (Рек. 1, 4, 5, 6, 7):
   - frontmatter: `todowrite: deny` (L15), `question: deny` (L12);
   - строка 49: `| 5 | DEV | COMPLEX | true |`;
   - строка 59: `**Rework loop (rows 1-DEEP, 4, 5, 6, 8):**` с `escalate_to` / default `rework` / `worker` for row 4;
   - строка 109: отсутствуют литералы `## PLAN` и `# Implementation Plan` (grep → 0 совпадений в файле);
   - PROHIBITIONS: пункт с `question/todowrite` (L120), пункты «No skipping dev-reviewer / consistency-checker» и «No more than ONE Task call per turn» — всего 8 пунктов;
   - `OPENCODE_ROUTING_TABLE` (L26) **не изменилась** — 24 агента (включая view-image, generate-image, generate-image-gpt, git-commit).
3. **plankestrator.md** (Рек. 1 + 2b):
   - frontmatter: `question: deny` (L12), `todowrite: deny` (L15);
   - PROHIBITIONS (исходно L110; после вставки семантического правила в ~L58 номер смещается вниз на число вставленных строк — проверять точным совпадением): содержит `question/todowrite`;
   - `OPENCODE_ROUTING_TABLE` (L26) — **10 агентов**, `"view-image"` последним;
   - `## TURN ALGORITHM` (Turn 1) содержит семантическое правило view-image («auxiliary inspection, CLASSIFY stage only»; отдельный ход; не шаг пайплайна; запреты генерации и подмены writer-агентов).
4. **opencode.json, секция `orchestrator`:** `"question": "deny"`, `"todowrite": "deny"`; нет ключей `unity-mcp.*` и `serena_*`; task-блок сохраняет 24 агента (включая `view-image`, `generate-image`, `generate-image-gpt`, `git-commit`).
5. **opencode.json, секция `plankestrator`:** `"question": "deny"`, `"todowrite": "deny"`; нет ключей `unity-mcp.*` и `serena_*`; task-блок: ровно **10** записей `"allow"` (9 прежних: plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly — **плюс view-image** последним, без запятой) + `"*": "deny"` + `"orchestrator-identity-probe": "deny"` — итого **12 ключей**; записи **`generate-image`/`generate-image-gpt` отсутствуют**; запись **`view-image` присутствует**.
6. **Секции subagents в opencode.json не затронуты:** ключи `unity-mcp.*`/`serena_*` сохранены у всех агентов вне двух primary-секций (выборочная проверка, например `plan-writer-simple`, `mcp-search`); `research-writer-simple`/`research-writer-complex` сохраняют `"view-image": "allow"` (L16 в файлах агентов — не трогать).
7. **workflow-enforcement.ts:**
   - (Рек. 3) в ветке fallback'а (`tool.execute.before`) первая проверка — `if (identityLocked && otherAllowedAgents.includes(targetAgent))` с throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)`;
   - (Рек. 3) переключение `currentAgent = otherAgent` осталось только в ветке для незаблокированных сессий;
   - (Рек. 2b) `ROUTING_TABLES.plankestrator` (L33–44) содержит `"view-image"` после `"devops-readonly"` — **10 агентов**;
   - `PRIMARY_AGENT_ALLOWED_TOOLS` (L466) не изменён: `{task, read, glob, grep}`;
   - `FORBIDDEN_VOCAB` (L88–99) не изменён; `REQUIRED_JSON_FIELDS` (L49–52) не изменены; `detectAgentFromSubagent` (L870–877) не изменён; обработчик `message.updated` (L337–353) не изменён;
   - синтаксис TypeScript валиден (файл загружается без ошибок — проверяется в разделе 2).
8. **ARCHITECTURE.md:**
   - (Рек. 1) «enforced by **3** layers», пункт про `tools:` field frontmatter удалён, нумерация 1–3; таблица lockdown L166–178 не изменена;
   - (Рек. 2b) заголовок `### plankestrator Whitelist (10 agents)` (L36); строка `| 10 | view-image | Image analysis |` (после L48); Agent Count Summary (L50–56): `| plankestrator | 10 | 11 (plankestrator + 10 subagents) |` (L55), Grand Total `**34**` / `**35**` (L56); примечание (L58) о «34 whitelist entries (view-image shared by both primaries), 33 unique subagents + 2 primary agents = 35»; таблица orchestrator (L7–34) не изменена — 24 агента, `| 20 | view-image | Image analysis |` на L30; (опционально) секция «Shared Utility Agents».
9. **AGENTS.md (проектный):**
   - (Рек. 1) L207: `todowrite`, `question` перемещены в колонку Forbidden;
   - (Рек. 2b) «plankestrator Whitelist (**10** agents)» (L240) + строка `| view-image | Image analysis |` (после L252).
10. **Копии документации (Рек. 2b):**
    - `MCP_SETUP.md`: «Task Whitelist (10 agents):» (L393), view-image в списке (L394); вторая копия таблицы — «(10 agents)» (L691) + строка (после L705); в документации routing tables плагина (L911–912) — `"view-image"`;
    - `opencode-config\ARCHITECTURE.md`: «(10 agents)» (L33) + строка `| 10 | view-image | Image analysis |` (после L45); счётчики Agent Count Summary: `| plankestrator | 10 | 11 ... |` (L52), Grand Total `**31**` / `**32**` (L53);
    - `opencode-config\AGENTS.md`: «(10 agents)» (L229) + строка таблицы (после L241);
    - `opencode-config\PLUGIN.md`: «(10 agents)» + строка таблицы (L154); `"view-image"` в копиях routing table (L206, L848–860);
    - `deploy-package\project-files\AGENTS.md`: «(10 agents)» (L237) + строка таблицы (после L249);
    - `deploy-package\project-files\PLUGIN.md`: «(10 agents)» + строка таблицы (L154, после L168); `'view-image'` в обеих копиях routing table (L206, L881);
    - `deploy-package\project-files\ARCHITECTURE.md`: «(10 agents)» (L10–11) + view-image в списке; L13–14 («Shared Utility Agents») соответствует факту — view-image теперь в routing table plankestrator, а не только в permission block;
    - `deploy-package\plugins\workflow-enforcement.ts`: `"view-image"` в `ROUTING_TABLES.plankestrator` (L39–40 → массив L30–41);
    - **Контрольный grep:** `grep -rn "9 agents"` по .md-файлам проекта (корень, opencode-config, deploy-package) → 0 совпадений в контексте plankestrator whitelist; `grep -rn "33"` в контексте Grand Total → заменено на `34` (уникальные агенты `35` сохранены; в копиях opencode-config — `31`/`32`); `grep -rn "devops-readonly"` по .md-копиям с routing table (MCP_SETUP.md, opencode-config\PLUGIN.md, deploy-package\project-files\PLUGIN.md) → после каждого `'devops-readonly'` / `"devops-readonly"` в plankestrator-таблице следует `'view-image'` / `"view-image"`.

### 2. Перезапуск и проверки загрузки

1. Перезапустить opencode (все изменения `~/.config/opencode` — opencode.json, agents/\*.md, plugins/\*.ts — подхватываются только при перезапуске/новой сессии).
2. В логах присутствует `Workflow enforcement plugin initialized` — плагин загрузился без ошибок компиляции.

### 3. Функциональные проверки (в новых сессиях)

1. **Сессия orchestrator:**
   - в тулсете модели отсутствуют `todowrite`, `question`, `unity-mcp.*`, `serena_*` (инструменты не инжектируются — deny на уровне merged permission ruleset);
   - штатный пайплайн работает: identity line + валидный JSON (8 полей) + один Task-вызов за ход; в логах нет `PRIMARY AGENT ACTION TOOL VIOLATION` и нет `INVALID JSON OUTPUT`.
2. **Сессия plankestrator:**
   - штатный пайплайн работает (JSON из 7 полей валиден);
   - **позитивный тест (Рек. 2b):** вызов Task с `subagent_type: "view-image"` из сессии plankestrator **проходит** на всех слоях — конфиг (`"view-image": "allow"` в task-блоке) и плагин (агент присутствует в `ROUTING_TABLES.plankestrator` → fallback-ветка `otherAgent` не срабатывает); `currentAgent` остаётся `plankestrator`; в логах **нет** warn `Agent corrected via routing fallback`; `lockedAgentName` не меняется;
   - **негативный тест (Рек. 2 + Рек. 3):** вызов Task с `subagent_type: "generate-image"` (или `"generate-image-gpt"`) отклоняется: на уровне конфига (`"*": "deny"`), а если вызов доходит до плагина — throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)`;
   - **тест семантического правила (Рек. 2b):** запрос с изображением, содержимое которого нужно для классификации → plankestrator вызывает view-image отдельным ходом (ровно один Task-вызов в этом ходе), в следующем ходе выдаёт классификационный JSON (7 полей) и вызывает первого агента пайплайна; запрос без изображения → вызовов view-image нет;
   - последующие JSON plankestrator валидируются по схеме plankestrator (нет предупреждений об отсутствии `plan_exists`/`plan_source`).
3. **Проверка Рек. 5:** в сессии orchestrator процитировать/спровоцировать текст правила `plan_exists` — в логах нет error `FORBIDDEN VOCABULARY DETECTED`.
4. **Проверка Рек. 4 (наблюдательная):** при прогоне DEV SIMPLE с планом (строка 4) или DEV SUPERCOMPLEX (строка 6) с критическими замечаниями consistency-checker orchestrator выполняет rework-loop (возврат к `worker` для строки 4 / к `rework` для строки 6, max 3 итерации, затем `utility`).
5. **Наблюдение (known issue, НЕ нарушение):** в **незалоченной** сессии (узкое окно гонки до `session.created`) вызов view-image может залогировать info «Reverse routing hint (not enforced)» с hint `orchestrator` — view-image теперь в обеих таблицах, а `detectAgentFromSubagent` (L870–877) возвращает первое совпадение. Мутации состояния нет (L518–536: «NO state mutation») — это ожидаемый диагностический шум задокументированной known issue (PLUGIN.md L763).

### 4. Финальная консистентность

- Прогнать `consistency-checker` против ARCHITECTURE.md: конфигурация обоих primary agents соответствует lockdown-таблице L166–178; routing tables идентичны во всех трёх источниках (orchestrator — **24 агента**, plankestrator — **10 агентов**, включая `view-image`); `view-image` — общий агент обоих primary (shared utility agent); описание слоёв защиты (**3 layers**) соответствует реальности; счётчики (34 whitelist-записи / 33 уникальных субагента / 35 уникальных агентов) согласованы в ARCHITECTURE.md, AGENTS.md, MCP_SETUP.md, opencode-config/\*, deploy-package/\*.

**Критерий успеха всего плана:** все проверки раздела «Верификация» пройдены; в контрольных сессиях отсутствуют error-логи `PRIMARY AGENT ACTION TOOL VIOLATION`, `IDENTITY DRIFT REJECTED`, `FORBIDDEN VOCABULARY DETECTED`, `INVALID JSON OUTPUT` и warn-лог `Agent corrected via routing fallback` для залоченных сессий; вызов `view-image` из plankestrator **проходит**; вызов `generate-image*` из plankestrator **отклоняется**.

---

## Примечания для исполнителя

1. **Смещение номеров строк:** все удаления/вставки смещают последующие строки. Правки выполнять либо точной заменой строк (string replace), либо **снизу вверх** по файлам:
   - `opencode.json` (пакет A): L1441–1442 + запятая L1440 (Рек. 2) → L1416–1427 (Рек. 1, plankestrator) → L1227–1239 (Рек. 1, orchestrator); всего удаляется 2 + 8 + 8 = 18 строк;
   - `orchestrator.md` (пакет C): L118–125 (Рек. 7, включая правку L120 Рек. 1) → L109 (Рек. 5) → L59 (Рек. 4) → L49 (Рек. 6) → L15 (Рек. 1);
   - `plankestrator.md` (пакет D): L110 (Рек. 1) → вставка после ~L58 (Рек. 2b, семантическое правило) → L26 (Рек. 2b) → L15 (Рек. 1) → L12 (Рек. 1); после вставки все номера ниже ~L58 (PROHIBITIONS L110–113 и др.) смещаются;
   - `workflow-enforcement.ts` (пакет B): L643–656 (Рек. 3) → L42–43 (Рек. 2b);
   - `ARCHITECTURE.md` (пакет E): L180–185 (Рек. 1) → L58 + опциональная секция (Рек. 2b) → L56 → L55 → вставка после L48 → L36;
   - `AGENTS.md` (пакет E): вставка после L252 → L240 (Рек. 2b) → L207 (Рек. 1).
2. **Запятые:**
   - JSON — единственная правка запятой: строка **1440** (`"view-image": "allow",` → без запятой; Рек. 2, шаг 2). Правка запятой на L1439 из V1 **отменена** — L1439 (`"devops-readonly": "allow",`) сохраняет запятую. Удаления L1232–1239 и L1420–1427 правки запятых не требуют (после `"patch": "deny",` следует `"task": {`).
   - TypeScript — запятая после `"devops-readonly"` добавляется в Рек. 2b (плагин L42; копия deploy-package L39).
3. **Не выходить за объём:** секции subagents в opencode.json; списки `FORBIDDEN_VOCAB` (L88–99), `PRIMARY_AGENT_ALLOWED_TOOLS` (L466), `REQUIRED_JSON_FIELDS` (L49–52); обработчики `message.updated` (L337–353) и `detectAgentFromSubagent` (L870–877); таблица ARCHITECTURE.md L166–178 и таблица orchestrator L7–34; `OPENCODE_ROUTING_TABLE` **orchestrator.md** L26 — не менять. **`OPENCODE_ROUTING_TABLE` plankestrator.md L26 — МЕНЯЕТСЯ** (Рек. 2b; запрет V1 снят). Ключи `view-image`/`generate-image`/`generate-image-gpt` в секции `orchestrator` opencode.json (L1262, L1264, L1265) — не трогать. Файлы `research-writer-simple.md`/`research-writer-complex.md` (`"view-image": "allow"`, L16) и allowlist `plankestrator-identity-probe` (MCP_SETUP.md L418) — не трогать (прецеденты уже корректны). Скрипт `deploy-package\scripts\verify.ps1` (L110–114) правкой не затронут.
4. **Требование перезапуска:** рекомендации 1, 2, 2b, 3–7 — один общий перезапуск opencode после всех правок (Фаза 3). До перезапуска изменения конфигурации, промптов и плагина в силу не вступают. Правки документации (пакеты E, F: ARCHITECTURE.md, AGENTS.md, MCP_SETUP.md, PLUGIN.md, opencode-config/\*, deploy-package/\*) перезапуска не требуют.
5. **Дисциплина счётчиков (Вариант B):** все вхождения «9 agents» → «10 agents» (plankestrator whitelist), Grand Total «33» → «34» (whitelist-записи), «35» (уникальные агенты) — **сохранить**; формула: 24 + 10 = 34 записи, 33 уникальных субагента + 2 primary = 35. Контроль: `grep -rn "9 agents"` и grep Grand Total по всем .md проекта. Список копий определён Изменениями 2/5 исследования; дополнительно проверить grep'ом копии `deploy-package\project-files\MCP_SETUP.md` и `deploy-package\project-files\PLUGIN.md` — при наличии счётчиков plankestrator whitelist синхронизировать их тем же правилом. Пропуск даже одной копии → consistency-checker зафиксирует несоответствие (риск 4.3 исследования).
6. **Порядок Рек. 2b → Рек. 2:** пакет A (opencode.json) не стартовать до завершения пакетов B и D. Обоснование — оборонительное: при прерывании выполнения любое промежуточное состояние «не хуже исходного» (подробно — см. «Порядок выполнения», первый пункт зависимостей).
7. **Known issue (reverse routing hint):** после Варианта B `view-image` присутствует в обеих routing tables; info-лог «Reverse routing hint (not enforced)» с hint `orchestrator` в незалоченных сессиях — ожидаемое поведение задокументированной known issue (PLUGIN.md L763), мутации состояния нет (L518–536). Не считать нарушением при верификации; опционально — примечание в PLUGIN.md (Рек. 2b, шаг 7).
8. **Семантическое правило view-image:** формулировка для plankestrator.md приведена в Рек. 2b (раздел «Семантическое правило»); размещение — `## TURN ALGORITHM`, Turn 1, новый пункт после пункта 2 (L58); нумерацию и форматирование пункта привести по факту файла; альтернативное размещение — явный пункт в CLASSIFICATION RULES. Ключевые инварианты формулировки: отдельный ход (не шаг пайплайна), state machine не продвигается, «ONE Task call per turn» соблюдается, только фаза CLASSIFY, запрет генерации и подмены writer-агентов.
