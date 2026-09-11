# Implementation Plan

**Дата составления:** 2026-09-07
**Источник:** `P:\Programming\Рефакторинг\REMEDIATION_PLAN_V2.md` (утверждённый план V2, 8 рекомендаций, 739 строк)
**Исполнитель:** dev-professor
**Назначение:** атомарная декомпозиция V2 на точные edit-операции (oldString/newString), порядок исполнения, критерии успеха, риски и откаты.

> **Все oldString сверены посимвольно с фактическими файлами 2026-09-07** (прочитаны все 16 целевых файлов V2 + 5 дополнительных копий, обнаруженных при адаптации). Номера строк приведены по состоянию файлов на дату сверки; после каждой вставки/удаления номера ниже смещаются — **полагаться на oldString, а не на номера строк**. Порядок «снизу вверх» сохранён как оборонительная дисциплина V2.
>
> **СОГЛАШЕНИЕ ОБ ОТПУСКАХ:** все блоки Old/New ниже приведены **БАЙТ-В-БАЙТ как в файлах** (code fence на колонке 0, содержимое без дополнительных отступов). Копировать в edit-операции дословно, включая пробелы. Единственное исключение оговорено явно в операции 1.1 (trailing whitespace, см. КТ-2).

---

## 0. Сводка адаптации

### 0.1. Соответствие рекомендациям V2

| Рек. V2 | Операции настоящего плана |
|---------|---------------------------|
| Рек. 1 (todowrite/question deny + удаление мёртвых грантов + «4 layers»→«3 layers») | 1.3, 1.6, 1.7, 1.9, 1.13, 1.15, 1.16, 2.1, 2.9, 2.27 (опц.) |
| Рек. 2 (удалить generate-image* из task-allowlist plankestrator) | 1.14 |
| Рек. 2b (легализация view-image: плагин, промпт, документация, копии) | 1.2, 1.4, 1.5, 2.2–2.8, 2.10–2.26, 2.28–2.34, 3.1–3.3, 3.10–3.18 |
| Рек. 3 (routing-fallback под identity lock) | 1.1, 3.10 (зеркало) |
| Рек. 4 (rework-loop rows 4, 6) | 1.11 |
| Рек. 5 (литеральные токены L109) | 1.10 |
| Рек. 6 (plan_exists строки 5: any→true) | 1.12 |
| Рек. 7 (усиление PROHIBITIONS orchestrator) | 1.8 |

### 0.2. ОБНАРУЖЕННЫЕ ПРОБЕЛЫ (не входят в список файлов V2)

При сверке файлов контрольный grep V2 («`9 agents` → 0 совпадений в контексте plankestrator whitelist») выявил копии, которые V2 не перечислил, но **которые обязательны для прохождения верификации V2 (§1.10, §4)**:

| № | Файл | Правки | Статус |
|---|------|--------|--------|
| G1 | `P:\Programming\Рефакторинг\PLUGIN.md` (корневой) | L157 «(9 agents)», после L171 строка таблицы, L212+L890 routing copies | **ОБЯЗАТЕЛЬНО** — V2 §1.10 контрольный grep по «корень» + consistency-checker Check 2/3 явно проверяет PLUGIN.md |
| G2 | `C:\Users\Admin\.config\opencode\agents\consistency-checker.md` | L100, L115, L116 («9 agents» → «10 agents») | **ОБЯЗАТЕЛЬНО** — иначе прогон consistency-checker (V2 §4 верификация) работает по устаревшим ожиданиям |
| G3 | `P:\Programming\Рефакторинг\deploy-package\agents\consistency-checker.md` | L100, L115, L116 (идентично G2) | **ОБЯЗАТЕЛЬНО** (копия G2 в deploy-пакете) |
| G4 | `P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts` | Те же 2 правки, что live-плагин (L643–644, L42–43; нумерация совпадает — полное зеркало) | РЕКОМЕНДУЕТСЯ — repo-зеркало live-плагина; без синхронизации git-копия расходится с runtime |
| G5 | `C:\Users\Admin\.config\opencode\PLUGIN.md` | L153, после L167, L204+L857 | РЕКОМЕНДУЕТСЯ — live-копия документации |
| G6 | `C:\Users\Admin\.config\opencode\MCP_SETUP.md` | L393–394, L686, после L700, L908 | РЕКОМЕНДУЕТСЯ — live-копия документации |

G1–G3 вынесены в **Фазу 3A (обязательная)**, G4–G6 — в **Фазу 3B (рекомендуемая, решение orchestrator)**. Обнаруженные, но НЕ включённые в план расхождения — раздел 7.4.

### 0.3. Критические точки (где ошибка ломает конфигурацию)

1. **КТ-1 (JSON-запятая):** операция 1.14 — после удаления `"generate-image*"` строка `"view-image": "allow"` ОБЯЗАНА потерять завершающую запятую, а `"devops-readonly": "allow",` (L1439) — СОХРАНИТЬ её. Ошибка → невалидный opencode.json → opencode не стартует. После пакета A обязателен `JSON.parse` (проверка П-4.1).
2. **КТ-2 (trailing whitespace):** в live-плагине строка L649 — пустая строка с 10 пробелами, L642 — с 8 пробелами. Полноблочная замена L643–656 рискует не совпасть. **Поэтому операция 1.1 спроектирована как МИНИМАЛЬНАЯ замена 2 строк (L643–644)** — тело с trailing whitespace не затрагивается и становится телом новой ветки `else if`.
3. **КТ-3 (replaceAll ×2):** паттерн `'devops-readonly'` + `  ]` встречается в каждом PLUGIN.md **ровно 2 раза** (две копии routing table: корневой L212/L890, opencode-config L206/L860, deploy L206/L881, live L204/L857). Ожидание: ровно 2 замены. Одна замена → вторая копия рассинхронизирована; ошибка «multiple matches» при одиночной замене → использовать replaceAll.
4. **КТ-4 (уникальность в opencode.json):** строки `"todowrite": "allow",`, `"devops-readonly": "allow",` и 8 ключей `unity-mcp.*`/`serena_*` встречаются и в секциях subagents (легально — НЕ ТРОГАТЬ). Все операции пакета A используют уникальные многострочные якоря (`    "orchestrator": {`, `    "plankestrator": {`, 5-строчный блок task). Никаких однострочных замен в opencode.json!
5. **КТ-5 (перенумерация):** операция 1.4 вставляет пункт 3 в Turn 1 plankestrator.md — старые пункты 3, 4, 5 ОБЯЗАТЕЛЬНО перенумеруются в 4, 5, 6 (единый блок замены L58–61).
6. **КТ-6 (не выходить за объём):** список «НЕ ТРОГАТЬ» — раздел 7.3.

### 0.4. Инструменты исполнения

- Файлы вне проекта (`C:\Users\Admin\.config\opencode\*`) — **только built-in `edit`/`read` с абсолютными путями** (serena работает в пределах корня проекта `P:\Programming\Рефакторинг`).
- Файлы проекта — `edit` (абсолютные пути) или `serena_replace_content` (literal/regex).
- Все операции — точные строковые замены; «снизу вверх» внутри файла — оборонительный порядок V2 (соблюдать).
- replaceAll-операции (2.20, 2.30, 3.1, 3.12) — ожидать **ровно 2** вхождения.

### 0.5. Параллельность и последовательность

```
ФАЗА 0 (backup) — ДО всего, последовательно
ФАЗА 1:
  Шаг 1.1 (параллельно):  Пакет B (1.1→1.2)  ∥  Пакет D (1.3→1.4→1.5→1.6→1.7)  ∥  Пакет C (1.8→1.9→1.10→1.11→1.12→1.13)
  Шаг 1.2 (СТРОГО ПОСЛЕ B и D):  Пакет A (1.14→1.15→1.16)  →  проверка П-4.1 (JSON.parse) — КРИТИЧЕСКАЯ ТОЧКА
ФАЗА 2 (параллельно с Фазой 1 и внутри себя):  Пакет E (2.1–2.9)  ∥  Пакет F (2.10–2.34)
ФАЗА 3A (обязательная, после или параллельно Фазе 2):  3.1–3.9
ФАЗА 3B (по решению orchestrator):  3.10–3.18
ФАЗА 4: статическая верификация (все grep-проверки раздела 7.2 — таблица П-4.2)
ФАЗА 5: ЕДИНСТВЕННЫЙ перезапуск opencode + функциональные тесты (выполняет orchestrator/пользователь, НЕ dev-professor)
```

Правило V2: **пакет A стартует только после завершения пакетов B и D** (оборонительный порядок «Рек. 2b до Рек. 2»: при прерывании состояние «2b есть, Рек. 2 нет» строго лучше исходного — view-image легализован во всех слоях; тогда как «Рек. 2 есть, 2b нет» сохраняет рассинхрон и с действующей Рек. 3 превращает вызов view-image из plankestrator в жёсткое нарушение).

---

## Phase 0: Резервное копирование

### Operation 0.1: Бэкап runtime-файлов + фиксация git-состояния

- File: создаётся каталог `P:\Programming\Рефакторинг\backup\2026-09-07_remediation_v2\`
- Line: —
- Old: — (файлы существуют)
- New: 5 копий + git-фиксация:

```powershell
$bk = "P:\Programming\Рефакторинг\backup\2026-09-07_remediation_v2"
New-Item -ItemType Directory -Force -Path $bk | Out-Null
Copy-Item "C:\Users\Admin\.config\opencode\opencode.json" $bk
Copy-Item "C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts" $bk
Copy-Item "C:\Users\Admin\.config\opencode\agents\orchestrator.md" $bk
Copy-Item "C:\Users\Admin\.config\opencode\agents\plankestrator.md" $bk
Copy-Item "C:\Users\Admin\.config\opencode\agents\consistency-checker.md" $bk
# в проекте P:\Programming\Рефакторинг (git repo):
git -C "P:\Programming\Рефакторинг" status --short   # зафиксировать состояние ДО правок
git -C "P:\Programming\Рефакторинг" rev-parse HEAD    # записать HEAD для отката
```

Если у dev-professor нет bash — делегировать копирование orchestrator/worker ДО начала Фазы 1.

- Verify: `read` каталога backup → 5 файлов; вывод git status сохранён в отчёте.
- Откат любой фазы: runtime-файлы — `Copy-Item $bk\<file> <оригинальный путь>`; проектные файлы — `git checkout -- <path>` (или `git restore`).

---

## Phase 1: Enforcement-слои и промпты (Рек. 1, 2, 2b-runtime, 3, 4, 5, 6, 7)

### Шаг 1.1 — Пакет B ∥ Пакет D ∥ Пакет C (параллельно: файлы не пересекаются)

---

### ПАКЕТ B — `workflow-enforcement.ts` (live). Порядок: 1.1 → 1.2 (снизу вверх).

### Operation 1.1: Рек. 3 — routing-fallback под identity lock (МИНИМАЛЬНАЯ замена 2 строк, см. КТ-2)

- File: `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`
- Line: 643–644 (тело L645–656 и ветка `} else {` L657–672 НЕ затрагиваются)
- Old (байт-в-байт, 8 пробелов перед `if`, 10 перед `//`):

```ts
        if (otherAllowedAgents.includes(targetAgent)) {
          // Switch to the correct agent based on routing
```

- New (байт-в-байт: `if`/`} else if` — 8 пробелов; комментарии/`throw`/тело — 10 пробелов; закрывающая `` `) `` — 10 пробелов; **текст сообщения внутри template literal — строго column 0**, как в существующем throw на L659–671):

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
```

После замены: старый блок L645–656 (`const previousAgent...` ... `})`) становится телом ветки `else if` без изменений; существующая ветка `        } else {` (L657, «Neither whitelist includes targetAgent») остаётся третьей веткой цепочки. Переменные `identityLocked`, `lockedAgentName`, `otherAgent`, `allowedAgents` уже доступны в области (L636–641, hard-gate L467–469). Итоговый код идентичен целевому блоку V2 (Рек. 3, шаг 2).

- Verify:
  - `grep "identityLocked && otherAllowedAgents.includes(targetAgent)"` → 1
  - `grep "identity lock active"` → 1
  - `grep "} else if (otherAllowedAgents.includes(targetAgent)) {"` → 1
  - `grep "currentAgent = otherAgent"` → 1 (остался только в else-if ветке)
  - `grep "Agent corrected via routing fallback"` → 1 (сохранён)
  - `read` L640–700: ветка `} else {` (L657+) не изменена.

### Operation 1.2: Рек. 2b — view-image в `ROUTING_TABLES.plankestrator`

- File: `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`
- Line: 42–43
- Old (4 пробела перед `"devops-readonly"`, 2 перед `]`):

```ts
    "devops-readonly"
  ]
```

- New:

```ts
    "devops-readonly",
    "view-image"
  ]
```

- Уникальность: в этом файле комбинация встречается 1 раз (таблица orchestrator не содержит devops-readonly). Массив станет L33–44.
- Verify: `grep '"view-image"'` в файле → 2 (L27 orchestrator + новая в plankestrator); `read` L33–44 → 10 агентов, `"view-image"` последним перед `]`.
- НЕ ТРОГАТЬ в плагине: `REQUIRED_JSON_FIELDS` (L49–52), `FORBIDDEN_VOCAB` (L88–99), `PRIMARY_AGENT_ALLOWED_TOOLS` (L466), `message.updated` (L337–353), `detectAgentFromSubagent` (L870–877).

---

### ПАКЕТ D — `plankestrator.md` (live). Порядок: 1.3 → 1.4 → 1.5 → 1.6 → 1.7 (снизу вверх).

### Operation 1.3: Рек. 1 — PROHIBITIONS: добавить question/todowrite

- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 110
- Old:

```
- 🚫 No edit/write/patch/bash/webfetch — those tools belong to specialist agents. Plan and research FILES are written by plan-writer-* / research-writer-* via Task, never by you.
```

- New:

```
- 🚫 No edit/write/patch/bash/webfetch/question/todowrite — those tools belong to specialist agents. Plan and research FILES are written by plan-writer-* / research-writer-* via Task, never by you.
```

- Verify: `grep "webfetch/question/todowrite"` в plankestrator.md → 1.

### Operation 1.4: Рек. 2b — семантическое правило view-image (вставка + ПЕРЕНУМЕРАЦИЯ, см. КТ-5)

- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 58–61 (`## TURN ALGORITHM`, Turn 1, пункты 2–5)
- Old:

```
2. (Optional) Inspect to classify ONLY: `read`/`glob`/`grep` to determine type and complexity. The moment you can fill the JSON — STOP inspecting. You may NOT inspect to answer the user's question itself — that is the writer agents' job.
3. Output the JSON block with `state: "CLASSIFY"`.
4. Call Task with `subagent_type = next_agent` (= pipeline[0]). Pass the user's ORIGINAL request verbatim, plus file instructions: plan-writer-* → "Write the plan to PLAN.md"; research-writer-* → "Write the research to RESEARCH.md".
5. STOP and wait.
```

- New (формулировка пункта 3 — дословно из V2, раздел «Семантическое правило»; старые пункты 3→4, 4→5, 5→6):

```
2. (Optional) Inspect to classify ONLY: `read`/`glob`/`grep` to determine type and complexity. The moment you can fill the JSON — STOP inspecting. You may NOT inspect to answer the user's question itself — that is the writer agents' job.
3. **view-image (auxiliary inspection, CLASSIFY stage only):** if the request references an image (screenshot, diagram, UI mockup, error photo) whose content is REQUIRED to classify it (type / complexity / scope) or to compose the Task prompt for the first pipeline agent, call `view-image` (Task, subagent_type: "view-image") as its OWN separate turn BEFORE the classification turn. Rules: (1) it is an inspection helper, NOT a pipeline step — the state machine does not advance, and the next turn outputs the classification JSON and calls the first pipeline agent as usual; (2) "No more than ONE Task call per turn" still holds — the view-image call occupies its own turn; (3) skip the call if the image content is already described in text or is irrelevant to classification; (4) never use view-image for image GENERATION (generate-image* are orchestrator-only) or as a substitute for plan-writer-* / research-writer-* — deep image analysis for plan/research CONTENT is delegated to the writer agents (research-writer-* already have task.view-image: allow).
4. Output the JSON block with `state: "CLASSIFY"`.
5. Call Task with `subagent_type = next_agent` (= pipeline[0]). Pass the user's ORIGINAL request verbatim, plus file instructions: plan-writer-* → "Write the plan to PLAN.md"; research-writer-* → "Write the research to RESEARCH.md".
6. STOP and wait.
```

- Verify: `grep "auxiliary inspection, CLASSIFY stage only"` → 1; `grep "6. STOP and wait."` → 1; `read` секции TURN ALGORITHM → нумерация Turn 1: 1,2,3,4,5,6 без пропусков/дублей.

### Operation 1.5: Рек. 2b — OPENCODE_ROUTING_TABLE: 10 агентов

- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 26
- Old:

```
OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly"]
```

- New:

```
OPENCODE_ROUTING_TABLE = ["plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex", "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple", "research-writer-complex", "research-reviewer", "devops-readonly", "view-image"]
```

- Verify: `grep '"devops-readonly", "view-image"]'` в plankestrator.md → 1.

### Operation 1.6: Рек. 1 — frontmatter: todowrite deny

- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 15
- Old (2 пробела): `  todowrite: allow`
- New: `  todowrite: deny`
- Verify: `grep "todowrite: deny"` → 1; `grep "todowrite: allow"` → 0.

### Operation 1.7: Рек. 1 — frontmatter: question deny

- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 12
- Old (2 пробела): `  question: allow`
- New: `  question: deny`
- Verify: `grep "question: deny"` → 1; `grep "question: allow"` → 0.

---

### ПАКЕТ C — `orchestrator.md` (live). Порядок: 1.8 → 1.9 → 1.10 → 1.11 → 1.12 → 1.13 (снизу вверх).

### Operation 1.8: Рек. 7 — два новых пункта PROHIBITIONS

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: вставка между 124 и 125
- Old:

```
- 🚫 No read/glob/grep during pipeline execution (Turns 2..N).
- 🚫 Never route to plankestrator, never call an agent outside OPENCODE_ROUTING_TABLE.
```

- New:

```
- 🚫 No read/glob/grep during pipeline execution (Turns 2..N).
- 🚫 No skipping dev-reviewer / consistency-checker — they are mandatory pipeline elements.
- 🚫 No more than ONE Task call per turn. One turn = one pipeline step.
- 🚫 Never route to plankestrator, never call an agent outside OPENCODE_ROUTING_TABLE.
```

- Verify: `grep "No skipping dev-reviewer"` → 1; `grep "No more than ONE Task call per turn"` → 1; `read` PROHIBITIONS → ровно 8 пунктов `🚫`.

### Operation 1.9: Рек. 1 — PROHIBITIONS L120: добавить todowrite

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: 120
- Old:

```
- 🚫 No edit/write/patch/bash/webfetch/question — those tools belong to specialist agents.
```

- New:

```
- 🚫 No edit/write/patch/bash/webfetch/question/todowrite — those tools belong to specialist agents.
```

- Verify: `grep "question/todowrite — those tools"` → 1.

### Operation 1.10: Рек. 5 — обезвредить литеральные токены в правиле plan_exists

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: 109
- Old:

```
**plan_exists=true** if conversation contains: plankestrator JSON with `"type": "PLAN"` / `"state": "COMPLETE"`; a "## PLAN" / "# Implementation Plan" heading; or user references a plan ("implement the plan", "the plan above"). Then `plan_source` = where it came from. Applies to DEV only.
```

- New:

```
**plan_exists=true** if conversation contains: plankestrator JSON with `"type": "PLAN"` / `"state": "COMPLETE"`; a markdown plan heading (an H2 heading whose text is PLAN, or an H1 heading whose text is Implementation Plan); or user references a plan ("implement the plan", "the plan above"). Then `plan_source` = where it came from. Applies to DEV only.
```

- Verify: `grep "## PLAN"` в orchestrator.md → **0**; `grep "# Implementation Plan"` → **0**; `grep "markdown plan heading"` → 1.

### Operation 1.11: Рек. 4 — rework-loop покрывает строки 4 и 6

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: 59
- Old:

```
**Rework loop (rows 1-DEEP, 5, 8):** if consistency-checker reports critical issues, return to `rework` (or the agent named in its `escalate_to`), max 3 iterations, then `utility`.
```

- New:

```
**Rework loop (rows 1-DEEP, 4, 5, 6, 8):** if consistency-checker reports critical issues, return to the agent named in its `escalate_to` (default `rework`; `worker` for row 4), max 3 iterations, then `utility`.
```

- Verify: `grep "rows 1-DEEP, 4, 5, 6, 8"` → 1.

### Operation 1.12: Рек. 6 — ячейка plan_exists строки 5: any → true

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: 49
- Old:

```
| 5 | DEV | COMPLEX | any | `["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]` |
```

- New:

```
| 5 | DEV | COMPLEX | true | `["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]` |
```

- Ячейки `any` в строках 7 (L51, DOCS SIMPLE) и 8 (L52, DOCS DEEP) НЕ менять.
- Verify: `grep "| 5 | DEV | COMPLEX | true |"` → 1; `grep "| 5 | DEV | COMPLEX | any |"` → 0.

### Operation 1.13: Рек. 1 — frontmatter: todowrite deny

- File: `C:\Users\Admin\.config\opencode\agents\orchestrator.md`
- Line: 15 (`question: deny` на L12 уже установлен — не трогать)
- Old (2 пробела): `  todowrite: allow`
- New: `  todowrite: deny`
- Verify: `grep "todowrite: deny"` → 1; `grep "todowrite: allow"` → 0.

---

### Шаг 1.2 — ПАКЕТ A: `opencode.json` (СТРОГО ПОСЛЕ завершения пакетов B и D). Порядок: 1.14 → 1.15 → 1.16 (снизу вверх). Все замены — многострочные блоки с уникальными якорями (КТ-4).

### Operation 1.14: Рек. 2 — task-блок plankestrator: удалить generate-image*, запятую снять с view-image (КТ-1)

- File: `C:\Users\Admin\.config\opencode\opencode.json`
- Line: 1438–1442 (секция `plankestrator.permission.task`, блок L1428–1443)
- Old (отступ 10 пробелов):

```json
          "research-reviewer": "allow",
          "devops-readonly": "allow",
          "view-image": "allow",
          "generate-image": "allow",
          "generate-image-gpt": "allow"
```

- New:

```json
          "research-reviewer": "allow",
          "devops-readonly": "allow",
          "view-image": "allow"
```

- Якорь из 5 строк уникален: только plankestrator содержит `research-reviewer` + `generate-image-gpt` без запятой в одном блоке (в orchestrator между view-image и generate-image стоит docs-planner, и у generate-image-gpt есть запятая — L1262–1265 НЕ ТРОГАТЬ). L1439 `"devops-readonly": "allow",` сохраняет запятую.
- Итог: task-блок = **12 ключей** (10 allow + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`).
- Verify: `read` L1424–1438 → блок из 12 ключей, последний `"view-image": "allow"` БЕЗ запятой; `grep "generate-image"` в диапазоне секции plankestrator → 0.

### Operation 1.15: Рек. 1 — permission-блок plankestrator: deny + удалить 8 мёртвых ключей

- File: `C:\Users\Admin\.config\opencode\opencode.json`
- Line: 1406–1427 (якорь `    "plankestrator": {` уникален)
- Old (отступы: 4 пробела ключ агента, 6 — mode/temperature/permission, 8 — ключи permission):

```json
    "plankestrator": {
      "mode": "primary",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": { "*": "deny" },
        "read": "allow",
        "grep": "allow",
        "glob": "allow",
        "question": "allow",
        "webfetch": "deny",
        "todowrite": "allow",
        "patch": "deny",
        "unity-mcp.*": "allow",
        "serena_find_symbol": "allow",
        "serena_find_referencing_symbols": "allow",
        "serena_get_symbols_overview": "allow",
        "serena_rename_symbol": "allow",
        "serena_safe_delete_symbol": "allow",
        "serena_replace_symbol_body": "allow",
        "serena_insert_after_symbol": "allow",
```

- New:

```json
    "plankestrator": {
      "mode": "primary",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": { "*": "deny" },
        "read": "allow",
        "grep": "allow",
        "glob": "allow",
        "question": "deny",
        "webfetch": "deny",
        "todowrite": "deny",
        "patch": "deny",
```

- Результат: после `"patch": "deny",` (запятая сохраняется) сразу следует `"task": {`. JSON валиден.
- Verify: `read` секции plankestrator → question/todowrite = deny, unity-mcp/serena отсутствуют, `"task": {` следует за `"patch": "deny",`.

### Operation 1.16: Рек. 1 — permission-блок orchestrator: deny + удалить 8 мёртвых ключей

- File: `C:\Users\Admin\.config\opencode\opencode.json`
- Line: 1218–1239 (якорь `    "orchestrator": {` уникален — `"orchestrator-identity-probe": {` не совпадает)
- Old:

```json
    "orchestrator": {
      "mode": "primary",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "read": "allow",
        "grep": "allow",
        "glob": "allow",
        "question": "deny",
        "webfetch": "deny",
        "bash": { "*": "deny" },
        "todowrite": "allow",
        "patch": "deny",
        "unity-mcp.*": "allow",
        "serena_find_symbol": "allow",
        "serena_find_referencing_symbols": "allow",
        "serena_get_symbols_overview": "allow",
        "serena_rename_symbol": "allow",
        "serena_safe_delete_symbol": "allow",
        "serena_replace_symbol_body": "allow",
        "serena_insert_after_symbol": "allow",
```

(`"question": "deny"` на L1227 уже корректен — сохраняется как есть.)

- New:

```json
    "orchestrator": {
      "mode": "primary",
      "temperature": 0.1,
      "permission": {
        "edit": "deny",
        "write": "deny",
        "read": "allow",
        "grep": "allow",
        "glob": "allow",
        "question": "deny",
        "webfetch": "deny",
        "bash": { "*": "deny" },
        "todowrite": "deny",
        "patch": "deny",
```

- Verify: `read` секции orchestrator → todowrite = deny, unity-mcp/serena отсутствуют; task-блок orchestrator (24 агента) НЕ изменён — `view-image`/`generate-image`/`generate-image-gpt`/`git-commit` на месте.

### Проверка П-4.1 (СРАЗУ после пакета A — КРИТИЧЕСКАЯ):

```
node -e "JSON.parse(require('fs').readFileSync('C:/Users/Admin/.config/opencode/opencode.json','utf8')); console.log('JSON OK')"
```

Ожидание: `JSON OK`. При SyntaxError → немедленный откат opencode.json из backup (Operation 0.1), повторить пакет A целиком.

---

## Phase 2: Документация (Пакет E ∥ Пакет F; может идти параллельно Фазе 1)

### ПАКЕТ E — `P:\Programming\Рефакторинг\ARCHITECTURE.md`. Порядок: 2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 (снизу вверх).

### Operation 2.1: Рек. 1 — «4 layers» → «3 layers» (удалить вымышленный слой)

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 180–185
- Old:

```
**Defense in depth — this lock is enforced by 4 layers:**

1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
2. **`tools:` field in agent.md frontmatter** — secondary belt-and-suspenders
3. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
4. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
```

- New:

```
**Defense in depth — this lock is enforced by 3 layers:**

1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
2. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
3. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
```

- Таблицу lockdown L166–178 НЕ менять.
- Verify: `grep "enforced by 3 layers"` → 1; `grep "field in agent.md frontmatter"` → 0.

### Operation 2.2: Рек. 2b — примечание L58 + секция «Shared Utility Agents» (опциональная часть V2 — рекомендуется)

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 58–59 (между L58 и L59 НЕТ пустой строки — oldString учитывает это)
- Old:

```
Note: 33 unique subagents + 2 primary agents = 35 unique agents total.
## Subagent Models
```

- New:

```
Note: 34 whitelist entries (view-image shared by both primaries), 33 unique subagents + 2 primary agents = 35 unique agents total.

### Shared Utility Agents

view-image is a shared utility agent available to BOTH primary agents. It is listed in BOTH routing tables (orchestrator: position 20 of 24; plankestrator: position 10 of 10) and granted `task.view-image: allow` in both permission blocks in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.

## Subagent Models
```

(Если orchestrator отклонит опциональную секцию — заменить только строку Note, сохранив отсутствие пустой строки перед `## Subagent Models`.)

- Verify: `grep "34 whitelist entries"` → 1; `grep "Shared Utility Agents"` → 1.

### Operation 2.3: Рек. 2b — Grand Total 33 → 34

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 56
- Old: `| **Grand Total** | **33** | **35** |`
- New: `| **Grand Total** | **34** | **35** |`
- Verify: `grep "| **Grand Total** | **34** | **35** |"` → 1.

### Operation 2.4: Рек. 2b — строка plankestrator в Agent Count Summary

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 55
- Old: `| plankestrator | 9 | 10 (plankestrator + 9 subagents) |`
- New: `| plankestrator | 10 | 11 (plankestrator + 10 subagents) |`
- Verify: `grep "| plankestrator | 10 | 11"` → 1.

### Operation 2.5: Рек. 2b — строка view-image в таблицу plankestrator whitelist

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: вставка после 48
- Old: `| 9 | devops-readonly | DevOps read-only |` (уникально в файле)
- New:

```
| 9 | devops-readonly | DevOps read-only |
| 10 | view-image | Image analysis |
```

- Verify: `grep "| 10 | view-image | Image analysis |"` → 1; `read` L36–50 → 10 строк таблицы.

### Operation 2.6: Рек. 2b — заголовок whitelist plankestrator

- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 36
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Таблицу orchestrator (L7–34, `| 20 | view-image | Image analysis |` на L30) НЕ менять.
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### ПАКЕТ E — `P:\Programming\Рефакторинг\AGENTS.md`. Порядок: 2.7 → 2.8 → 2.9 (снизу вверх).

### Operation 2.7: Рек. 2b — строка view-image в whitelist plankestrator

- File: `P:\Programming\Рефакторинг\AGENTS.md`
- Line: вставка после 252
- Old: `| devops-readonly | DevOps read-only |` (уникально в файле — L252)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L240–254 → 10 строк таблицы, последняя `| view-image | Image analysis |`.

### Operation 2.8: Рек. 2b — заголовок whitelist

- File: `P:\Programming\Рефакторинг\AGENTS.md`
- Line: 240
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` в AGENTS.md → 1.

### Operation 2.9: Рек. 1 — Tool allowance: todowrite/question в Forbidden

- File: `P:\Programming\Рефакторинг\AGENTS.md`
- Line: 207
- Old:

```
| `task` (delegate), `read`, `glob`, `grep` (inspection), `todowrite`, `question` | `bash`, `edit`, `write`, `patch`, `webfetch`, MCP action tools |
```

- New:

```
| `task` (delegate), `read`, `glob`, `grep` (inspection) | `bash`, `edit`, `write`, `patch`, `webfetch`, `todowrite`, `question`, MCP action tools |
```

- Verify: `grep "(inspection) |"` → 1; `grep "(inspection), \`todowrite\`"` → 0.

---

### ПАКЕТ F — копии документации (параллельно с E). Внутри каждого файла — снизу вверх.

### Operation 2.10: Рек. 2b — MCP_SETUP.md: routing table плагина в документации

- File: `P:\Programming\Рефакторинг\MCP_SETUP.md`
- Line: 914
- Old (4 пробела): `    "research-writer-complex", "research-reviewer", "devops-readonly"`
- New (4 пробела): `    "research-writer-complex", "research-reviewer", "devops-readonly", "view-image"`
- Verify: `grep '"devops-readonly", "view-image"'` в MCP_SETUP.md → 1.

### Operation 2.11: Рек. 2b — MCP_SETUP.md: строка view-image во второй таблице whitelist

- File: `P:\Programming\Рефакторинг\MCP_SETUP.md`
- Line: вставка после 705
- Old: `| devops-readonly | DevOps read-only |` (уникально — L705)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L691–708 → 10 строк таблицы.

### Operation 2.12: Рек. 2b — MCP_SETUP.md: заголовок второй таблицы

- File: `P:\Programming\Рефакторинг\MCP_SETUP.md`
- Line: 691
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` в MCP_SETUP.md → 1.

### Operation 2.13: Рек. 2b — MCP_SETUP.md: Task Whitelist (счётчик + список)

- File: `P:\Programming\Рефакторинг\MCP_SETUP.md`
- Line: 393–394
- Old:

```
**Task Whitelist (9 agents):**
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly
```

- New:

```
**Task Whitelist (10 agents):**
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly, view-image
```

- Строку L418 (plankestrator-identity-probe → view-image) НЕ менять (прецедент уже корректен). Permissions-таблицы L360–366/L381–391 — вне объёма V2 (см. 7.4, В-3).
- Verify: `grep "Task Whitelist (10 agents)"` → 1.

### Operation 2.14: Рек. 2b — opencode-config\ARCHITECTURE.md: Grand Total 30 → 31

- File: `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md`
- Line: 53
- Old: `| **Grand Total** | **30** | **32** |`
- New: `| **Grand Total** | **31** | **32** |`
- (В этой копии orchestrator = 21 агент: 21+10 = 31 запись; уникальные агенты 32 — БЕЗ изменений, view-image уже посчитан в whitelist orchestrator.)
- Verify: `grep "| **Grand Total** | **31** | **32** |"` → 1.

### Operation 2.15: Рек. 2b — opencode-config\ARCHITECTURE.md: строка plankestrator в Agent Count Summary

- File: `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md`
- Line: 52
- Old: `| plankestrator | 9 | 10 (plankestrator + 9 subagents) |`
- New: `| plankestrator | 10 | 11 (plankestrator + 10 subagents) |`
- Примечание L55 («30 unique subagents + 2 primary agents = 32») НЕ менять.
- Verify: `grep "| plankestrator | 10 | 11"` → 1.

### Operation 2.16: Рек. 2b — opencode-config\ARCHITECTURE.md: строка view-image в таблицу

- File: `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md`
- Line: вставка после 45
- Old: `| 9 | devops-readonly | DevOps read-only |` (уникально в файле)
- New:

```
| 9 | devops-readonly | DevOps read-only |
| 10 | view-image | Image analysis |
```

- Verify: `read` L33–47 → 10 строк таблицы.

### Operation 2.17: Рек. 2b — opencode-config\ARCHITECTURE.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\opencode-config\ARCHITECTURE.md`
- Line: 33
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.18: Рек. 2b — opencode-config\AGENTS.md: строка view-image

- File: `P:\Programming\Рефакторинг\opencode-config\AGENTS.md`
- Line: вставка после 241
- Old: `| devops-readonly | DevOps read-only |` (уникально — L241)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L229–243 → 10 строк таблицы.

### Operation 2.19: Рек. 2b — opencode-config\AGENTS.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\opencode-config\AGENTS.md`
- Line: 229
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.20: Рек. 2b — opencode-config\PLUGIN.md: ОБЕ routing table copies (replaceAll, КТ-3)

- File: `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md`
- Line: 206–207 и 860–861 (ровно 2 вхождения)
- Old (4 пробела перед `'devops-readonly'`, 2 перед `]`):

```
    'devops-readonly'
  ]
```

- New:

```
    'devops-readonly',
    'view-image'
  ]
```

- Режим: **replaceAll / allow_multiple_occurrences=true**. Ожидание: ровно 2 замены.
- Verify: `grep "'devops-readonly',"` → 2; `grep "'view-image'"` → 4 (2 в таблицах orchestrator L194/L848 + 2 новые в plankestrator).

### Operation 2.21: Рек. 2b — opencode-config\PLUGIN.md: строка view-image в таблицу whitelist

- File: `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md`
- Line: вставка после 168
- Old: `| devops-readonly | DevOps read-only |` (уникально — L168)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L154–170 → 10 строк таблицы.

### Operation 2.22: Рек. 2b — opencode-config\PLUGIN.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md`
- Line: 154
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.23: (ОПЦИОНАЛЬНО, Low) Рек. 2b шаг 7 — примечание к known issue

- File: `P:\Programming\Рефакторинг\opencode-config\PLUGIN.md`
- Line: 736
- Old:

```
**Issue**: If session title doesn't contain "orchestrator" or "plankestrator", session.agent is not set, and the agent doesn't output JSON before making a task call, the reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables).
```

- New:

```
**Issue**: If session title doesn't contain "orchestrator" or "plankestrator", session.agent is not set, and the agent doesn't output JSON before making a task call, the reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables). Confirmed case (post Variant B): `view-image` now exists in BOTH routing tables; for an UNLOCKED session the reverse lookup returns `orchestrator` (iterated first). Effect is limited to the info log "Reverse routing hint (not enforced)" — NO state mutation (see `detectAgentFromSubagent`).
```

- Verify: `grep "Confirmed case (post Variant B)"` → 1.

### Operation 2.24: Рек. 2b шаг 2 — копия плагина deploy-package (ОБЯЗАТЕЛЬНО по V2)

- File: `P:\Programming\Рефакторинг\deploy-package\plugins\workflow-enforcement.ts`
- Line: 39–40
- Old (4 пробела / 2 пробела):

```ts
    "devops-readonly"
  ]
```

- New:

```ts
    "devops-readonly",
    "view-image"
  ]
```

- Уникально в файле (таблица plankestrator L30–40; массив станет L30–41).
- Verify: `grep '"view-image"'` → 2 (L27 orchestrator + новая).

### Operation 2.25: Рек. 2b — deploy-package\project-files\AGENTS.md: строка view-image

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md`
- Line: вставка после 249
- Old: `| devops-readonly | DevOps read-only |` (уникально — L249)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L237–251 → 10 строк таблицы.

### Operation 2.26: Рек. 2b — deploy-package\project-files\AGENTS.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md`
- Line: 237
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.27: (ОПЦИОНАЛЬНО по V2) Рек. 1 — deploy-копия Tool allowance

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\AGENTS.md`
- Line: 207
- Old/New: идентичны операции 2.9.
- Verify: `grep "(inspection) |"` → 1.

### Operation 2.28: Рек. 2b — deploy-package\project-files\ARCHITECTURE.md: Shared Utility Agents в соответствие с фактом

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md`
- Line: 14
- Old:

```
view-image is a shared utility agent available to BOTH primary agents. It is listed in the orchestrator routing table and also granted `task.view-image: allow` in the plankestrator permission block in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.
```

- New:

```
view-image is a shared utility agent available to BOTH primary agents. It is listed in BOTH routing tables (orchestrator and plankestrator) and granted `task.view-image: allow` in both permission blocks in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.
```

- Строку L16 (`### Agent Count: 30 unique subagents + 2 primary = 32 total`) НЕ менять.
- Verify: `grep "listed in BOTH routing tables"` → 1.

### Operation 2.29: Рек. 2b — deploy-package\project-files\ARCHITECTURE.md: whitelist (заголовок + список)

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\ARCHITECTURE.md`
- Line: 10–11
- Old:

```
### plankestrator Whitelist (9 agents)
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly
```

- New:

```
### plankestrator Whitelist (10 agents)
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly, view-image
```

- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.30: Рек. 2b — deploy-package\project-files\PLUGIN.md: ОБЕ routing table copies (replaceAll, КТ-3)

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md`
- Line: 206–207 и 881–882 (ровно 2 вхождения)
- Old/New: идентичны операции 2.20. Режим replaceAll, ожидание ровно 2 замены.
- Verify: `grep "'devops-readonly',"` → 2.

### Operation 2.31: Рек. 2b — deploy-package\project-files\PLUGIN.md: строка view-image

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md`
- Line: вставка после 168
- Old/New: идентичны операции 2.21.
- Verify: `read` L154–170 → 10 строк таблицы.

### Operation 2.32: Рек. 2b — deploy-package\project-files\PLUGIN.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md`
- Line: 154
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 2.33: (ОПЦИОНАЛЬНО, Low) Рек. 2b шаг 7 — примечание к known issue (deploy-копия)

- File: `P:\Programming\Рефакторинг\deploy-package\project-files\PLUGIN.md`
- Line: 757
- Old/New: идентичны операции 2.23.
- Verify: `grep "Confirmed case (post Variant B)"` → 1.

### Operation 2.34: (ОПЦИОНАЛЬНО, Low) Рек. 2b шаг 7 — примечание к known issue (корневой PLUGIN.md)

- File: `P:\Programming\Рефакторинг\PLUGIN.md`
- Line: 763
- Old/New: идентичны операции 2.23.
- Verify: `grep "Confirmed case (post Variant B)"` → 1.

---

## Phase 3: Синхронизация пробелов, обнаруженных при адаптации

### Фаза 3A — ОБЯЗАТЕЛЬНАЯ (без неё верификация V2 §1.10 и §4 не проходит)

### Operation 3.1: G1 — корневой PLUGIN.md: ОБЕ routing table copies (replaceAll, КТ-3)

- File: `P:\Programming\Рефакторинг\PLUGIN.md`
- Line: 212–213 и 890–891 (ровно 2 вхождения)
- Old/New: идентичны операции 2.20. Режим replaceAll, ожидание ровно 2 замены.
- Обоснование: consistency-checker Check 2 требует идентичности PLUGIN.md ↔ ARCHITECTURE.md §1.
- Verify: `grep "'devops-readonly',"` в PLUGIN.md → 2.

### Operation 3.2: G1 — корневой PLUGIN.md: строка view-image в таблицу whitelist

- File: `P:\Programming\Рефакторинг\PLUGIN.md`
- Line: вставка после 171
- Old: `| devops-readonly | DevOps read-only |` (уникально — L171)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L157–173 → 10 строк таблицы.

### Operation 3.3: G1 — корневой PLUGIN.md: заголовок whitelist

- File: `P:\Programming\Рефакторинг\PLUGIN.md`
- Line: 157
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Обоснование: V2 §1.10 — контрольный grep «9 agents» по .md корня проекта → 0 совпадений в контексте plankestrator whitelist; без этой правки совпадение остаётся.
- Verify: `grep "plankestrator Whitelist (9 agents)"` в .md корня, opencode-config, deploy-package → 0.

### Operation 3.4: G2 — live consistency-checker.md: ожидание по плагину

- File: `C:\Users\Admin\.config\opencode\agents\consistency-checker.md`
- Line: 100
- Old:

```
- `workflow-enforcement.ts` → `ROUTING_TABLES.plankestrator` array (9 agents)
```

- New:

```
- `workflow-enforcement.ts` → `ROUTING_TABLES.plankestrator` array (10 agents)
```

- Verify: `grep "array (10 agents)"` → 1.

### Operation 3.5: G2 — live consistency-checker.md: ожидание по AGENTS.md

- File: `C:\Users\Admin\.config\opencode\agents\consistency-checker.md`
- Line: 115
- Old:

```
- `AGENTS.md`: "plankestrator Whitelist (9 agents)" — count must match actual rows
```

- New:

```
- `AGENTS.md`: "plankestrator Whitelist (10 agents)" — count must match actual rows
```

- Verify: `grep "9 agents"` в файле → 0 (после 3.6).

### Operation 3.6: G2 — live consistency-checker.md: ожидание по PLUGIN.md

- File: `C:\Users\Admin\.config\opencode\agents\consistency-checker.md`
- Line: 116
- Old:

```
- `PLUGIN.md`: "plankestrator Whitelist (9 agents)" — count must match actual rows
```

- New:

```
- `PLUGIN.md`: "plankestrator Whitelist (10 agents)" — count must match actual rows
```

- Verify: `grep "9 agents"` → 0; `grep "10 agents"` → 3 (L100, L115, L116). Строки L99/L113/L114 про orchestrator (24 agents) НЕ менять.

### Operation 3.7: G3 — deploy consistency-checker.md: ожидание по плагину

- File: `P:\Programming\Рефакторинг\deploy-package\agents\consistency-checker.md`
- Line: 100
- Old/New: идентичны операции 3.4.
- Verify: `grep "array (10 agents)"` → 1.

### Operation 3.8: G3 — deploy consistency-checker.md: ожидание по AGENTS.md

- File: `P:\Programming\Рефакторинг\deploy-package\agents\consistency-checker.md`
- Line: 115
- Old/New: идентичны операции 3.5.
- Verify: `grep "9 agents"` в файле → 0 (после 3.9).

### Operation 3.9: G3 — deploy consistency-checker.md: ожидание по PLUGIN.md

- File: `P:\Programming\Рефакторинг\deploy-package\agents\consistency-checker.md`
- Line: 116
- Old/New: идентичны операции 3.6.
- Verify: `grep "10 agents"` → 3.

### Фаза 3B — РЕКОМЕНДУЕМАЯ (зеркала; решение orchestrator — выполнять или задокументировать расхождение)

### Operation 3.10: G4 — зеркало плагина в проекте: Рек. 3

- File: `P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts`
- Line: 643–644 (нумерация совпадает с live — зеркало проверено: fallback-сообщение на той же L654)
- Old/New: идентичны операции 1.1 (минимальная замена 2 строк обходит trailing whitespace L649 и здесь).
- Verify: `grep "identityLocked && otherAllowedAgents"` → 1.

### Operation 3.11: G4 — зеркало плагина в проекте: Рек. 2b

- File: `P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts`
- Line: 42–43
- Old/New: идентичны операции 1.2.
- Verify: `grep '"view-image"'` → 2.

### Operation 3.12: G5 — live PLUGIN.md: обе routing table copies (replaceAll)

- File: `C:\Users\Admin\.config\opencode\PLUGIN.md`
- Line: 204–205 и 857–858 (ровно 2 вхождения)
- Old/New: идентичны операции 2.20.
- Verify: `grep "'devops-readonly',"` → 2.

### Operation 3.13: G5 — live PLUGIN.md: строка view-image

- File: `C:\Users\Admin\.config\opencode\PLUGIN.md`
- Line: вставка после 167
- Old: `| devops-readonly | DevOps read-only |` (уникально — L167)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L153–169 → 10 строк таблицы.

### Operation 3.14: G5 — live PLUGIN.md: заголовок whitelist

- File: `C:\Users\Admin\.config\opencode\PLUGIN.md`
- Line: 153
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (9 agents)"` в `C:\Users\Admin\.config\opencode\*.md` → 0 (после 3.17).

### Operation 3.15: G6 — live MCP_SETUP.md: routing table плагина в документации

- File: `C:\Users\Admin\.config\opencode\MCP_SETUP.md`
- Line: 908
- Old (4 пробела): `    "research-writer-complex", "research-reviewer", "devops-readonly"`
- New (4 пробела): `    "research-writer-complex", "research-reviewer", "devops-readonly", "view-image"`
- Verify: `grep '"devops-readonly", "view-image"'` → 1.

### Operation 3.16: G6 — live MCP_SETUP.md: строка view-image

- File: `C:\Users\Admin\.config\opencode\MCP_SETUP.md`
- Line: вставка после 700
- Old: `| devops-readonly | DevOps read-only |` (уникально — L700)
- New:

```
| devops-readonly | DevOps read-only |
| view-image | Image analysis |
```

- Verify: `read` L686–702 → 10 строк таблицы.

### Operation 3.17: G6 — live MCP_SETUP.md: заголовок второй таблицы

- File: `C:\Users\Admin\.config\opencode\MCP_SETUP.md`
- Line: 686
- Old: `### plankestrator Whitelist (9 agents)`
- New: `### plankestrator Whitelist (10 agents)`
- Verify: `grep "plankestrator Whitelist (10 agents)"` → 1.

### Operation 3.18: G6 — live MCP_SETUP.md: Task Whitelist

- File: `C:\Users\Admin\.config\opencode\MCP_SETUP.md`
- Line: 393–394
- Old/New: идентичны операции 2.13 (тексты строк в live-копии совпадают с проектной).
- Заголовок L369 «Task Whitelist (21 agents)» (orchestrator) НЕ менять — устаревшее расхождение live-копии, вне объёма (см. 7.4, В-4).
- Verify: `grep "Task Whitelist (10 agents)"` → 1.

---

## Phase 4: Статическая верификация (ДО перезапуска)

### П-4.1. Валидность JSON (критично — КТ-1):

```
node -e "JSON.parse(require('fs').readFileSync('C:/Users/Admin/.config/opencode/opencode.json','utf8')); console.log('JSON OK')"
```

→ `JSON OK`, без SyntaxError.

### П-4.2. Матрица grep-проверок (ожидание по каждому файлу):

| Файл | Паттерн | Ожидание |
|------|---------|----------|
| orchestrator.md | `todowrite: deny` / `todowrite: allow` | 1 / 0 |
| orchestrator.md | `question: deny` | 1 (L12, не менялся) |
| orchestrator.md | `\| 5 \| DEV \| COMPLEX \| true \|` | 1 |
| orchestrator.md | `rows 1-DEEP, 4, 5, 6, 8` | 1 |
| orchestrator.md | `## PLAN` и `# Implementation Plan` | 0 и 0 |
| orchestrator.md | `No skipping dev-reviewer` / `No more than ONE Task call per turn` | 1 / 1 |
| orchestrator.md | `OPENCODE_ROUTING_TABLE` (L26) | 24 агента, БЕЗ изменений |
| plankestrator.md | `question: deny` / `todowrite: deny` | 1 / 1 |
| plankestrator.md | `"devops-readonly", "view-image"]` | 1 |
| plankestrator.md | `auxiliary inspection, CLASSIFY stage only` | 1 |
| plankestrator.md | `webfetch/question/todowrite` | 1 |
| opencode.json | `"todowrite": "allow"` / `"question": "allow"` | 0 / 0 (во всём файле — были только в primary-секциях) |
| opencode.json | `"todowrite": "deny"` | 2 (обе primary-секции) |
| opencode.json, секция plankestrator | `unity-mcp` / `serena_` | 0 в секции; в секциях subagents сохранены (выборочно: plan-writer-simple, mcp-search) |
| opencode.json, секция plankestrator task | `generate-image` | 0; в секции orchestrator — 2 (L1264–1265 сохранены) |
| workflow-enforcement.ts (live) | `identityLocked && otherAllowedAgents` | 1 |
| workflow-enforcement.ts (live) | `ROUTING_TABLES.plankestrator` | 10 агентов, `"view-image"` после `"devops-readonly",` |
| workflow-enforcement.ts (live) | `PRIMARY_AGENT_ALLOWED_TOOLS` / `FORBIDDEN_VOCAB` / `REQUIRED_JSON_FIELDS` | без изменений |
| ARCHITECTURE.md (проект) | `plankestrator Whitelist (10 agents)` / `34 whitelist entries` / `**34** \| **35**` / `enforced by 3 layers` | 1 / 1 / 1 / 1 |
| Все .md проекта (корень, opencode-config, deploy-package) | `9 agents` в контексте plankestrator whitelist | **0** (допустимы только: CHANGELOG.md L200 «9 agents migrated» — другой контекст; RESEARCH.md, VIEW_IMAGE_RESEARCH.md, REMEDIATION_PLAN*.md — исторические документы) |
| Все .md с routing tables | после `'devops-readonly'`/`"devops-readonly"` в plankestrator-таблице | следует `'view-image'`/`"view-image"` |
| consistency-checker.md (live + deploy) | `9 agents` | 0 |

### П-4.3. Read-проверки секций:

- `read` opencode.json: секция orchestrator (после правок ~L1218–1252) и секция plankestrator (~L1390–1425) — итоговые блоки соответствуют операциям 1.14–1.16.
- `read` workflow-enforcement.ts L33–44 и L640–695 — соответствуют операциям 1.1–1.2.
- `read` plankestrator.md L54–64 — нумерация Turn 1: 1–6, без дублей.

---

## Phase 5: Перезапуск и функциональная верификация (выполняет orchestrator/пользователь)

1. **Единственный перезапуск opencode** после всех правок (покрывает Рек. 1–7; документация перезапуска не требует).
2. В логах: `Workflow enforcement plugin initialized` — плагин загрузился без ошибок компиляции (валидация TS).
3. **Сессия orchestrator:** в тулсете нет `todowrite`/`question`/`unity-mcp.*`/`serena_*`; штатный пайплайн работает (identity line + валидный JSON 8 полей + один Task-вызов за ход); нет `PRIMARY AGENT ACTION TOOL VIOLATION`, нет `INVALID JSON OUTPUT`.
4. **Сессия plankestrator:**
   - **позитивный тест (Рек. 2b):** Task `subagent_type: "view-image"` ПРОХОДИТ на всех слоях (конфиг `"view-image": "allow"` + плагин — агент в `ROUTING_TABLES.plankestrator`, fallback-ветка `otherAgent` не срабатывает); `currentAgent` остаётся `plankestrator`; нет warn `Agent corrected via routing fallback`; `lockedAgentName` не меняется;
   - **негативный тест (Рек. 2 + 3):** Task `subagent_type: "generate-image"` (или `"generate-image-gpt"`) ОТКЛОНЯЕТСЯ: на уровне конфига (`"*": "deny"`), а при достижении плагина в залоченной сессии — throw `WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT (identity lock active)`;
   - **тест семантического правила (Рек. 2b):** запрос с изображением, содержимое которого нужно для классификации → plankestrator вызывает view-image отдельным ходом (ровно один Task-вызов в ходе), в следующем ходе классификационный JSON (7 полей) + вызов первого агента пайплайна; запрос без изображения → вызовов view-image нет;
   - последующие JSON plankestrator валидируются по схеме plankestrator (нет предупреждений об отсутствии `plan_exists`/`plan_source`).
5. **Рек. 5:** в сессии orchestrator процитировать/спровоцировать текст правила `plan_exists` → в логах нет error `FORBIDDEN VOCABULARY DETECTED`.
6. **Рек. 4 (наблюдательная):** при прогоне DEV SIMPLE с планом (строка 4) или DEV SUPERCOMPLEX (строка 6) с критическими замечаниями consistency-checker → rework-loop (возврат к `worker` для строки 4 / к `rework` для строки 6, max 3 итерации, затем `utility`).
7. **Known issue (НЕ нарушение):** в незалоченной сессии (узкое окно гонки до `session.created`) вызов view-image может дать info-лог «Reverse routing hint (not enforced)» с hint `orchestrator` — ожидаемо (PLUGIN.md L763), мутации состояния нет.
8. **Финальная консистентность:** прогон `consistency-checker` против ARCHITECTURE.md: routing tables идентичны в трёх источниках (orchestrator — 24, plankestrator — 10 с view-image); view-image — shared utility agent обоих primary; 3 layers; счётчики (34 whitelist-записи / 33 уникальных субагента / 35 уникальных агентов) согласованы в ARCHITECTURE.md, AGENTS.md, MCP_SETUP.md, opencode-config\*, deploy-package\*.

**Критерий успеха всего плана (V2):** все проверки Фаз 4–5 пройдены; в контрольных сессиях отсутствуют error-логи `PRIMARY AGENT ACTION TOOL VIOLATION`, `IDENTITY DRIFT REJECTED`, `FORBIDDEN VOCABULARY DETECTED`, `INVALID JSON OUTPUT` и warn-лог `Agent corrected via routing fallback` для залоченных сессий; вызов `view-image` из plankestrator **проходит**; вызов `generate-image*` из plankestrator **отклоняется**.

---

## 6. Риски и откаты

### 6.1. Что делать, если правка не применилась

| Симптом | Причина | Действие |
|---------|---------|----------|
| edit: «oldString not found» | Файл изменился после сверки 2026-09-07; или не учтён trailing whitespace (КТ-2); или сбиты отступы при копировании из плана | STOP, НЕ угадывать. `read` фактического участка, скопировать oldString посимвольно из файла, повторить. Операция 1.1 спроектирована минимальной заменой 2 строк именно чтобы обойти trailing whitespace |
| edit: «Found multiple matches» | oldString не уникален | Расширить oldString соседними строками (якоря заложены: агент-ключи в opencode.json, 5-строчный блок в 1.14, `  ]` в 1.2). Для replaceAll-операций (2.20, 2.30, 3.1, 3.12) ровно 2 вхождения ожидаемы |
| replaceAll дал ≠2 замен в PLUGIN.md-копиях | Файл-копия отличается от сверенного | STOP: `grep "'devops-readonly'"` по файлу, выявить фактическое число копий routing table, скорректировать и зафиксировать в отчёте |
| `JSON OK` не получен после пакета A (КТ-1) | Висячая/пропущенная запятая | Откат opencode.json из backup (0.1), повторить 1.14–1.16 целиком одним проходом |
| Плагин не загружается после перезапуска | Синтаксическая ошибка TS (итог операций 1.1/1.2) | Откат workflow-enforcement.ts из backup, повторить пакет B; проверить template literal: текст сообщения column 0, закрывающая `` `) `` — 10 пробелов |
| Сбита нумерация Turn 1 plankestrator.md (КТ-5) | Частичное применение операции 1.4 | `read` L54–66; при дублях/пропусках — откатить операцию (New→Old) и повторить единым блоком |

### 6.2. Файлы, требующие резервного копирования (Фаза 0 — ОБЯЗАТЕЛЬНО)

- **Критические runtime (вне git — только файловый backup):** `opencode.json`, `plugins\workflow-enforcement.ts`, `agents\orchestrator.md`, `agents\plankestrator.md`, `agents\consistency-checker.md` (все — `C:\Users\Admin\.config\opencode\`).
- **Проектные файлы (под git):** фиксируется HEAD + `git status` до правок; откат — `git restore <path>`. Файловый backup для Фаз 2–3 не обязателен (git покрывает), но рекомендуемые копии 3B (live `C:\...\opencode\PLUGIN.md`, `MCP_SETUP.md`) — вне git: при их правке снять копии в тот же backup-каталог.

### 6.3. Откат отдельных операций

Каждая операция обратима: поменять местами Old/New и выполнить как edit. Откатывать снизу вверх по файлу (как при прямом ходе). Откат пакета A целиком — восстановление opencode.json из backup безопаснее построчного отката (риск запятых).

### 6.4. Риски, принятые без изменений (по V2)

1. **Reverse routing hint (Low, остаточный):** view-image в обеих таблицах → в незалоченных сессиях info-лог с hint `orchestrator`; мутации состояния нет (`detectAgentFromSubagent` L870–877 только логирует, L518–536 «NO state mutation»). Смягчение: identity lock на `session.created`; опциональные операции 2.23/2.33/2.34 документируют кейс.
2. **Гонка до session.created:** для незаблокированных сессий fallback-переключение сохранено намеренно (race-condition mitigation) — ветка `else if` операции 1.1.
3. **Счётчики 34 vs 33:** расхождение «whitelist-записи (34) ≠ уникальные субагенты (33)» — осознанное (view-image shared), зафиксировано примечанием L58 (операция 2.2).

---

## 7. Приложение

### 7.1. Зависимости между операциями (сводно)

```
0.1 ──> всё
1.1 ──> 1.2 (один файл, снизу вверх)                        ┐
1.3 ──> 1.4 ──> 1.5 ──> 1.6 ──> 1.7 (один файл)             ├─ пакет B ∥ D ∥ C
1.8 ──> 1.9 ──> 1.10 ──> 1.11 ──> 1.12 ──> 1.13 (один файл) ┘
(B, D завершены) ──> 1.14 ──> 1.15 ──> 1.16 ──> П-4.1 [ЖЁСТКАЯ зависимость V2: «Рек. 2b до Рек. 2»]
2.* и 3.* — независимо от Фазы 1 (файлы не пересекаются); внутри файла — снизу вверх
3.3 ──> проверяется совместно с 2.17/2.19/2.22/2.26/2.29/2.32 (общий grep «9 agents» → 0)
3.10/3.11 (зеркало G4) — повторять 1.1/1.2 ТОЛЬКО после их успешного применения в live-плагине
П-4.* ──> после всех правок; Фаза 5 ──> после П-4 (единственный перезапуск)
```

### 7.2. Итоговые числа (контрольные значения V2)

- plankestrator routing table: **10 агентов** во всех источниках (плагин live + зеркало + deploy-копия, промпт L26, ARCHITECTURE.md, AGENTS.md, PLUGIN.md ×4, MCP_SETUP.md ×2).
- plankestrator task-allowlist opencode.json: **12 ключей** (10 allow + `"*": "deny"` + `"orchestrator-identity-probe": "deny"`).
- orchestrator: **24 агента** — везде БЕЗ изменений.
- Grand Total: проект **34/35**, opencode-config **31/32**; «35» и «32» (уникальные) не меняются.
- Слои защиты: **3 layers** (было 4).
- PROHIBITIONS orchestrator: **8 пунктов** (было 6); plankestrator — 8 пунктов (состав не меняется, правится текст первого).
- Удаляется строк в opencode.json: 2 (task) + 8 (plankestrator permission) + 8 (orchestrator permission) = **18**.

### 7.3. НЕ ТРОГАТЬ (запретная зона V2, примечание 3)

- Секции subagents в opencode.json (ключи `unity-mcp.*`/`serena_*`/`view-image` там легальны; `research-writer-*` сохраняют `"view-image": "allow"`).
- opencode.json orchestrator task-ключи L1262/L1264/L1265 (view-image, generate-image, generate-image-gpt) и весь 24-агентный блок.
- Плагин: `FORBIDDEN_VOCAB` (L88–99), `PRIMARY_AGENT_ALLOWED_TOOLS` (L466), `REQUIRED_JSON_FIELDS` (L49–52), `VALID_VALUES`, обработчик `message.updated` (L337–353), `detectAgentFromSubagent` (L870–877), ветка `} else {` L657–672.
- orchestrator.md: `OPENCODE_ROUTING_TABLE` (L26), `question: deny` (L12).
- ARCHITECTURE.md: lockdown-таблица L166–178, таблица orchestrator L7–34.
- opencode-config\ARCHITECTURE.md: примечание L55; deploy-package\project-files\ARCHITECTURE.md: L16.
- Файлы агентов `research-writer-simple.md`/`research-writer-complex.md` (L16), allowlist `plankestrator-identity-probe` (MCP_SETUP.md L418), `deploy-package\scripts\verify.ps1` (L110–114).
- Исторические/исследовательские документы: CHANGELOG.md (L200 — другой контекст «9 agents migrated»), RESEARCH.md, VIEW_IMAGE_RESEARCH.md, REMEDIATION_PLAN.md (V1), REMEDIATION_PLAN_V2.md, VALIDATION_REPORT.md.

### 7.4. Вне объёма — обнаружено при адаптации, требует ОТДЕЛЬНОГО решения orchestrator (в план НЕ включено)

| № | Находка | Детали | Почему вне плана |
|---|---------|--------|------------------|
| В-1 | `deploy-package\opencode.json` — устаревший снапшот конфига | plankestrator task-блок (L1427–1429) содержит `view-image`/`generate-image`/`generate-image-gpt` — та же Проблема №2; orchestrator — 21 агент (устарел против 24) | V2 не включает файл; полная синхронизация deploy-снапшота — отдельная задача (пакет устарел целиком, не только по Рек. 1/2/2b) |
| В-2 | `deploy-package\agents\plankestrator.md` (L12 `question: allow`, L15 `todowrite: allow`, L66 — 9-агентная таблица) и `deploy-package\agents\orchestrator.md` (L15 `todowrite: allow`, L31 — 21 агент) | Развёрнутые копии промптов не получат правки Рек. 1/2b/4–7 | V2 не включает deploy-package\agents\* в целевые файлы; при деплое пакета проблемы воспроизведутся — рекомендовать отдельную синхронизацию всего deploy-пакета |
| В-3 | Permissions-таблицы MCP_SETUP.md (проект: L360–366 orchestrator, L381–391 plankestrator; live-копия: те же разделы) показывают `question/todowrite/unity-mcp.*/serena_* = allow` | После Рек. 1 таблицы устареют | Рек. 1 V2 не перечисляет MCP_SETUP.md среди файлов; расширять объём без решения orchestrator нельзя |
| В-4 | live MCP_SETUP.md L369 «Task Whitelist (21 agents)» (orchestrator) | Фактически 24 агента — расхождение существовало ДО этого плана | Предсуществующее расхождение live-копии, вне всех рекомендаций |
| В-5 | Глобальный `C:\Users\Admin\.config\opencode\AGENTS.md` | Проверено grep: упоминаний `todowrite`/«9 agents» НЕТ — уточнение V2 (L33) подтверждено, правки не требуются | — (подтверждение отсутствия проблемы) |
| В-6 | `deploy-package\project-files\MCP_SETUP.md` | Проверено по V2 примечанию 5: счётчиков plankestrator whitelist нет (единственное упоминание devops-readonly — L59, список субагентов) → правки не требуются | — (подтверждение отсутствия проблемы) |

---

*Конец плана. Всего операций: 1 (Фаза 0) + 16 (Фаза 1) + 25 (Фаза 2) + 18 (Фаза 3) = 60, из них обязательных 54, опциональных 4 (2.23, 2.27, 2.33, 2.34), рекомендуемых 9 (3.10–3.18). Один перезапуск opencode в Фазе 5 покрывает все runtime-изменения.*
