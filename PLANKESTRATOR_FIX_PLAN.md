# Plankestrator Self-Work Prevention Plan

> **Источник:** `RESEARCH_PLANKESTRATOR_ISSUE.md` (240 строк) — все ссылки «Рек. N» указывают на раздел «Recommendations» исследования.
> **Цель:** устранить структурную асимметрию — лишить plankestrator физической и мотивационной возможности выполнять plan/research-работу самостоятельно (self-work), доведя его защитные механизмы до уровня orchestrator (инспекционный бюджет, запрет инспекции Turns 2..N, ack-ритуал, few-shot, позитивная рамка роли).

## Целевые файлы

| Файл | Роль в плане | Риск правки |
|---|---|---|
| `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1040 строк) | Hard enforcement (Фаза 1) | **ВЫСОКИЙ** — синтаксическая ошибка отключает ВСЕ enforcement-механизмы обоих primary-агентов |
| `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (118 строк) | Промпт (Фаза 2) | Средний — ошибка ломает только plankestrator |
| `P:\Programming\Рефакторинг\ARCHITECTURE.md` | Синхронизация (Фаза 3) | Низкий |
| `P:\Programming\Рефакторинг\AGENTS.md` | Синхронизация (Фаза 3) | Низкий |
| `P:\Programming\Рефакторинг\PLUGIN.md` | Синхронизация (Фаза 3) | Низкий |
| `P:\Programming\Рефакторинг\CHANGELOG.md` | Запись изменений (Фаза 3) | Низкий |
| `C:\Users\Admin\.config\opencode\opencode.json` (блок plankestrator: строки 1398–1428) | **ТОЛЬКО Фаза 5 (условная)** | **КРИТИЧЕСКИЙ** — битый JSON ломает весь opencode |

## Правила выполнения (ОБЯЗАТЕЛЬНЫ)

1. **Все номера строк в этом плане — ДО правок (исходные).** Внутри каждого файла операции идут **строго снизу вверх** (от больших номеров строк к меньшим), чтобы вставки не сдвигали якоря последующих операций.
2. **Фазы 1 и 2 атомарны каждая:** если хотя бы одна операция фазы не применилась (якорь не найден), откатить ВЕСЬ файл из бэкапа и разобрать причину. Частично применённый plugin-файл = нерабочий plugin.
3. Правки делать anchor-based (exact string replace / `serena_replace_content` с literal-режимом), а не «по номеру строки». Перед каждой правкой перечитать якорную область — если текст не совпадает с `Old:` дословно, СТОП и сверка.
4. Фазы 1 и 2 touch разные файлы → **могут выполняться параллельно**. Фаза 3 — после 1+2. Фаза 4 — после 3. Фаза 5 — только по триггеру (см. «Условие запуска Фазы 5»).

## Карта: рекомендации исследования → операции плана

| Рекомендация исследования | Операции |
|---|---|
| Рек. 1 — Inspection budget (plugin) | 1.5, 1.13 |
| Рек. 2 — Post-pipeline inspection ban (plugin) | 1.5 + атрибуция 1.1–1.3, 1.6, 1.9–1.11 |
| Рек. 3 — Self-work vocabulary (plugin) | 1.7, 1.12 (+ промпт 2.2) |
| Рек. 4 — JSON validation → enforcement | 1.4, 1.8 |
| Рек. 5 — PROHIBITIONS: Turns 2..N + лимит | 2.1, 2.8 |
| Рек. 6 — complexity из текста запроса | 2.4 |
| Рек. 7 — few-shot EXAMPLES | 2.3 |
| Рек. 8 — ack-строка делегирования | 2.6, 2.7 |
| Рек. 9 — сужение COMPLETE-хода | 2.5 |
| Рек. 10 — позитивная рамка роли (строка 19) | 2.9 |
| Рек. 11 — полное удаление read/grep/glob | **Фаза 5 (условная)** |
| Рек. 12 — формулировка description | 2.10 |
| *(сверх исследования)* — атрибуция parent/child сессий | 1.1–1.3, 1.6, 1.9–1.11 (см. обоснование ниже) |

## ⚠️ Критическое расширение сверх исследования: атрибуция сессий

При планировании обнаружена зависимость, без которой **Рек. 2 (post-pipeline ban) неработоспособна**, а наивная реализация **сломала бы writer-агентов**:

- Plugin хранит состояние на уровне модуля (`identityLocked`, `lockedAgentName`, `workflowSteps`, L77–82) и **безусловно сбрасывает его на каждый `session.created`** (L138–141, L227).
- Когда plankestrатор делегирует через Task, opencode создаёт **дочернюю сессию** субагента. Если она эмитирует `session.created`, сброс стирает lock родителя → после ПЕРВОЙ же делегации `identityLocked=false` → любой новый гейт (и существующий Gate A) молча отключается на всю оставшуюся сессию. Это же объясняет, почему writer-агенты сегодня НЕ блокируются Gate A при `edit` — их сессии стирают lock.
- Хуки plugin firing'ают для вызовов других сессий — это подтверждено комментарием L519–536 («build agents ... subsequent edit/write/bash to be blocked» — исторический баг ровно этой природы).

**Решение (обязательная пара, неразрывна):**
1. **parentID-guard** (оп. 1.11): дочерняя сессия (`parentID` присутствует — поле уже перечислено в `suspectFields`, L169) НЕ стирает состояние родителя. Поле `parentID` уже ожидается в payload — см. L169.
2. **activeTaskDepth** (оп. 1.1, 1.2, 1.3, 1.6, 1.9): пока выполняется Task-субагент (depth > 0), ВСЕ вызовы инструментов и сообщения принадлежат субагенту (родитель приостановлен) → enforcement пропускается. Без этого guard'а оп. 1.11 приведёт к тому, что Gate A (L467–511) заблокирует `edit`-вызовы writer-агентов и JSON-гейт (L601–618) заблокирует их Task-вызовы → **поломка всех пайплайнов**.

**Операции 1.11 и 1.1/1.6/1.9 применяются ТОЛЬКО вместе.** Откат — тоже вместе.

---

## Phase 0: Резервное копирование

### Operation 0.1: Создать бэкап всех целевых файлов
- File: (создание каталога) `P:\Programming\Рефакторинг\backup\2026-09-07_plankestrator_selfwork_fix\`
- Line: —
- Old: — (каталог не существует; конвенция проекта — `backup\2026-09-07_remediation_v2\`)
- New (PowerShell):
```powershell
$bk = "P:\Programming\Рефакторинг\backup\2026-09-07_plankestrator_selfwork_fix"
New-Item -ItemType Directory -Force -Path $bk | Out-Null
Copy-Item "C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts" $bk
Copy-Item "C:\Users\Admin\.config\opencode\agents\plankestrator.md" $bk
Copy-Item "C:\Users\Admin\.config\opencode\agents\orchestrator.md" $bk
Copy-Item "C:\Users\Admin\.config\opencode\opencode.json" $bk
Copy-Item "P:\Programming\Рефакторинг\ARCHITECTURE.md" $bk
Copy-Item "P:\Programming\Рефакторинг\AGENTS.md" $bk
Copy-Item "P:\Programming\Рефакторинг\PLUGIN.md" $bk
Copy-Item "P:\Programming\Рефакторинг\CHANGELOG.md" $bk
```
- Verify: `(Get-ChildItem $bk).Count` → **8**. Плюс сверка размеров: каждый бэкап ≥ оригинала по байтам (`Compare-Object (Get-Item <orig>).Length (Get-Item <bak>).Length`).

### Operation 0.2: Зафиксировать исходные контрольные суммы
- File: —
- Line: —
- Old: —
- New: `Get-FileHash <каждый из 8 файлов> -Algorithm SHA256 | Out-File "$bk\HASHES.txt"` — точка сравнения при откате.
- Verify: `Get-Content "$bk\HASHES.txt"` содержит 8 строк с хэшами.

---

## Phase 1: Plugin — hard enforcement (`workflow-enforcement.ts`)

**Порядок выполнения: 1.1 → 1.13 (строго снизу вверх по файлу).** Все строки — исходные (до правок).

### Operation 1.1: `tool.execute.after` — декремент activeTaskDepth
- File: `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`
- Line: 709–711
- Old:
```typescript
    "tool.execute.after": async (input, output) => {
      await client.app.log({
```
- New:
```typescript
    "tool.execute.after": async (input, output) => {
      // v4: Task-субагент завершён (успешно или с ошибкой — after-хук fires в обоих
      // случаях, см. success-флаг ниже) → вернуть enforcement в родительскую сессию.
      if (input.tool === "task") {
        activeTaskDepth = Math.max(0, activeTaskDepth - 1)
      }
      await client.app.log({
```
- Verify: `rg -n "activeTaskDepth = Math.max" "C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts"` → 1 совпадение внутри `tool.execute.after`.

### Operation 1.2: Инкремент activeTaskDepth при валидном routing
- File:同上 (plugin)
- Line: 695–696
- Old:
```typescript
      // Log valid routing
      await client.app.log({
```
- New:
```typescript
      // v4: родительский Task-вызов прошёл routing — сейчас запустится субагент.
      // Пока activeTaskDepth > 0, все tool-вызовы и сообщения принадлежат СУБАГЕНТУ
      // (родитель приостановлен) → enforcement для них подавляется (см. depth-guard).
      activeTaskDepth += 1

      // Log valid routing
      await client.app.log({
```
- Verify: `rg -n "activeTaskDepth \+= 1" <plugin>` → **2** совпадения (после оп. 1.3).

### Operation 1.3: Инкремент activeTaskDepth в built-in bypass
- File: plugin
- Line: 624–634 (блок `BUILTIN_OPENCODE_AGENTS`)
- Old:
```typescript
            extra: { currentAgent, mode: currentMode }
          }
        })
        return
      }
```
- New:
```typescript
            extra: { currentAgent, mode: currentMode }
          }
        })
        activeTaskDepth += 1 // v4: built-in агент (explore/general) тоже субагент
        return
      }
```
- Verify: `rg -nF "built-in агент (explore/general)" <plugin>` → 1; суммарно `activeTaskDepth += 1` → 2 (с оп. 1.6 будет 3).
- ⚠️ Якорь `return\n      }` не уникален — Old-блок включать целиком с `extra: { currentAgent, mode: currentMode }`.

### Operation 1.4: Расширение JSON-гейта (Рек. 4, часть 2)
- File: plugin
- Line: 601–603
- Old:
```typescript
      // Check: agent must output JSON before calling non-identity-probe agents
      const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
      if (!agentJSONStatus && targetAgent && !IDENTITY_PROBE_AGENTS.includes(targetAgent) && !isFirstTaskCall) {
```
- New:
```typescript
      // Check: agent must output JSON before calling non-identity-probe agents.
      // v4: для LOCKED primary-агентов grace-исключение isFirstTaskCall БОЛЬШЕ НЕ
      // применяется — оно существует только как race-mitigation для UNLOCKED сессий
      // (session.created ещё не определил агента). Если identityLocked=true, гонки
      // нет: lock установлен до первого хода модели.
      // Auxiliary-цели остаются исключены: identity-probe и view-image легально
      // вызываются ОТДЕЛЬНЫМ ходом ДО классификационного JSON
      // (plankestrator.md Turn 1 step 3; исследование стр. 128 — ⚠️ нюанс).
      const AUXILIARY_TASK_TARGETS = [...IDENTITY_PROBE_AGENTS, "view-image"]
      const jsonGracePeriod = isFirstTaskCall && !identityLocked
      const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
      if (!agentJSONStatus && targetAgent && !AUXILIARY_TASK_TARGETS.includes(targetAgent) && !jsonGracePeriod) {
```
(Тело `throw new Error(...)` ниже — без изменений.)
- Verify: `rg -n "AUXILIARY_TASK_TARGETS|jsonGracePeriod" <plugin>` → 3 строки (1 объявление массива + 1 объявление grace + 1 использование в условии; `jsonGracePeriod` — 2).
- Обоснование из исследования: `hasOutputtedJSON` и сегодня ставится в `true` ТОЛЬКО при валидном JSON (L391–392), т.е. «не-первый Task call требует валидный JSON» уже работает; реальное расширение = снятие grace для locked-агентов (исследование стр. 118, 134, 205).
- Edge: race — `message.updated` (валидация JSON) теоретически может обработаться ПОСЛЕ `tool.execute.before` первого pipeline-вызова → ложный throw. Self-healing: модель получит текст ошибки, переотправит JSON+Task, флаг уже `true`. Мониторинг: оп. 4.4.

### Operation 1.5: INSPECTION GATE — бюджет + post-pipeline ban + self-work (Рек. 1, 2, 3-эскалация)
- File: plugin
- Line: вставка после 511 (конец Gate A), перед комментарием строки 513
- Old (якорь):
```typescript
        `)
      }

      // Check: is this the first task tool call? (race condition mitigation)
```
- New (вставить МЕЖДУ `}` Gate A и комментарием):
```typescript
        `)
      }

      // ==========================================================
      // INSPECTION GATE (v4) — предотвращение self-work plankestrator.
      // Источник: RESEARCH_PLANKESTRATOR_ISSUE.md, Приоритет 1, пп. 1–3.
      // Проверка выполняется ДО workflowSteps.push() (строка ~564), поэтому
      // inspectionsUsed считает ТОЛЬКО предыдущие вызовы: текущий вызов —
      // (inspectionsUsed+1)-й. Бюджет 3 = разрешены вызовы 1..3, 4-й → throw.
      // Промпт требует от модели max 2 — запас 1 вызов (промпт строже плагина).
      // ==========================================================
      if (
        identityLocked &&
        lockedAgentName === "plankestrator" &&
        (input.tool === "read" || input.tool === "grep" || input.tool === "glob")
      ) {
        // «Пайплайн начался» = был task-вызов ЦЕЛЬЮ которого не является
        // auxiliary-агент. view-image — инспекционный helper ДО классификации
        // (plankestrator.md стр. 59; исследование стр. 128), identity-probe —
        // процедура идентификации. Task с неизвестной целью считается стартом
        // пайплайна (консервативно).
        const AUXILIARY_TARGETS = new Set([...IDENTITY_PROBE_AGENTS, "view-image"])
        const pipelineStarted = workflowSteps.some(
          s => s.tool === "task" && (!s.target || !AUXILIARY_TARGETS.has(s.target))
        )
        const inspectionsUsed = workflowSteps.filter(
          s => s.tool === "read" || s.tool === "grep" || s.tool === "glob"
        ).length

        if (pipelineStarted) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "error",
              message: `INSPECTION AFTER PIPELINE START BLOCKED — plankestrator tried "${input.tool}"`,
              extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool, inspectionsUsed }
            }
          })
          throw new Error(`
⛔ INSPECTION AFTER PIPELINE START — DELEGATE INSTEAD

You are running as: plankestrator (identity-locked).
The pipeline has already started — ALL inspection (read/grep/glob) is now FORBIDDEN.
This is the "Turns 2..N" rule (same rule orchestrator follows).

Fix: advance the pipeline. Identity line → JSON block → Task call with the NEXT
agent from your routing table:
${ROUTING_TABLES.plankestrator.map(a => `   - ${a}`).join("\n")}

Need file/code context? Delegate to devops-readonly via Task — never read yourself.
          `)
        }

        if (selfWorkDetected) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "error",
              message: `INSPECTION BLOCKED — self-work content detected in previous plankestrator message`,
              extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool }
            }
          })
          throw new Error(`
⛔ SELF-WORK CONTENT DETECTED IN YOUR PREVIOUS MESSAGE

You are running as: plankestrator (identity-locked).
Your last message contained plan/research content markers (e.g. "## Findings",
"## Analysis", "Executive Summary"). Producing plan/research CONTENT is self-work —
it belongs to plan-writer-* / research-writer-* agents, NOT to you.

Fix: do NOT continue investigating. Identity line → JSON block → ONE Task call
with next_agent from your routing table → ack line. Your message text must contain
NOTHING else.
          `)
        }

        if (inspectionsUsed >= INSPECTION_BUDGET) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "error",
              message: `INSPECTION BUDGET EXHAUSTED — plankestrator tried "${input.tool}" (used ${inspectionsUsed}/${INSPECTION_BUDGET})`,
              extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool, used: inspectionsUsed, budget: INSPECTION_BUDGET }
            }
          })
          throw new Error(`
⛔ INSPECTION BUDGET EXHAUSTED — CLASSIFY AND DELEGATE NOW

You are running as: plankestrator (identity-locked).
You have used all ${INSPECTION_BUDGET} allowed inspection calls (read/grep/glob).
Further inspection is self-work, not classification.

Fix: STOP inspecting. Type and complexity are determined from the REQUEST TEXT
(number of questions / topics / objects to compare), NOT from files.
Identity line → JSON block → Task call with next_agent from your routing table.
          `)
        }

        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "info",
            message: `Inspection allowed: plankestrator "${input.tool}" (used ${inspectionsUsed}/${INSPECTION_BUDGET}, pipeline not started)`,
            extra: { used: inspectionsUsed, budget: INSPECTION_BUDGET }
          }
        })
      }

      // Check: is this the first task tool call? (race condition mitigation)
```
- Verify: `rg -n "INSPECTION AFTER PIPELINE START|INSPECTION BUDGET EXHAUSTED|SELF-WORK CONTENT DETECTED IN YOUR" <plugin>` → по 1 совпадению каждого; `rg -n "INSPECTION GATE (v4)" <plugin>` → 1.
- Критично: вставка именно ДО `workflowSteps.push()` (L564) — иначе off-by-one в бюджете (текущий вызов засчитается сам себе).

### Operation 1.6: Depth-guard в начале `tool.execute.before`
- File: plugin
- Line: 441–444
- Old:
```typescript
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      // BYPASS: Built-in OpenCode Plan mode (Shift+Tab toggle).
```
- New:
```typescript
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      // v4: пока выполняется Task-субагент (activeTaskDepth > 0), ЛЮБОЙ tool-вызов
      // принадлежит субагенту, а не locked primary-агенту (родитель приостановлен
      // в ожидании результата). Enforcement атрибутирован только родительской
      // сессии → пропускаем. Вложенные делегирования (субагент → суб-субагент)
      // поддерживают баланс счётчика: +1 здесь, -1 в tool.execute.after.
      if (activeTaskDepth > 0) {
        if (input.tool === "task") {
          activeTaskDepth += 1
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "TASK CALL WHILE SUBAGENT ACTIVE — routing check skipped (nested delegation, or prohibited parallel Task from primary agent)",
              extra: { depth: activeTaskDepth }
            }
          })
        }
        return
      }

      // BYPASS: Built-in OpenCode Plan mode (Shift+Tab toggle).
```
- Verify: `rg -n "TASK CALL WHILE SUBAGENT ACTIVE" <plugin>` → 1; `rg -c "activeTaskDepth" <plugin>` → ≥ 8.
- Edge (осознанно принят): параллельный второй Task-вызов от primary-агента в одном ходе уйдёт по этой ветке БЕЗ routing-проверки (warn в логе). Промпт запрещает >1 Task за ход (plankestrator.md L114); полностью «правило одного Task за ход» не реализуемо без границ ходов — см. «Не реализуем сейчас».

### Operation 1.7: Self-work check в `message.updated` (Рек. 3)
- File: plugin
- Line: вставка после 434 (конец forbidden-vocab блока), до 435 (`}` закрытия `message.updated`)
- Old (якорь):
```typescript
            // (e.g. orchestrator mentioning "plan-writer" in an OUT OF SCOPE message).
          }
        }
      }
    },
```
- New:
```typescript
            // (e.g. orchestrator mentioning "plan-writer" in an OUT OF SCOPE message).
          }
        }

        // ==========================================================
        // SELF-WORK CONTENT CHECK (v4) — plankestrator.
        // Заголовочные маркеры ("## Findings" и т.п.) в СОБСТВЕННОМ сообщении
        // locked plankestrator = модель написала plan/research-контент сама
        // вместо делегирования (исследование: Пробел 3, Рек. 3).
        // Эскалация в отличие от forbidden-vocab: выставляет selfWorkDetected →
        // следующий read/grep/glob бросает throw (INSPECTION GATE). Task-вызовы
        // НЕ блокируются — делегирование и есть желаемая коррекция.
        // Guard 1: только assistant-сообщения — пользователь легально может
        // вставить документ с такими заголовками (user-message → пропуск).
        // Guard 2 (выше по потоку): activeTaskDepth > 0 → сообщения субагентов
        // не проверяются (research-writer легально пишет "## Findings" в файл).
        // ==========================================================
        if (identityLocked && lockedAgentName && SELF_WORK_MARKERS[lockedAgentName]) {
          const msgRole = String((message as any).role || (message as any).info?.role || "assistant")
          if (msgRole === "assistant") {
            const selfContent = String(message.content || message.text || "")
            const selfWorkHits = SELF_WORK_MARKERS[lockedAgentName].filter(t => selfContent.includes(t))
            if (selfWorkHits.length > 0) {
              selfWorkDetected = true
              await client.app.log({
                body: {
                  service: "workflow-enforcement",
                  level: "error",
                  message: `SELF-WORK CONTENT DETECTED — ${lockedAgentName} message contains plan/research content markers`,
                  extra: {
                    lockedAgent: lockedAgentName,
                    markers: selfWorkHits,
                    excerpt: selfContent.slice(0, 200)
                  }
                }
              })
            }
          }
        }
      }
    },
```
- Verify: `rg -n "SELF-WORK CONTENT DETECTED —" <plugin>` → 1 (в message.updated); `rg -n "msgRole" <plugin>` → 2.
- ⚠️ Guard 1 (role) — КРИТИЧЕН: без него вставка пользователем текста исследования (содержит `## Findings`-подобные заголовки) заблокировала бы инспекцию plankestrator.
- ⚠️ Guard 2 обеспечивается оп. 1.9 (depth-guard в message.updated) — без него сообщения research-writer'а («## Findings» в его ответе) выставили бы `selfWorkDetected` родителю.

### Operation 1.8: INVALID JSON OUTPUT — warn → error (Рек. 4, часть 1)
- File: plugin
- Line: 382–383
- Old:
```typescript
                level: "warn",
                message: "INVALID JSON OUTPUT",
```
- New:
```typescript
                level: "error",
                message: "INVALID JSON OUTPUT",
```
- Verify: `rg -n -B1 '"INVALID JSON OUTPUT"' <plugin>` → выше стоит `level: "error"`.
- Примечание (исследование стр. 134): смена уровня — только видимость в логах; обратную связь модели даёт оп. 1.4 (throw-гейт).

### Operation 1.9: Depth-guard в `message.updated`
- File: plugin
- Line: 251–255
- Old:
```typescript
      if (event.type === "message.updated") {
        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return
```
- New:
```typescript
      if (event.type === "message.updated") {
        // v4: сообщения, созданные ПОКА выполняется Task-субагент, принадлежат
        // субагенту (writer легально пишет "## Findings" и свой JSON) —
        // enforcement атрибутирован родителю, пропускаем.
        if (activeTaskDepth > 0) return

        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return
```
- Verify: `rg -n "if (activeTaskDepth > 0) return" <plugin>` → 1 (в event-хуке); второй depth-guard (оп. 1.6) — в before-хуке.

### Operation 1.10: Сброс нового состояния в `session.created`
- File: plugin
- Line: 138–141
- Old:
```typescript
        currentAgent = null
        identityLocked = false
        lockedAgentName = null
        hasOutputtedJSON = new Map()
```
- New:
```typescript
        currentAgent = null
        identityLocked = false
        lockedAgentName = null
        hasOutputtedJSON = new Map()
        selfWorkDetected = false
        activeTaskDepth = 0
```
- Verify: `rg -n "selfWorkDetected = false" <plugin>` → 1 (в reset-блоке session.created).
- Примечание: `workflowSteps = []` уже сбрасывается на L227 — не дублировать.

### Operation 1.11: parentID-guard для дочерних сессий (⚠️ пара с 1.6/1.9)
- File: plugin
- Line: 125 (начало блока `session.created`), вставка ПЕРЕД комментарием «CRITICAL FIX» (L126)
- Old:
```typescript
      if (event.type === "session.created") {
        // CRITICAL FIX: Reset module-level identity-lock state on every new
```
- New:
```typescript
      if (event.type === "session.created") {
        // v4: ДОЧЕРНИЕ сессии (Task-субагенты) НЕ должны стирать identity-lock и
        // workflow-состояние РОДИТЕЛЬСКОЙ primary-сессии. Без этого guard'а первая
        // же делегация сбрасывает identityLocked=false и workflowSteps=[]
        // (безусловный reset ниже), молча отключая Gate A, routing enforcement и
        // INSPECTION GATE на остаток сессии родителя. Вызовы инструментов
        // субагентов атрибутируются отдельно через activeTaskDepth
        // (depth-guard в tool.execute.before / message.updated).
        const childCheckData = (event as any).properties?.session
          || (event as any).properties
          || event
        const parentSessionID = childCheckData?.parentID
          || (event as any).properties?.parentID
          || (event as any).parentID
        if (parentSessionID) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `CHILD session created (parentID=${parentSessionID}) — primary-agent state PRESERVED`,
              extra: { parentID: String(parentSessionID) }
            }
          })
          return
        }

        // CRITICAL FIX: Reset module-level identity-lock state on every new
```
- Verify: `rg -n "CHILD session created" <plugin>` → 1.
- ⚠️ Имя `childCheckData` — НЕ `sessionData` (в том же блочном scope на L144 объявлен `const sessionData` → конфликт обявления = синтаксическая/семантическая ошибка).
- Эмпирическая проверка допущения: оп. 4.4 (лог «CHILD session created» должен появиться при первой делегации). **Если не появился** — поле `parentID` в этом payload отсутствует; см. «Риски» → R3 (fail-open: поведение = статус-кво, регрессии нет).

### Operation 1.12: Константа SELF_WORK_MARKERS (Рек. 3)
- File: plugin
- Line: вставка после 100 (закрывающая `}` объекта `FORBIDDEN_VOCAB`)
- Old (якорь):
```typescript
  plankestrator: [
    "I am orchestrator", "I'm orchestrator", "I am the Conductor",
    "I am the Task classifier", "Task classifier and router",
    "bugfix-triage", "execute-bug", "devops-agent", "consistency-checker"
  ]
}
```
- New:
```typescript
  plankestrator: [
    "I am orchestrator", "I'm orchestrator", "I am the Conductor",
    "I am the Task classifier", "Task classifier and router",
    "bugfix-triage", "execute-bug", "devops-agent", "consistency-checker"
  ]
}

// ============================================================
// Self-work markers (v4) — маркеры САМОСТОЯТЕЛЬНОЙ plan/research-работы
// в сообщении locked primary-агента (исследование: Пробел 3, Рек. 3).
// Намеренно НЕ смешиваются с FORBIDDEN_VOCAB: тот логируется как
// "contains {otherAgent} terminology" (стр. 420) — семантика другая.
// Заголовочные токены ("## ...") снижают false-positive: обычные слова
// ("research", "findings") встречались бы в легальной маршрутной прозе
// и именах файлов ("RESEARCH.md"). Русские маркеры добавлены сверх
// списка исследования: модель отвечает пользователю по-русски.
// ============================================================
const SELF_WORK_MARKERS: Record<string, string[]> = {
  plankestrator: [
    "## Findings", "## Research", "Executive Summary", "## Analysis",
    "### Root Cause", "## Recommendations", "## Overview",
    "## Выводы", "## Результаты исследования"
  ]
}
```
- Verify: `rg -nF "SELF_WORK_MARKERS" <plugin>` → 3 (объявление + 2 использования в оп. 1.7 и 1.5-комментариях нет — ровно: объявление, `SELF_WORK_MARKERS[lockedAgentName]` ×2 в оп. 1.7).
- Обоснование отдельной константы (а не расширение `FORBIDDEN_VOCAB` буквально по Рек. 3): лог-сообщение существующей проверки (L420) говорит «contains {otherAgent} terminology» — смешение исказило бы диагностику; поведение идентично, структура чище.

### Operation 1.13: Константа INSPECTION_BUDGET + переменные состояния
- File: plugin
- Line: после 82 (`let currentMode ...`)
- Old:
```typescript
let workflowSteps: Array<{timestamp: number, tool: string, agent: string, target?: string}> = []
let currentMode: "plan" | "build" = "build"
```
- New:
```typescript
let workflowSteps: Array<{timestamp: number, tool: string, agent: string, target?: string}> = []
let currentMode: "plan" | "build" = "build"

// ============================================================
// v4 — состояние предотвращения self-work plankestrator
// (сбрасывается на session.created ВЕРХНЕГО уровня; дочерние сессии
// не сбрасывают — см. parentID-guard)
// ============================================================
// Максимум read+grep+glob за сессию, ВСЕ — до первого pipeline Task-вызова.
// Промпт требует от модели max 2 (plankestrator.md) — плагин оставляет
// 1 вызов запаса: промпт строже закона, закон ловит эскалацию.
const INSPECTION_BUDGET = 3
// Маркер self-work-контента в последнем assistant-сообщении родителя
let selfWorkDetected: boolean = false
// >0 пока выполняется Task-субагент — enforcement приостановлен (атрибуция)
let activeTaskDepth = 0
```
- Verify: `rg -n "INSPECTION_BUDGET = 3" <plugin>` → 1; `rg -c "activeTaskDepth" <plugin>` → ≥ 9.

### Проверка целостности Фазы 1 (после всех 13 операций)
- `rg -c "v4" <plugin>` → ≥ 8 (маркеры новых блоков).
- Баланс скобок/синтаксис: оп. 4.2 (tsc) — **обязательно до перезапуска opencode**.
- Логическая проверка порядка: depth-guard (оп. 1.6) находится ВЫШЕ по коду, чем Gate A (L467) и INSPECTION GATE (оп. 1.5) — иначе субагентские вызовы попадут в гейты.

---

## Phase 2: Промпт — `agents\plankestrator.md`

**Порядок выполнения: 2.1 → 2.10 (строго снизу вверх).** Может идти **параллельно Фазе 1** (другой файл). Все строки — исходные (118 строк).

### Operation 2.1: PROHIBITIONS — два новых запрета (Рек. 5)
- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: после 115
- Old:
```markdown
- 🚫 No pipeline changes after Turn 1. No re-classification mid-pipeline.
```
- New:
```markdown
- 🚫 No pipeline changes after Turn 1. No re-classification mid-pipeline.
- 🚫 No read/glob/grep during pipeline execution (Turns 2..N). After your first pipeline Task call, ANY inspection is HARD-BLOCKED by the plugin (⛔ INSPECTION AFTER PIPELINE START).
- 🚫 Max 2 inspection calls TOTAL, Turn 1 only — and only when the request text is genuinely insufficient to classify (for RESEARCH/PLAN it almost never is). Plugin hard limit: 3 — the 4th call throws ⛔ INSPECTION BUDGET EXHAUSTED.
```
- Verify: `rg -nF "INSPECTION AFTER PIPELINE START" <plankestrator.md>` → 1; `rg -nF "Max 2 inspection calls" <plankestrator.md>` → 1.
- Это точный аналог правил orchestrator.md стр. 124 (Turns 2..N) и стр. 114 (числовой лимит) — устраняет асимметрию из сравнительной таблицы исследования (стр. 165–166).

### Operation 2.2: PROHIBITIONS — усиление запрета self-work маркерами
- File: plankestrator.md
- Line: 112
- Old:
```markdown
- 🚫 No plan content or research findings in YOUR OWN message text — not even partial, not even a summary presented as "the plan is...".
```
- New:
```markdown
- 🚫 No plan content or research findings in YOUR OWN message text — not even partial, not even a summary presented as "the plan is...". Research/plan headings in your message ("## Findings", "## Analysis", "## Research", "Executive Summary", "## Recommendations") are DETECTED BY THE PLUGIN and hard-block all further inspection.
```
- Verify: `rg -nF "DETECTED BY THE PLUGIN" <plankestrator.md>` → 1.

### Operation 2.3: Секция EXAMPLES — few-shot (Рек. 7)
- File: plankestrator.md
- Line: вставка перед 109 (`## PROHIBITIONS — VIOLATION = FAILURE`), после 107
- Old (якорь):
```markdown
## PROHIBITIONS — VIOLATION = FAILURE
```
- New:
````markdown
## EXAMPLES — WHAT A CORRECT TURN LOOKS LIKE

**User request:** «Исследуй, почему сборка медленная, и сравни трёх CI-провайдеров.»

Классификация ИЗ ТЕКСТА запроса: RESEARCH («исследуй», «сравни»); COMPLEX (2 темы + сравнительный анализ 3 объектов). Файлы читать НЕ НУЖНО.

✅ CORRECT Turn 1 — classify and delegate immediately:

```
✓ IDENTITY VERIFIED: I am plankestrator. I am NOT orchestrator. My role: planning and research routing. My permissions: edit=deny, write=deny, bash=deny. Proceeding.
```

```json
{
  "agent": "plankestrator",
  "state": "CLASSIFY",
  "type": "RESEARCH",
  "complexity": "COMPLEX",
  "goal": "Investigate slow build and compare 3 CI providers",
  "next_agent": "research-writer-complex",
  "pipeline": ["research-writer-complex", "research-reviewer"]
}
```

Task call: `subagent_type = "research-writer-complex"`, prompt = original request verbatim + "Write the research to RESEARCH.md".

```
→ DELEGATED to research-writer-complex for: investigate slow build + compare 3 CI providers
```

❌ WRONG Turn 1 — self-work (VIOLATION):

```
✓ IDENTITY VERIFIED: ...
Let me investigate. [read package.json] [read build config]
## Findings
The build is slow because of ...   ← CONTENT WRITTEN BY YOU = SELF-WORK
```

Коррекция: НИКАКОЙ инспекции «чтобы ответить», НИКАКИХ findings/analysis в твоём тексте. Правильный ход: identity line → JSON → ОДИН Task call → ack line. Содержание исследования — работа research-writer-complex; оценка — работа research-reviewer. Твоя работа — ТОЛЬКО маршрутизация.

## PROHIBITIONS — VIOLATION = FAILURE
````
- Verify: `rg -n "^## EXAMPLES" <plankestrator.md>` → 1; `rg -nF "→ DELEGATED to research-writer-complex" <plankestrator.md>` → 1; `rg -nF "CONTENT WRITTEN BY YOU" <plankestrator.md>` → 1.
- Примечание: внешние блоки примеров используют ```` (4 backtick) обёртку НЕ требуется — внутри примеров только ```-блоки с пустой строкой-разделителем; при вставке проверить, что markdown-рендер не ломает вложенность (в opencode промпт consumed as raw text — безопасно). Пример намеренно демонстрирует COMPLEX-классификацию из текста (закрепляет оп. 2.4) и ack-строку (оп. 2.6–2.7).

### Operation 2.4: complexity из текста запроса (Рек. 6 + Best Practice 7)
- File: plankestrator.md
- Line: 105–107
- Old:
```markdown
**complexity:**
- SIMPLE: 1 file / 1 source, no architectural decisions, straightforward answer.
- COMPLEX: 2+ files / 2+ sources, architectural decisions, external integrations, comparative analysis, non-obvious approach.
```
- New:
```markdown
**complexity — determined from the REQUEST TEXT ONLY. NEVER inspect files to "count" complexity:**
- SIMPLE: one question / one topic / one object; no comparative analysis; no architectural decisions; a straightforward answer is expected.
- COMPLEX: 2+ distinct questions or topics; 2+ objects to compare; comparative analysis requested; architectural decisions; external integrations; non-obvious approach; the request spans multiple subsystems or a whole codebase.
- RESEARCH+PLAN: ALWAYS COMPLEX (two work products, 4-stage pipeline) — use table row 6. Row 5 remains only as a defensive fallback and must not be chosen deliberately.
```
- Verify: `rg -nF "REQUEST TEXT ONLY" <plankestrator.md>` → 1; `rg -nF "1 file / 1 source" <plankestrator.md>` → **0** (старый текст удалён); `rg -nF "ALWAYS COMPLEX" <plankestrator.md>` → 1.
- Решение: строка 5 таблицы пайплайнов (RESEARCH+PLAN SIMPLE) СОХРАНЕНА — таблица должна оставаться идентичной секции ARCHITECTURE.md (стр. 245: «Each table must stay identical»), а MCP_SETUP.md L755 дублирует её. Правило «ALWAYS COMPLEX» делает строку 5 недостижимой на уровне классификации, не ломая синхронизацию таблиц. Полное удаление строки 5 — отдельная задача с синхронизацией 3 файлов (не входит).

### Operation 2.5: Сужение COMPLETE-хода (Рек. 9)
- File: plankestrator.md
- Line: 77
- Old:
```markdown
3. One short user-facing summary: which agents ran, what they produced, where the output file lives. Do NOT call Task again.
```
- New:
```markdown
3. One short user-facing summary (MAX 3 lines): which agents ran + output file path(s). Content recap is FORBIDDEN — the plan/research content lives in the file, never in your message. Do NOT call Task again.
```
- Verify: `rg -nF "Content recap is FORBIDDEN" <plankestrator.md>` → 1; `rg -nF "what they produced" <plankestrator.md>` → 0.
- Устраняет паттерн «Summary-эскалация» (исследование стр. 60–61, 105).

### Operation 2.6: Ack-строка в Turns 2..N (Рек. 8)
- File: plankestrator.md
- Line: 69–70
- Old:
```markdown
3. Call Task with `subagent_type = next_agent`. Pass the previous agent's output verbatim as context.
4. STOP and wait.
```
- New:
```markdown
3. Call Task with `subagent_type = next_agent`. Pass the previous agent's output verbatim as context.
4. One ack line: `→ DELEGATED to <agent> for: <goal>`. STOP and wait.
```
- Verify: `rg -c "One ack line" <plankestrator.md>` → 2 (после оп. 2.7).

### Operation 2.7: Ack-строка в Turn 1 (Рек. 8)
- File: plankestrator.md
- Line: 61–62
- Old:
```markdown
5. Call Task with `subagent_type = next_agent` (= pipeline[0]). Pass the user's ORIGINAL request verbatim, plus file instructions: plan-writer-* → "Write the plan to PLAN.md"; research-writer-* → "Write the research to RESEARCH.md".
6. STOP and wait.
```
- New:
```markdown
5. Call Task with `subagent_type = next_agent` (= pipeline[0]). Pass the user's ORIGINAL request verbatim, plus file instructions: plan-writer-* → "Write the plan to PLAN.md"; research-writer-* → "Write the research to RESEARCH.md".
6. One ack line: `→ DELEGATED to <agent> for: <goal>`. STOP and wait.
```
- Verify: `rg -nF "→ DELEGATED to <agent> for: <goal>" <plankestrator.md>` → 2 (Turn 1 + Turns 2..N); аналог orchestrator.md стр. 70 присутствует — асимметрия устранена.
- ⚠️ Якоря «6. STOP and wait.» (L62) и «4. STOP and wait.» (L70) различаются номерами — править КАЖДЫЙ со своей предыдущей строкой (5. / 3. соответственно) для уникальности.

### Operation 2.8: Turn 1 step 2 — количественная граница инспекции (Рек. 5, Best Practice 4)
- File: plankestrator.md
- Line: 58
- Old:
```markdown
2. (Optional) Inspect to classify ONLY: `read`/`glob`/`grep` to determine type and complexity. The moment you can fill the JSON — STOP inspecting. You may NOT inspect to answer the user's question itself — that is the writer agents' job.
```
- New:
```markdown
2. (Optional) Inspect to classify ONLY — MAX 2 `read`/`glob`/`grep` calls TOTAL, Turn 1 only, and only when the request TEXT is insufficient to classify (for RESEARCH/PLAN it almost never is: type comes from keywords, complexity — from the number of questions/topics/objects in the request). The moment you can fill the JSON — STOP inspecting. You may NOT inspect to answer the user's question itself — that is the writer agents' job. The plugin HARD-BLOCKS: any inspection after your first pipeline Task call, any inspection beyond the budget, and any inspection after self-work content was detected in your message.
```
- Verify: `rg -nF "MAX 2" <plankestrator.md>` → 1 (строка 58 области); `rg -nF "HARD-BLOCKS" <plankestrator.md>` → ≥ 2 (L58 + PROHIBITIONS).
- Заменяет субъективный self-assessment («the moment you can fill the JSON») на проверяемую числовую границу (исследование стр. 54–55, 186).

### Operation 2.9: Позитивная рамка роли (Рек. 10)
- File: plankestrator.md
- Line: 19
- Old:
```markdown
You are the Plankestrator. You classify the user's request, pick ONE pipeline from the table below, and walk it step by step via the Task tool. You NEVER write plans or research yourself — that is what the writer agents are for.
```
- New:
```markdown
You are the Plankestrator — a ROUTER, not a writer and not a researcher. You classify the user's request, pick ONE pipeline from the table below, and walk it step by step via the Task tool. Your ONLY outputs are: (1) the identity line, (2) the JSON block, (3) at most ONE Task call per turn, (4) the ack line. Nothing else — no analysis, no findings, no plan/research content in your message text. You NEVER write plans or research yourself — that is what the writer agents are for.
```
- Verify: `rg -nF "Your ONLY outputs are" <plankestrator.md>` → 1.
- Позитивное перечисление разрешённых артефактов вместо чистого запрета (Best Practice 3, исследование стр. 184); закрывает интерпретацию «текст ≠ writing» (стр. 76, 106).

### Operation 2.10: Frontmatter description (Рек. 12)
- File: plankestrator.md
- Line: 2
- Old:
```markdown
description: Plankestrator. Planning and research state machine. Determines task type, complexity, and routes to specialist agents. Handles PLAN, RESEARCH, RESEARCH+PLAN. Implementation tasks are out of scope. NEVER edits files or runs commands.
```
- New:
```markdown
description: Plankestrator. Routes planning and research tasks to writer agents. Determines task type, complexity, and pipeline, then delegates via Task. Handles PLAN, RESEARCH, RESEARCH+PLAN. Implementation tasks are out of scope. NEVER edits files, NEVER runs commands, NEVER investigates or answers directly.
```
- Verify: `rg -nF "Routes planning and research tasks to writer agents" <plankestrator.md>` → 1; `rg -nF "NEVER investigates or answers directly" <plankestrator.md>` → 1.
- ⚠️ Ограничения (не нарушать): слово «Plankestrator» ОБЯЗАТЕЛЬНО сохраняется в description — fallback-детекторы `detectAgentFromSessionData` (Methods 4–5, plugin L783–794) ищут его в title/description; слово «orchestrator» НЕ должно появляться (Method 5: `desc.includes("orchestrator")` → ложная идентификация). Новый текст оба условия соблюдает. Убирает ролевую путаницу «research state machine → я исследователь» (исследование стр. 82).

---

## Phase 3: Синхронизация документации (после Фаз 1+2)

> consistency-checker валидирует конфигурацию против ARCHITECTURE.md — рассинхрон = ложные нарушения в пайплайнах BUGFIX DEEP / DEV.

### Operation 3.1: ARCHITECTURE.md — Defense in depth: 3 → 4 слоя
- File: `P:\Programming\Рефакторинг\ARCHITECTURE.md`
- Line: 186–190
- Old:
```markdown
**Defense in depth — this lock is enforced by 3 layers:**

1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
2. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
3. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
```
- New:
```markdown
**Defense in depth — this lock is enforced by 4 layers:**

1. **Merged permission ruleset** (opencode.json deep-merged with `agents/*.md` frontmatter) — the runtime refuses to inject denied tools into the agent's toolset
2. **Plugin runtime gate** (`workflow-enforcement.ts` → `PRIMARY_AGENT_ALLOWED_TOOLS`) — throws `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception if anything bypasses the config
3. **Identity-lock v3** — if the agent outputs wrong identity in JSON, the locked routing table is still enforced
4. **Inspection gate v4 (plankestrator)** — plugin hard-blocks `read`/`grep`/`glob`: (a) after the first pipeline Task call (`⛔ INSPECTION AFTER PIPELINE START`), (b) beyond the inspection budget of 3 calls per session (`⛔ INSPECTION BUDGET EXHAUSTED`; the prompt tells the model max 2), (c) after self-work content markers (`## Findings`, `## Analysis`, `Executive Summary`, ...) were detected in plankestrator's own message. view-image and identity-probe Task calls are auxiliary — they do NOT count as pipeline start. Child (subagent) sessions do not reset the parent's lock (parentID guard); subagent tool calls are excluded from enforcement via `activeTaskDepth`.
```
- Verify: `rg -nF "enforced by 4 layers" ARCHITECTURE.md` → 1; `rg -nF "Inspection gate v4" ARCHITECTURE.md` → 1.

### Operation 3.2: ARCHITECTURE.md — Plankestrator Delegation Rule: лимиты инспекции
- File: ARCHITECTURE.md
- Line: после 224 (конец блока «File output handling»)
- Old (якорь):
```markdown
- plankestrator NEVER writes files directly
```
- New:
```markdown
- plankestrator NEVER writes files directly

**Inspection limits (v4):** plankestrator may call `read`/`grep`/`glob` ONLY on Turn 1 and ONLY to classify (prompt limit: max 2 calls; plugin hard limit: `INSPECTION_BUDGET = 3`). After the first pipeline Task call, any inspection throws. Type and complexity are classified from the REQUEST TEXT (keywords; number of questions/topics/objects), not from files. RESEARCH+PLAN is always COMPLEX. Context-heavy investigation is delegated to `devops-readonly` via Task. Plan/research CONTENT in plankestrator's own message (headings like `## Findings`, `## Analysis`) is detected by the plugin and blocks further inspection.
```
- Verify: `rg -nF "Inspection limits (v4)" ARCHITECTURE.md` → 1.

### Operation 3.3: ARCHITECTURE.md — §9 Plugin Hooks: назначение хуков
- File: ARCHITECTURE.md
- Line: 620, 622, 625
- Old:
```markdown
| `tool.execute.before` | Before any tool call | Routing table enforcement — blocks invalid agent calls |
```
- New:
```markdown
| `tool.execute.before` | Before any tool call | Routing table enforcement; JSON-before-Task gate (no grace for locked agents, v4); inspection budget & post-pipeline inspection ban for plankestrator (v4); suppressed while a Task subagent runs (`activeTaskDepth > 0`, v4) |
```
- Old (L622):
```markdown
| `session.created` | New session starts | Detects which agent is running |
```
- New:
```markdown
| `session.created` | New session starts | Detects which agent is running; CHILD (subagent) sessions preserve the parent's identity-lock state (parentID guard, v4) |
```
- Old (L625):
```markdown
| `message.updated` | Message added | Validates JSON output format |
```
- New:
```markdown
| `message.updated` | Message added | Validates JSON output format (INVALID JSON logged as error, v4); detects forbidden vocabulary and self-work content markers (v4); skipped while a Task subagent runs |
```
- Verify: `rg -nF "activeTaskDepth" ARCHITECTURE.md` → ≥ 2; `rg -nF "parentID guard" ARCHITECTURE.md` → ≥ 1.

### Operation 3.4: AGENTS.md — планкестратор-секция: лимиты инспекции
- File: `P:\Programming\Рефакторинг\AGENTS.md`
- Line: после 201 (абзац «plankestrator is a router, not a writer.»)
- Old (якорь — конец абзаца L201):
```markdown
It NEVER writes the plan or research content itself — that is `plan-writer-*` / `research-writer-*` work, delegated through the pipeline.
```
- New:
```markdown
It NEVER writes the plan or research content itself — that is `plan-writer-*` / `research-writer-*` work, delegated through the pipeline.

**Inspection limits (v4):** plankestrator may use `read`/`grep`/`glob` ONLY on Turn 1 to classify (prompt: max 2 calls; plugin hard limit: 3). After the first pipeline Task call any inspection throws ⛔. Complexity is classified from the request text, not from files; RESEARCH+PLAN is always COMPLEX. Self-work content markers (`## Findings`, `## Analysis`, `Executive Summary`, ...) in plankestrator's own message are detected by the plugin and block further inspection.
```
- Verify: `rg -nF "Inspection limits (v4)" AGENTS.md` → 1.

### Operation 3.5: AGENTS.md — Workflow Enforcement Plugin → Functionality
- File: AGENTS.md
- Line: 416–422 (список Functionality)
- Old:
```markdown
- Enforces routing tables via pre-call hooks
- Validates JSON output format includes required fields
- Detects and prevents identity drift
- Ensures agents stay within their whitelisted agent set
```
- New:
```markdown
- Enforces routing tables via pre-call hooks
- Validates JSON output format includes required fields
- Detects and prevents identity drift
- Ensures agents stay within their whitelisted agent set
- Inspection budget & post-pipeline inspection ban for plankestrator (v4)
- Self-work content marker detection in primary-agent messages (v4)
- Parent/child session attribution: subagent sessions preserve the parent's identity lock; enforcement suppressed while a Task subagent runs (v4)
```
- Verify: `rg -nF "Inspection budget & post-pipeline" AGENTS.md` → 1.

### Operation 3.6: PLUGIN.md — секции 3, 5, 6, 10, 11
- File: `P:\Programming\Рефакторинг\PLUGIN.md`
- Line: секция `## 3. Lifecycle Hooks` (L67+), `## 5. Error Messages` (L242+), `## 6. JSON Validation` (L314+), `## 10. Known Issues` (L761+), `## 11. Configuration Reference` (L820+)
- Old/New (содержательно, якоря уточнить по месту при выполнении):
  - §3: добавить описание depth-guard (`activeTaskDepth`), parentID-guard в `session.created`, INSPECTION GATE в `tool.execute.before`, self-work check в `message.updated`.
  - §5: добавить три новых сообщения об ошибках дословно из оп. 1.5/1.7: `⛔ INSPECTION AFTER PIPELINE START — DELEGATE INSTEAD`, `⛔ INSPECTION BUDGET EXHAUSTED — CLASSIFY AND DELEGATE NOW`, `⛔ SELF-WORK CONTENT DETECTED IN YOUR PREVIOUS MESSAGE` (условия срабатывания + что делает модель для коррекции).
  - §6: отразить warn→error для `INVALID JSON OUTPUT` и снятие `isFirstTaskCall`-grace для locked-агентов (exception: auxiliary targets — identity probes, view-image).
  - §10: закрыть/обновить known issue «нет бюджета инспекции» (если присутствует); добавить known issue «параллельный второй Task-вызов в одном ходе не проверяется routing-таблицей (depth>0), только warn-лог».
  - §11: добавить `INSPECTION_BUDGET = 3`, `SELF_WORK_MARKERS`, `activeTaskDepth`.
- Verify: `rg -nF "INSPECTION BUDGET EXHAUSTED" PLUGIN.md` → ≥ 1; `rg -nF "INSPECTION_BUDGET" PLUGIN.md` → ≥ 1; `rg -nF "activeTaskDepth" PLUGIN.md` → ≥ 1.

### Operation 3.7: CHANGELOG.md — запись
- File: `P:\Programming\Рефакторинг\CHANGELOG.md`
- Line: верх файла (по существующей конвенции — уточнить формат последней записи перед вставкой)
- New (содержательно): запись «v4 — plankestrator self-work prevention»: inspection budget (3/session), post-pipeline inspection ban, self-work markers, JSON-gate tightening (locked agents), parentID/activeTaskDepth session attribution, prompt: ack-line, few-shot EXAMPLES, text-based complexity, MAX-2 inspection, narrowed COMPLETE, positive role frame, new description. Ссылка на `RESEARCH_PLANKESTRATOR_ISSUE.md` и `PLANKESTRATOR_FIX_PLAN.md`.
- Verify: `rg -nF "self-work prevention" CHANGELOG.md` → 1.

### Operation 3.8 (осознанное решение): копии в `deploy-package\` и `opencode-config\` НЕ трогаем
- Это deployment-снапшоты на определённую дату (как `backup\2026-09-07_remediation_v2\`). Синхронизация снапшотов не требуется; при следующем формировании deploy-пакета копии будут пересобраны из живых конфигов. Зафиксировать это решение в записи CHANGELOG (оп. 3.7), чтобы consistency-checker не трактовал расхождение как нарушение.

---

## Phase 4: Верификация

### Operation 4.1: Статические grep-проверки (сводная таблица)
- File: все изменённые
- Line: —
- Old/New: — (только проверки)
- Verify (ожидаемые результаты):
```powershell
$pl = "C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts"
$pk = "C:\Users\Admin\.config\opencode\agents\plankestrator.md"
rg -c "activeTaskDepth" $pl          # ≥ 9
rg -c "INSPECTION_BUDGET" $pl        # ≥ 5
rg -c "SELF_WORK_MARKERS" $pl        # = 3
rg -n "CHILD session created" $pl    # 1
rg -n "AUXILIARY_TASK_TARGETS" $pl   # 2 (объявление + использование)
rg -nF 'level: "error",' $pl         # ≥ 4 (было 3: drift, vocab, Gate A + INVALID JSON)
rg -c "DELEGATED to" $pk             # ≥ 3 (Turn1, Turns2..N, EXAMPLES)
rg -nF "1 file / 1 source" $pk       # 0 (старые критерии удалены)
rg -n "^## EXAMPLES" $pk             # 1
rg -nF "Max 2 inspection calls" $pk  # 1
rg -nF "enforced by 4 layers" "P:\Programming\Рефакторинг\ARCHITECTURE.md"  # 1
rg -nF "Inspection limits (v4)" "P:\Programming\Рефакторинг\AGENTS.md"      # 1
```
- Кросс-консистентность промпт↔плагин: `rg -n "MAX 2" $pk` (промпт) при `INSPECTION_BUDGET = 3` (плагин) — расхождение НАМЕРЕННОЕ (промпт строже), задокументировано в оп. 1.13 и 3.1.
- Регресс orchestrator: `rg -nF "No read/glob/grep during pipeline execution (Turns 2..N)" "C:\Users\Admin\.config\opencode\agents\orchestrator.md"` → 1 (файл НЕ изменялся в Фазах 1–4).

### Operation 4.2: Синтаксическая проверка plugin (ДО перезапуска opencode)
- File: plugin
- Verify:
```powershell
npx tsc --noEmit --skipLibCheck --target es2022 --module esnext --moduleResolution bundler "C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts"
```
- Критерий успеха: НЕТ ошибок класса TS1xxx (синтаксис) и TS2xxx, КРОМЕ допустимой `TS2307: Cannot find module '@opencode-ai/plugin'` (типы хоста недоступны вне opencode). Любая иная ошибка → откат файла из бэкапа, повтор Фазы 1.

### Operation 4.3: Перезапуск opencode + инициализация plugin
- Verify: после перезапуска в свежем логе (`Get-ChildItem ~\.local\share\opencode\log\*.log | Sort-Object LastWriteTime | Select-Object -Last 1`) присутствует `Workflow enforcement plugin initialized` и ОТСУТСТВУЮТ syntax/parse-ошибки загрузки плагина. Если plugin не загрузился — ВСЕ гейты молча отсутствуют: немедленный откат `workflow-enforcement.ts` из бэкапа.

### Operation 4.4: Смоук — реальный RESEARCH-пайплайн + эмпирическая проверка parentID
- Verify: новая сессия «plankestrator — test research routing», запрос: «Исследуй и сравни 2 подхода к X» (RESEARCH COMPLEX). Ожидание:
  1. identity line → JSON (`type: "RESEARCH"`, `complexity: "COMPLEX"`) → Task(`research-writer-complex`) → ack-строка; НИ ОДНОГО read/grep/glob;
  2. в логах: `Inspection allowed` НЕ появляется; `CHILD session created (parentID=...)` — ПОЯВЛЯЕТСЯ при старте writer-агента (подтверждение допущения оп. 1.11);
  3. пайплайн доходит до COMPLETE: writer и reviewer отработали, `edit`-вызовы writer'а НЕ заблокированы Gate A (подтверждение корректности depth-guard);
  4. `INVALID JSON OUTPUT`, `IDENTITY DRIFT`, `⛔` — отсутствуют.
- Если (2) НЕ появилось → parentID отсутствует в payload → см. R3: enforcement после первой делегации остаётся в статус-кво (fail-open), зафиксировать в PLUGIN.md §10, запланировать альтернативу (детект child по title/absence agent field).
- Если (3) нарушено (writer заблокирован) → **НЕМЕДЛЕННЫЙ ОТКАТ Фазы 1** (ошибка depth-guard — критический сценарий).

### Operation 4.5: Негативный тест — инспекция в середине пайплайна
- Verify: в сессии plankestrator после первого Task-вызова попросить (следующим сообщением пользователя): «Прочитай файл X и покажи содержимое». Ожидание: throw `⛔ INSPECTION AFTER PIPELINE START — DELEGATE INSTEAD` в ответе read-вызова + error-лог `INSPECTION AFTER PIPELINE START BLOCKED`. Модель после throw должна продолжить пайплайн (delegate), а не читать.

### Operation 4.6: Регресс — view-image ДО классификации не блокируется
- Verify: сессия plankestrator с запросом, содержащим изображение, значимое для классификации. Ожидание: Task(view-image) отдельным ходом проходит (auxiliary: не требует JSON — оп. 1.4; не считается стартом пайплайна — оп. 1.5); последующий ход — классификация JSON + Task(writer). В логах нет `INSPECTION AFTER PIPELINE START` после view-image.

### Operation 4.7: Регресс — orchestrator не затронут
- Verify: сессия «orchestrator — ...» с DEV SIMPLE задачей. Ожидание: поведение прежнее (routing, JSON-gate с isFirstTaskCall-grace для первого вызова... ВАЖНО: grace снят и для locked orchestrator тоже — оп. 1.4 применима к обоим primary-агентам; orchestrator.md ТРЕБУЕТ JSON каждый ход (L80), поэтому ужесточение корректно и для него); read/glob/grep orchestrator НЕ ограничены бюджетом (INSPECTION GATE — только plankestrator, условие `lockedAgentName === "plankestrator"`).
- Отдельно: orchestrator-сессия с планом (plan_exists) — первый Task(worker) проходит при выданном валидном JSON; если модель вызвала Task БЕЗ JSON → throw (это и есть целевое усиление, не регресс).

---

## Phase 5 (УСЛОВНАЯ): Структурное удаление read/grep/glob (Рек. 11)

**Условие запуска:** после Фаз 1–4 в ≥5 реальных plankestrator-сессиях зафиксировано ≥2 нарушения (throw'ы `INSPECTION *` / `SELF-WORK *` в логах ИЛИ визуальный self-work в ответах). Если нарушения единичны и гасятся retry — Фаза 5 НЕ выполняется (сохраняется удобство быстрой инспекции). Решение принимает пользователь.

### Operation 5.1: plankestrator.md frontmatter — deny
- File: `C:\Users\Admin\.config\opencode\agents\plankestrator.md`
- Line: 9–11
- Old:
```yaml
  read: allow
  grep: allow
  glob: allow
```
- New:
```yaml
  read: deny
  grep: deny
  glob: deny
```
- Verify: `rg -n "read: deny" <plankestrator.md>` → 1 (внутри frontmatter, строки 1–17).

### Operation 5.2: opencode.json — deny (⚠️ КРИТИЧЕСКАЯ ТОЧКА)
- File: `C:\Users\Admin\.config\opencode\opencode.json`
- Line: 1405–1407 — СТРОГО внутри блока `"plankestrator"` (начало блока L1398)
- Old:
```json
        "read": "allow",
        "grep": "allow",
        "glob": "allow",
```
- New:
```json
        "read": "deny",
        "grep": "deny",
        "glob": "deny",
```
- Verify: ОБЯЗАТЕЛЬНА валидация JSON сразу после правки:
```powershell
node -e "JSON.parse(require('fs').readFileSync('C:/Users/Admin/.config/opencode/opencode.json','utf8')); console.log('JSON OK')"
rg -n -A12 '"plankestrator": \{' "C:\Users\Admin\.config\opencode\opencode.json" | rg "read|grep|glob"   # только "deny"
```
- ⚠️ Трио `"read": "allow", "grep": "allow", "glob": "allow"` встречается в файле МНОГОКРАТНО (orchestrator и другие агенты) — править ТОЛЬКО по номерам строк внутри блока plankestrator (1398–1428) или с якорем `"plankestrator": {` + весь permission-блок целиком. Случайная правка orchestrator-блока = катастрофа.

### Operation 5.3: Plugin Gate A — per-agent allowed tools
- File: plugin
- Line: 467 (объявление) + 468–472 (условие) + 492–498 (текст throw)
- Old:
```typescript
      const PRIMARY_AGENT_ALLOWED_TOOLS = new Set(["task", "read", "glob", "grep"])
      if (
        identityLocked &&
        (lockedAgentName === "orchestrator" || lockedAgentName === "plankestrator") &&
        !PRIMARY_AGENT_ALLOWED_TOOLS.has(input.tool)
      ) {
```
- New:
```typescript
      const PRIMARY_AGENT_ALLOWED_TOOLS: Record<string, Set<string>> = {
        orchestrator: new Set(["task", "read", "glob", "grep"]),
        plankestrator: new Set(["task"]) // v5: классификация из текста запроса; контекст — через devops-readonly
      }
      if (
        identityLocked &&
        (lockedAgentName === "orchestrator" || lockedAgentName === "plankestrator") &&
        !PRIMARY_AGENT_ALLOWED_TOOLS[lockedAgentName].has(input.tool)
      ) {
```
  В тексте throw (L494–498) список «Allowed» для plankestrator не должен рекламировать read/glob/grep — сделать сообщение по `lockedAgentName`: для plankestrator — «Allowed: task ONLY; need context → delegate to devops-readonly».
- Verify: `rg -n "plankestrator: new Set" <plugin>` → 1; tsc (оп. 4.2) чист; INSPECTION GATE (оп. 1.5) остаётся как defense-in-depth (read всё равно deny на уровне permission + Gate A).

### Operation 5.4: Промпт — переписать инспекционные места
- File: plankestrator.md
- Line: 58 (после оп. 2.8), PROHIBITIONS (после оп. 2.1)
- Old: тексты оп. 2.8 / 2.1 (к тому моменту уже новые)
- New: step 2 Turn 1 → «(Removed) You have NO direct inspection tools. Type and complexity come from the REQUEST TEXT. If you genuinely cannot classify without file context, call Task(devops-readonly) as its own turn, then classify.»; PROHIBITIONS-пункты про «Max 2 / Turns 2..N» → «🚫 No read/glob/grep at all — you do not have these tools. Any context gathering is delegated to devops-readonly via Task.»
- Verify: `rg -nF "You have NO direct inspection tools" <plankestrator.md>` → 1; `rg -nF "Max 2 inspection calls" <plankestrator.md>` → 0.

### Operation 5.5: Синхронизация документации под Фазу 5
- Files/Line:
  - ARCHITECTURE.md L172–184 (таблица lockdown): строки `read`/`glob`/`grep` — колонка plankestrator ✅→❌, Reason: «Classified from request text; context via devops-readonly (v5)»; L166 note — дополнить; L175–177.
  - ARCHITECTURE.md оп. 3.1 слой 4 и оп. 3.2 блок — обновить формулировки (инспекции больше нет).
  - AGENTS.md L203–207 (таблица Tool allowance): для plankestrator Allowed = `task` only.
  - AGENTS.md оп. 3.4 блок — переписать.
  - PLUGIN.md §11 — состав `PRIMARY_AGENT_ALLOWED_TOOLS` per-agent.
  - MCP_SETUP.md — если содержит матрицу permissions plankestrator (L394+, L408+) — проверить и синхронизировать (`rg -n "plankestrator" MCP_SETUP.md`).
- Verify: `rg -nF "task (delegate), read, glob, grep" AGENTS.md` → в таблице primary-агентов запись скорректирована (orchestrator сохраняет inspection, plankestrator — нет); consistency-checker-прогон чист.

### Operation 5.6: Верификация Фазы 5
- Verify: повторить оп. 4.2, 4.3, 4.4 + новый тест: в plankestrator-сессии попросить «прочитай файл» → модель НЕ имеет read в toolset (permission deny) ИЛИ получает `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL`; пайплан RESEARCH работает end-to-end; devops-readonly делегирование для контекста работает.

---

## Порядок исполнения и параллельность

```
Phase 0 (бэкап) ──► Phase 1 (plugin, 1.1→1.13 последовательно) ──┐
                 └► Phase 2 (промпт, 2.1→2.10 последовательно) ──┼─► Phase 3 (docs,
                     (Phase 1 ∥ Phase 2 — разные файлы)          │   3.1→3.7 последовательно)
                                                                 └─► Phase 4 (верификация
                                                                      4.1→4.7 последовательно)
                                                                          │
                                              [триггер нарушений] ──► Phase 5 (условная)
```

- **Параллельно:** Phase 1 ∥ Phase 2 (разные файлы); внутри Phase 3 операции 3.1–3.5 независимы по файлам (ARCHITECTURE ∥ AGENTS ∥ PLUGIN ∥ CHANGELOG), но внутри одного файла — последовательно.
- **Последовательно (жёстко):** 0 → {1, 2} → 3 → 4 → (5). Операции внутри файла — строго в указанном порядке (снизу вверх).
- **Неразрывные пары:** (1.11 + 1.6 + 1.9 + 1.1/1.2/1.3) — атрибуция целиком; (1.13 + 1.5) — константы раньше использования не обязательны для компиляции (hoisting `const` в module scope определяется до runtime), но применяются вместе; (5.1 + 5.2 + 5.3 + 5.4) — Фаза 5 только целиком.

## Критические точки (где ошибка ломает конфигурацию)

| # | Точка | Последствие ошибки | Защита |
|---|---|---|---|
| C1 | Синтаксис plugin (любая из 13 операций Фазы 1) | Plugin не загружается → ВСЕ гейты (routing, Gate A, identity lock) молча исчезают у ОБОИХ primary-агентов | оп. 4.2 (tsc) до перезапуска; оп. 4.3 (init-лог); атомарность Фазы 1 |
| C2 | Оп. 1.11 без 1.6/1.9 (или наоборот) | Gate A заблокирует `edit` writer-агентов → все пайплайны PLAN/RESEARCH падают | неразрывная пара; оп. 4.4 п.3 (writer edit работает) |
| C3 | Оп. 1.5 вставлена ПОСЛЕ `workflowSteps.push` (L564) | Off-by-one бюджета: 3-й вызов блокируется вместо 4-го | якорь вставки — до комментария L513; оп. 4.1 |
| C4 | Оп. 1.7 без role-guard | Пользователь вставляет документ с «## Findings» → plankestrator лишается инспекции | `msgRole === "assistant"` guard в коде оп. 1.7 |
| C5 | Оп. 5.2 (JSON-трио не уникально) | Правка orchestrator-блока вместо plankestrator → orchestrator лишается инспекции | правка строго L1405–1407 + `node -e JSON.parse` сразу после |
| C6 | Оп. 2.10 (description) | Потеря слова «Plankestrator» или появление «orchestrator» → детектор сессий (Methods 4–5) ломается | ограничения в Verify оп. 2.10 |
| C7 | Исключение view-image (оп. 1.4, 1.5) | Легитимная pre-classification инспекция изображения блокируется | `AUXILIARY_TASK_TARGETS` / `AUXILIARY_TARGETS`; оп. 4.6 |
| C8 | Якоря «STOP and wait» (оп. 2.6/2.7) | Правка не в тот ход (L62 vs L70) | Old-блоки включают предыдущую строку с номером шага |

## Риски и откаты

### R1: Правка не применилась (якорь не найден / текст отличается)
- **Действие:** НЕ форсить, НЕ применять частично. Перечитать область (`read` с offset ±20 строк), найти реальный текст (`rg -n "<фрагмент якоря>"`), скорректировать Old дословно. Если расхождение системное (файл изменился относительно исследования) — пересчитать все номера строк фазы и пройти операции заново по свежим якорям.
- **Порог отката:** любая неустранимая нестыковка в Фазе 1 → `Copy-Item "$bk\workflow-enforcement.ts" "C:\Users\Admin\.config\opencode\plugins\"` → перезапуск opencode → разбор.

### R2: Plugin не загружается после перезапуска (C1)
- Симптом: в логе НЕТ «Workflow enforcement plugin initialized», либо есть parse-ошибка.
- **Действие:** немедленный откат `workflow-enforcement.ts` из бэкапа, перезапуск, затем бинарный поиск: применить операции Фазы 1 двумя пачками (1.13–1.7, затем 1.6–1.1) с tsc-проверкой после каждой.

### R3: parentID отсутствует в payload дочерних сессий
- Симптом: лог «CHILD session created» не появляется при делегировании (оп. 4.4 п.2).
- Последствие: fail-open — состояние родителя стирается как сегодня (статус-кво): post-pipeline ban и self-work escalation работают только ДО первой делегации; бюджет Turn 1 работает всегда. **Регрессии нет** — усиление частично не действует.
- **Действие:** зафиксировать в PLUGIN.md §10; альтернативный детект child-сессии (title «task ...», отсутствие agent-поля + наличие parent-ссылки в ином поле) — отдельная мини-задача по dump-логу `session.created` (DEBUG-DUMP блок L163–187 уже выводит ключи payload — использовать его вывод для поиска реального имени поля).

### R4: Depth-guard не сбалансирован (activeTaskDepth «залип» > 0)
- Симптом: enforcement молча не срабатывает ни на что (все вызовы пропускаются), в логах нет `Valid routing`/гейт-сообщений при явных нарушениях.
- Причина-кандидат: `tool.execute.after` не fires для task при определённых ошибках.
- **Действие:** диагностика — `rg "activeTaskDepth|TASK CALL WHILE SUBAGENT" <свежий лог>`; аварийный сброс уже встроен: `activeTaskDepth = 0` на каждой новой session.created ВЕРХНЕГО уровня (оп. 1.10). Страховка (опционально, если залипание подтвердится): timestamp последнего инкремента + auto-reset depth при `Date.now() - lastTaskStart > 30 мин`.

### R5: Ложные срабатывания self-work маркеров
- Симптом: `SELF-WORK CONTENT DETECTED` в логе на легитимном сообщении (например, OUT OF SCOPE или COMPLETE-summary).
- **Действие:** исключить конкретный маркер из `SELF_WORK_MARKERS` (одна строка), перезапуск. Маркеры заголовочные — риск минимален; COMPLETE-summary ограничен 3 строками без заголовков (оп. 2.5).

### R6: Ложный throw JSON-гейта на первом pipeline-вызове (race, оп. 1.4)
- Симптом: `⛔ JSON OUTPUT REQUIRED` при фактически выданном JSON; повторный ход проходит.
- **Действие:** допустимо единично (self-healing, усиливает ритуал). Если системно в каждой сессии — вернуть grace для ПЕРВОГО pipeline-вызова: `jsonGracePeriod = isFirstTaskCall` (откат одной строки оп. 1.4), сохранив остальное.

### R7: Файлы, требующие бэкапа (полный список = оп. 0.1)
`workflow-enforcement.ts`, `plankestrator.md`, `orchestrator.md` (не меняется, но страхуется), `opencode.json`, `ARCHITECTURE.md`, `AGENTS.md`, `PLUGIN.md`, `CHANGELOG.md` → `backup\2026-09-07_plankestrator_selfwork_fix\` + `HASHES.txt`.
- **Полный откат:** `Copy-Item "$bk\*.*" — по исходным путям` (plugin/agents/json → `C:\Users\Admin\.config\opencode\...`, docs → корень проекта) → перезапуск opencode → сверка с HASHES.txt.

## Зависимости и проверки перед стартом

1. **Opencode НЕ запущен** во время правок Фаз 1–2 (или правки применяются до перезапуска — конфиги читаются при старте сессий; горячая перезагрузка плагина не гарантирована).
2. Доступ на запись к `C:\Users\Admin\.config\opencode\` (plugin, agents, json).
3. `rg` и `npx` (tsc) доступны в shell исполнителя; для tsc — сеть/node_modules не обязательны (флаг `--skipLibCheck`, единственная ожидаемая ошибка TS2307 допустима).
4. Бэкап (Фаза 0) выполнен и проверен (8 файлов + HASHES.txt) — **блокирующая зависимость для Фаз 1–5**.
5. Файлы не изменены с момента исследования: сверить контрольные строки (`rg -n "The moment you can fill the JSON" plankestrator.md` → строка 58; `rg -n "PRIMARY_AGENT_ALLOWED_TOOLS = new Set" workflow-enforcement.ts` → строка 467). При расхождении номеров — пересчитать якоря ДО начала правок.
6. Для Фазы 5 дополнительно: решение пользователя по триггеру (≥2 нарушения в ≥5 сессиях).

## Не реализуем сейчас (осознанные отсечения)

| Item | Причина |
|---|---|
| «Не более одного Task за ход» в plugin (исследование, Пробел 4) | Границы хода модели ненаблюдаемы из доступных хуков; частичное покрытие — warn-лог оп. 1.6 («TASK CALL WHILE SUBAGENT ACTIVE») ловит параллельные Task-вызовы. Полный enforcement потребует per-message turn-tracking — отдельное исследование API opencode. |
| Per-turn re-requirement JSON (флаг `hasOutputtedJSON` сбрасывается только на сессию, не на ход) | Существующая семантика v3; изменение затронет orchestrator и потребует reset-хука на каждое новое assistant-сообщение. Вне scope Рек. 1–12. |
| Удаление строки 5 таблицы пайплайнов (RESEARCH+PLAN SIMPLE) | Синхронизация ARCHITECTURE.md L245 + MCP_SETUP.md L755 + планкестратор-таблицы; правило «ALWAYS COMPLEX» (оп. 2.4) решает задачу классификации без лома таблицы. |
| Per-session state map вместо модульных переменных (полное решение гонок параллельных сессий) | Существующее ограничение архитектуры plugin (single-user); parentID-guard + activeTaskDepth закрывают целевой сценарий (родитель/потомок) с минимальным diff. |
| Синхронизация снапшотов `deploy-package\`, `opencode-config\`, `backup\*` | Снапшоты — исторические копии (оп. 3.8). |
