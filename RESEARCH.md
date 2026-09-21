# Исследование: Структура проекта opencode (локальная FS-разведка)

**Дата:** 2026-09-21
**Метод:** Wave → Barrier → Synthesis, 3 параллельных scout-агента (локальная FS-разведка) + 1 верификационная волна (прямые grep/read)
**Источники:** только локальная файловая система — MCP-инструменты не использовались (проверка R12)

---

## Research Question

Структура проекта opencode: (1) конфигурационные файлы и их роли, (2) полная архитектура агентов включая нового агента `scout`, (3) синхронизация счетчиков агентов во всех источниках документации.

## Research Strategy

Декомпозиция на 3 независимых подвопроса → одна параллельная scout-волна (3 Task-вызова в одном сообщении, дешёвая модель MiniMax-M2.7) → barrier → обнаруженные противоречия → верификационная волна (точечные grep/read на сильной модели) → синтез.

## Sources Consulted

- `C:\Users\Admin\.config\opencode\agents\*.md` — 36 файлов агентов (frontmatter: модель, permissions)
- `C:\Users\Admin\.config\opencode\opencode.json` — главный конфиг (plugin, MCP-серверы, провайдер моделей)
- `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` — плагин принудительного контроля (routing tables, источник истины)
- `C:\Users\Admin\.config\opencode\PLUGIN.md` — живая документация плагина
- `P:\Programming\Рефакторинг\ARCHITECTURE.md` (+ копии в `opencode-config/`, `deploy-package/project-files/`)
- `P:\Programming\Рефакторинг\AGENTS.md`, `MCP_SETUP.md`, `PLUGIN.md`, `deploy-package\README.md`, `deploy-package\DEPLOYMENT_GUIDE.md`, `deploy-package\scripts\verify.ps1`

---

## Findings

### 1. Конфигурационные файлы

**Карта конфигурации проекта:**

| Файл | Расположение | Роль |
|------|-------------|------|
| `opencode.json` | `C:\Users\Admin\.config\opencode\` | Главный конфиг: провайдер `bifrost-litellm` (50+ моделей, строки 29–843), плагин, MCP-серверы |
| `agents/*.md` | `C:\Users\Admin\.config\opencode\agents\` | 36 определений агентов (frontmatter: mode, model, temperature, permissions) |
| `workflow-enforcement.ts` | `C:\Users\Admin\.config\opencode\plugins\` | Единственный плагин; routing tables, JSON-валидация, identity lock, inspection budget |
| `ARCHITECTURE.md` | корень проекта + 2 копии | Архитектурные требования: whitelist, пайплайны, модели, счетчики |
| `AGENTS.md` | корень проекта + глобальный `~/.config/opencode/AGENTS.md` | Правила проекта: MCP-first, приоритеты инструментов, routing tables |
| `MCP_SETUP.md` | корень + `~/.config/opencode/` + deploy-package | Настройка MCP-серверов и таблицы моделей/агентов |
| `PLUGIN.md` | `~/.config/opencode/` + 2 копии в проекте | Документация плагина (lifecycle hooks, routing tables) |
| `verify.ps1` | `deploy-package\scripts\` | Скрипт верификации установки |

**Взаимосвязи (цепочка истины):**

```
opencode.json ──подключает──> plugins/workflow-enforcement.ts (источник истины routing)
        │                              │
        │                              ▼
        │                    ARCHITECTURE.md / AGENTS.md / PLUGIN.md (документация,
        │                              │    должна зеркалить плагин)
        ▼                              ▼
agents/*.md (36 файлов) <── verify.ps1 (проверяет наличие файлов)
```

**Ключевые факты:**
- `opencode.json:845` — `"plugin": ["./plugins/workflow-enforcement.ts"]` — единственный плагин
- `opencode.json:848-890` — 5 MCP-серверов: `zai_web_reader`, `zai_web_search`, `zai_zread` (remote), `serena` (local), `unity-mcp` (remote)
- `workflow-enforcement.ts:92` — `INSPECTION_BUDGET = 3`
- В корне проекта дополнительно найдено ~25 MD-файлов верхнего уровня (планы, исследования, CHANGELOG) и 4 PS1-скрипта

### 2. Архитектура агентов

**Структура: 2 primary + 34 субагента = 36 всего**

- **Primary (2):** `orchestrator` (операционные задачи: BUGFIX/DEVOPS/DEV/DOCS) и `plankestrator` (планирование: PLAN/RESEARCH). Подтверждение: `AGENTS.md:181` — "OpenCode uses two primary agents"; `workflow-enforcement.ts:1001` — hard gate только для этих двух. Обе на модели `bifrost-litellm/QWEN3.7-plus` (`AGENTS.md:413`)
- **Субагенты (34):** из них 33 уникальных в routing tables (view-image общий для обоих primary) + `scout` вне routing tables

**Routing tables (источник истины — `workflow-enforcement.ts:7-44`):**
- orchestrator whitelist = **24** агента (строки 7–32, последний — `git-commit`)
- plankestrator whitelist = **10** агентов (строки 33–44, включая общий `view-image`)

**Профиль агента `scout` (`agents\scout.md`, 68 строк):**

| Атрибут | Значение | Источник |
|---------|----------|----------|
| mode | `subagent` | scout.md:3 |
| model | `bifrost-litellm/MiniMax-M2.7` | scout.md:4 |
| temperature | 0.1 | scout.md:5 |
| allow tools | `read`, `glob`, `grep` | scout.md:7-9 |
| deny tools | `edit`, `write`, `bash`, `webfetch`, `patch`, `todowrite`, `question`, `task` | scout.md:10-17 |
| Роль | "Local filesystem reconnaissance scout. Cheap parallel exploration" | scout.md:2 |
| Вызывается из | research-writer-*, plan-writer-*, dev-planner, bugfix-triage, plan-bug | scout.md:22 |
| Принцип вывода | "POINTER, NOT TRANSCRIPT", ≤3 строки на finding, цель ≤60 строк | scout.md:29-35, 64-67 |
| Запреты | НЕТ анализа/синтеза/выводов, НЕТ модификаций, НЕТ выдуманных путей | scout.md:48-54 |
| В routing tables | НЕТ — "a subagent OUTSIDE both routing tables (never a pipeline step)" | ARCHITECTURE.md:59 |

**Распределение моделей по 36 агентам (по фактическим frontmatter):**

| Модель | Кол-во | Агенты |
|--------|--------|--------|
| MiniMax-M2.7 | **6** | mcp-github, mcp-read, mcp-search, scout, summarizer, utility |
| MiniMax-M3 | 5 | devops-agent, devops-readonly, plan-bug, view-image, worker |
| QWEN3.7-plus | **7** | orchestrator, plankestrator, orchestrator-identity-probe, plankestrator-identity-probe, bugfix, consistency-checker, plan-writer-simple |
| Kimi K3 | 4 | dev-reviewer, plan-reviewer-complex, research-writer-complex, rework |
| qwen3.8-max | 3 | dev-planner, devops-reviewer, plan-writer-complex |
| GLM-5.3 | **4** | dev-professor, execute-bug, plan-reviewer-simple, research-reviewer |
| mimo-v2.5 | 3 | generate-image, generate-image-gpt, git-commit |
| mimo-v2.5-pro | 2 | docs-writer, research-writer-simple |
| GLM-5.3-Flash | 1 | bugfix-triage |
| qwen3.8-flash | 1 | docs-planner |

Итого: 7+6+5+4+4+3+3+2+1+1 = **36** ✓ (identity-probe входят в строку QWEN3.7-plus; сверено с frontmatter всех 36 файлов и `MCP_SETUP.md:50-59` — совпадает, кроме отсутствующего там view-image, см. Проблему 4)

### 3. Синхронизация счетчиков

**Сводная таблица (эталон: whitelist 24/10, субагенты 34, всего 36, MiniMax-M2.7 = 6):**

| Источник | orch. | plank. | Σ sub | Total | M2.7 | Статус |
|----------|-------|--------|-------|-------|------|--------|
| `workflow-enforcement.ts` (live, источник истины) | 24 (L7-32) | 10 (L33-44) | 34 | 36 файлов | 6 | ✅ |
| `ARCHITECTURE.md` (корень) | 24 (L7) | 10 (L36) | 34 (L57) | 36 (L57) | 6 (L81-85,102) | ✅ |
| `ARCHITECTURE.md` (`opencode-config/`) | 24 | 10 | 34 | 36 | — | ✅ |
| `ARCHITECTURE.md` (`deploy-package/project-files/`) | 24 | 10 | — | 36 (L16) | — | ✅ |
| `MCP_SETUP.md` (корень) | 24 (L677) | 10 (L706) | 34 (L43) | 36 (L44) | 6 (L51) | ✅ |
| `AGENTS.md` (корень) | 24 (L213) | 10 (L242) | — | — | — | ✅ |
| `deploy-package\README.md` | — | — | 34 (L5,97) | 36 (L14,88) | — | ✅ |
| `PLUGIN.md` (`deploy-package/project-files/`) | 24 (L126) | 10 (L157) | — | — | — | ✅ |
| `PLUGIN.md` (`opencode-config/`) | 24 (L126) | 10 (L157) | — | — | — | ✅ |
| `verify.ps1` | — | — | — | ≥36 файлов (L108) | — | ✅ (частично) |
| **`PLUGIN.md` (live, `~/.config/opencode/`)** | **21 (L126)** | 10 (L153) | — | — | — | ⚠️ **РАССИНХРОН** |
| `DEPLOYMENT_GUIDE.md` | — | — | — | 36 файлов (L88, L93) | — | ✅ (только счетчик файлов) |
| `MCP_SETUP.md` (`deploy-package/project-files/`) | 21 (L1296) | 9 (L1296) | 30 (L43) | 32 (L44) | M3=7 (L54) | ⚠️ **УСТАРЕЛ** |

---

## Key Facts

- 36 файлов агентов в `agents/*.md`; 2 primary (orchestrator, plankestrator), 34 субагента — источник: `workflow-enforcement.ts:7-44`, `ARCHITECTURE.md:57`
- Routing tables: orchestrator = 24, plankestrator = 10, view-image общий — источник: `workflow-enforcement.ts:7-44`
- `scout` — read-only разведчик на MiniMax-M2.7, вне routing tables, вызывается субагентами через их `permission.task` — источник: `scout.md:2-22`, `ARCHITECTURE.md:59`
- MiniMax-M2.7 = ровно 6 агентов (utility, mcp-github, mcp-read, mcp-search, summarizer, scout) — источник: frontmatter файлов + `ARCHITECTURE.md:81-85,102` + `MCP_SETUP.md:51`
- 5 MCP-серверов в opencode.json — источник: `opencode.json:848-890`

## Contradictions / Uncertainties (найденные проблемы)

### ⚠️ Проблема 1: Живой PLUGIN.md рассинхронизирован с плагином
`C:\Users\Admin\.config\opencode\PLUGIN.md:126` — "### orchestrator Whitelist (**21** agents)" вместо 24. В таблице (L130-151) отсутствуют `docs-planner`, `generate-image`, `generate-image-gpt`, `git-commit` (4 агента). При этом сама таблица содержит лишь **20** строк — заголовок «21» не сходится даже с собственным содержимым (24 − 4 отсутствующих = 20; уточнено при ревью). Обе копии PLUGIN.md в проекте корректны (24). **Живая документация отстает от кода плагина.**

### ⚠️ Проблема 2: view-image — модель в файле ≠ модель в документации
Фактический frontmatter: `agents\view-image.md:4` — `model: bifrost-litellm/MiniMax-M3`. Документация: `ARCHITECTURE.md:101` и `AGENTS.md` (view-image permission table) — `bifrost-litellm/Kimi K2.6`. **Конфиг и документация расходятся** (при этом функционально view-image работает — MiniMax-M3 мультимодальна, но документы описывают другую модель).

### ⚠️ Проблема 3: deploy-package/project-files/MCP_SETUP.md устарел
Строка 54 — "MiniMax-M3 | 7 | mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-readonly, plan-bug" — эти mcp-*/summarizer фактически на MiniMax-M2.7. Строки 418-419 также приписывают mcp-search/summarizer к MiniMax-M3. Строка 1299 упоминает устаревшие модели (GLM-5.2, Kimi K2.6/K2.7, GLM-4.7). Дополнительно найдено при ревью: **L43-44** — устаревшие счетчики «Subagents | 30» и «Total unique agents | 32» (эталон 34/36); **L1296** — «orchestrator (21), plankestrator (9)» вместо 24/10; **L50-56** — таблица моделей целиком из выведенных моделей (GLM-5.2, Kimi K2.7, GLM-4.7, GLM-5.1) с неверной разбивкой (worker на QWEN3.7-plus и т.д.). **Deploy-копия MCP_SETUP.md не синхронизирована с корневой — рассинхрон глубже, чем только модели.**

### ⚠️ Проблема 4 (найдена при ревью): корневой MCP_SETUP.md — таблица моделей не сходится с 36
`MCP_SETUP.md:48-59` (корень): сумма строк распределения моделей = 7+6+4+4+4+3+3+2+1+1 = **35 ≠ 36** — агент `view-image` отсутствует в таблице (ни как MiniMax-M3, ни как Kimi K2.6). Это следствие Проблемы 2: документация не решила, какой моделью считать view-image, и молча его опустила. Счетчики агентов (L43-44: 34/36) при этом корректны.

### ℹ️ Не противоречия, а особенности
- `DEPLOYMENT_GUIDE.md` содержит только счетчик файлов агентов (36 — L88, L93, L132, L212, корректен); whitelist-счетчиков 24/10 и разбивки subagents/total нет — проверять больше нечего
- `verify.ps1:108` проверяет только наличие ≥36 файлов агентов (`$agentCount -ge 36`) и 12 ключевых агентов поименно (включая scout) — **routing tables 24/10 скриптом не валидируются**, рассинхрон whitelist документации скриптом не ловится

## Пилотная проверка агента scout — вердикт

| Критерий | Результат |
|----------|-----------|
| Read-only | ✅ Ни одной модификации; deny-лист соблюден (edit/write/bash не вызывались) |
| Без MCP (R12) | ✅ Все 3 скаута использовали только glob/grep/read; MCP-инструменты не вызывались |
| Компактный вывод (pointer, not transcript) | ✅ Формат `file:line — цитата` соблюден; списки файлов компактные |
| Параллельная волна | ✅ 3 Task-вызова в одном сообщении, barrier сработал структурно |
| Качество findings | ✅ Все ключевые факты найдены, включая неочевидный рассинхрон PLUGIN.md |
| Точность | ⚠️ Один скаут ошибочно включил `research-writer-complex` в список MiniMax-M3 (дубль с Kimi K3) и неверно заявил об отсутствии "34"/"36" в ARCHITECTURE.md — обе ошибки вскрыты кросс-проверкой с двумя другими скаутами (2 vs 1) и верификационной волной |

**Вывод по пилоту:** scout работает корректно как read-only разведчик. Как и ожидалось от дешёвой модели, возможны ошибки в подсчетах — паттерн Wave→Barrier→Synthesis с кросс-референсированием их отлавливает. *Поправка ревью:* две ошибки подсчета (QWEN3.7-plus, GLM-5.3) пережили барьер и были исправлены только внешней проверкой research-reviewer — барьер снижает риск ошибок, но не устраняет его полностью (см. Limitations).

## Review Log (research-reviewer, 2026-09-21)

- **Исправлено:** QWEN3.7-plus 6 → 7 (добавлены оба identity-probe; сверка: frontmatter + `MCP_SETUP.md:50`)
- **Исправлено:** GLM-5.3 3 → 4 (добавлен `plan-reviewer-simple`; сверка: `plan-reviewer-simple.md:4` + `MCP_SETUP.md:53`)
- **Исправлено:** строка «Итого» — теперь суммируется в 36 напрямую, без искусственной добавки «+2 identity-probe»
- **Дополнено (Проблема 3):** deploy MCP_SETUP.md — устаревшие счетчики L43-44 (30/32), L1296 (21/9), таблица моделей L50-56 целиком устарела
- **Дополнено (Проблема 4):** корневой MCP_SETUP.md L48-59 — сумма распределения моделей 35 ≠ 36 (отсутствует view-image)
- **Дополнено (Проблема 1):** заголовок «21» расходится и с собственной таблицей живого PLUGIN.md (20 строк)
- **Уточнено:** DEPLOYMENT_GUIDE.md содержит счетчик файлов 36 (L88, L93, L212) — корректен
- **Вердикт ревью:** APPROVED WITH CORRECTIONS — все 3 заявленных расхождения подтверждены, эталонные счетчики (24/10/34/36/M2.7=6) верны, ссылки file:line проверены и точны

## Limitations

- `DEPLOYMENT_GUIDE.md` не содержит whitelist-счетчиков — их синхронизацию подтвердить невозможно (есть только счетчик файлов 36, он корректен)
- Две ошибки подсчета в таблице распределения моделей (QWEN3.7-plus: было указано 6, факт 7; GLM-5.3: было 3, факт 4 — пропущен `plan-reviewer-simple`) пережили верификационную волну и попали в синтез; исправлены при ревью research-reviewer сверкой с frontmatter всех 36 файлов и `MCP_SETUP.md:50-59`. Вывод для пилота: кросс-проверка scout-волн отлавливает ошибки скаутов, но финальные таблицы синтеза также нуждаются во внешней верификации
- Полное содержимое всех 36 файлов агентов не читалось — только frontmatter (модель/permissions) и scout.md целиком
- Подсчет моделей выполнен по строке `model:` в frontmatter; вариации написания (например, `GLM-5.3 (res)`) нормализованы вручную
- verify.ps1 проверен только по релевантным строкам (L108-114), полный аудит скрипта не выполнялся
