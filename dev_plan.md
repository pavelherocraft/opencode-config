# Phase 4: Testing — Multi-Phase Pipelines (MVP, plugin v7)

> **Источник:** `PLAN_MULTI_PHASE_PIPELINES.md` §Phase 4 (шаги 4.1–4.5), Verification Checklist V-22…V-24.
> **Статус входа:** Phases 1–3 завершены. `plugins/workflow-enforcement.ts` (live `C:\Users\Admin\.config\opencode\plugins\` и repo `P:\Programming\Рефакторинг\plugins\`) — 2582 строки, **байт-в-байт идентичны** (проверено recon); все v7-маркеры на месте: VALID_VALUES.state (:65–68), pipelineState.phases/currentPhaseIdx (:176–182), константы MULTI_PHASE_* (:211–219), awaitingConfirmation/awaitingMsgId (:221–228), gate clearing (:578–599), mpEmptyShapeOk (:801–820), validateNextAgent whitelist кейсы 5–7 (:857–885), gate arming (:928–949), provisional fix (:994–1000), Turn-1 lock + resume detect (:1003–1032), MP-1..MP-6 whitelist (:1035–1085), blockerStop reset (:1098–1109), phases refresh в unchanged-ветке (:1159–1173), ack-формы 7–9 + regex (:1182–1209), confirmation gate throw (:1393–1411), phase-хелперы (:2150–2211), MULTI_PHASE-ветка validatePipeline (:2271–2334), conditional fields validateJSONOutput (:2452–2478).
> **Язык плана:** русский (код/логи/asserts — английские, конвенция файлов).

---

## Goal

1. Расширить harness `plugins/test-workflow-enforcement.mjs` (165 строк, T1–T8) симуляцией `message.updated` и хелперами `sendMessage` / `orchMsg` / `tryTask`.
2. Добавить 20 новых тестов **T9–T26** (канонические id — таблица PLAN §4.2, строки 901–920), покрывающих: confirmation gate (+ fallback по messageID), per-phase валидацию, provisional trap, mutation whitelist MP-1..MP-6, structural fail-closed, terminal-shape, blockerStop reset, refinement-once, ack-формы 7–9, resume, single-phase регрессию.
3. Прогнать harness против **live** и **repo** копий плагина (V-22): `RESULT: pass=<N> fail=0`.
4. Выполнить живые пилоты **S1–S7** (PLAN §4.4) + V-pilot-1 (видимость user-role сообщений, PLAN §4.3) + телеметрию (PLAN §4.5) → V-23, V-24.

**НЕ входит в Phase 4:** правки промптов/плагина/opencode.json (при выявлении бага — см. Dependencies), CHANGELOG/config-sync/коммит (Phase 5).

---

## Architecture

### Подход

- Harness остаётся **плоским скриптом** (без test-runner): новые хелперы вставляются после `tryTool` (:73–80), новые тесты — после T8 (:161), до итогового `RESULT` (:163–165). Существующие T1–T8 и хелперы **не изменяются** (регрессия).
- Один инстанс плагина на весь файл (`:65`). Изоляция сценариев — через `lockSession('orchestrator')` (session.created сбрасывает ВСЁ состояние плагина: :342–367 — pipelineState, флаги, blockerStop, awaitingConfirmation, activeTaskDepth=0) + `logs.length = 0`.
- Симуляция `message.updated` — через `plugin.event({ event: { type, properties: { message } } })`. Плагин читает: `properties.message` (:562), `message.id || message.info?.id` (:572), `message.role || message.info?.role` (:587), `message.content` — **строка** с ```json-блоком (extractJSONFromMessage :2122–2147; extractIdentityFromMessage :2105–2116).
- Task-вызовы симулируются парой `tool.execute.before` + `tool.execute.after` (баланс `activeTaskDepth`: +1 при успешном task :1802/:1886, −1 в after :1906). **Разбалансировка depth молча отключает весь enforcement** (:1304, :487) — главный питч harness (см. Edge Cases #1).
- Негативные проверки — через **probe**: `tryTool('read')` → gate 9.0в (:1364–1391) бросает `WORKFLOW VIOLATION — <CODE>` и **consume-once** сбрасывает флаги. Порядок кодов в gate: identityMissing > pipelineMismatch > nextAgentMismatch > invalidJSON > forbiddenIdentity > pipelineImmutable > blockerStop (:1366–1372); текст `violationDetail` в теле throw — **последний** записанный (важно для T14: code=PIPELINE VALIDATION FAILED, detail=PIPELINE IMMUTABLE (MULTI_PHASE)).

### Соответствие нумерации (задание ↔ канон PLAN §4.2)

Канон — таблица PLAN_MULTI_PHASE_PIPELINES.md :901–920. Обзор задания использует другую нумерацию; покрытие полное:

| Обзор задания | Канон PLAN | Где покрыто |
|---|---|---|
| T9 AWAITING валиден + same-turn Task блок | T9 | Step 4.2 / T9 |
| T10 user-role clearing | T10 | T10 |
| T10b fallback по messageID | T10b | T10b |
| T11 executing-ход после AWAITING | T12 | T12 |
| T12 «4 фазы → fail-closed» | T18(a) | T18a |
| T13 single-phase регрессия | T26 | T26(a–e) |
| T14 MP-1 refinement once per phase | T22 | T22 |
| T15/T15b terminal exemption, финальный ход | T15b | T15b |
| T16 MP-2 BUGFIX continuation | T13 | T13 |
| T17 «MP-3 nit-skip» | T22 (MP-1/MP-3) + nit-skip single-phase | T22 + T26(d) |
| T18 MP-4 Auto-DOCS hook | T20 | T20 |
| T19 MP-5 phase transition | T15 | T15 |
| T20 MP-6 SUPERCOMPLEX per-step | T23 | T23 |
| T21 blockerStop reset | T21 | T21 |
| T22 provisional trap | T14 | T14 |
| T23 immutable pipeline | T16 + T17 | T16, T17 |
| T24 ack format | T24 | T24 |
| T25 «severity gate» | T25 канон = resume; severity gate — существующий механизм :765–773 | T25 + доп. sub-check T26(f) |
| T26 «cross-routing prevention» | T26 канон = single-phase регрессия; cross-routing — существующий :1814–1831 | T26 + доп. sub-check T26(g) |

Пилоты: S1 задания = канон S1; S2 задания = канон S5; S3 задания → опц. **S8**; S4 задания = канон S3 (edit) + S4 (reject) + S1 (approve); S5 задания → опц. **S9**; S6 задания → опц. **S10**; S7 задания = канон S7 + опц. **S7b** (invalid transition live).

---

## Files to Modify

1. **`P:\Programming\Рефакторинг\plugins\test-workflow-enforcement.mjs`** (repo-only, НЕ входит в 5 sync-пар) — единственная кодовая правка Phase 4:
   - после `:80` (tryTool) — блок v7-хелперов (~60 строк);
   - после `:83` — блок фикстур (ROW*, PH*, mp()) (~40 строк);
   - после `:161` (T8) — секции T9–T26 (~450–550 строк);
   - опционально: docblock `:2–22` — добавить строку «v7: + message.updated simulation, T9–T26 (Multi-Phase MVP)».
   - Итоговый размер файла: ~700–800 строк. Ожидаемый результат: `RESULT: pass≈65–70 fail=0` (17 существующих check + ~50 новых).
2. **`RESEARCH_MULTI_PHASE_PIPELINES.md`** §9.4 — append телеметрии пилотов S1/S5 (Step 4.5; 2–5 строк, опционально до Phase 5).
3. Артефакты пилотов (не файлы repo): `PHASE_STATE.md` в пилотном проекте, записи в логах opencode, заметка результата V-pilot-1 для CHANGELOG Phase 5.

**НЕ修改:** `plugins/workflow-enforcement.ts` (live и repo), `agents/*.md`, `ARCHITECTURE.md`, `opencode.json`. Баг плагина, найденный тестами → отдельная правка live+repo с немедленным репрогоном (см. Dependencies #5).

---

## Implementation Details

### Step 4.0 — Baseline (до правок)

1. `node --version` → **≥ 22.6** (harness импортирует .ts через Node type-stripping, :44; без tsx/jiti).
2. Прогон существующего harness (резолвит LIVE-плагин, candidate #2 :30–35):
   ```powershell
   cd P:\Programming\Рефакторинг
   node plugins\test-workflow-enforcement.mjs
   ```
   **Verify:** `PLUGIN: C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts`, `RESULT: pass=17 fail=0`, exit 0.
3. Контроль идентичности live/repo (уже подтверждён recon; перепроверка):
   ```powershell
   (Get-FileHash "$env:USERPROFILE\.config\opencode\plugins\workflow-enforcement.ts").Hash -eq (Get-FileHash "P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts").Hash
   ```
   **Verify:** `True`. Если False — сначала `config-sync --save` (порядок развёртывания PLAN :68), затем повторить baseline.

### Step 4.1 — Расширение harness: хелперы + фикстуры

**Вставка после `:80`** (после `tryTool`). Точный код (адаптирован из PLAN шага 4.1 с обязательными исправлениями — баланс depth, unique-id, probe-семантика):

```js
// ============================================================================
// v7 (Multi-Phase MVP) helpers — message.updated simulation + task depth
// ============================================================================
let msgSeq = 0

/** message.updated. id уникален (msgSeq), кроме {id} — re-fire того же
 *  сообщения (streaming-симуляция: gate НЕ снимается при том же messageID). */
async function sendMessage(role, content, { id } = {}) {
  const mid = id || `m${++msgSeq}`
  await plugin.event({
    event: { type: 'message.updated', properties: { message: { id: mid, role, content } } },
  })
  return mid
}

/** Сообщение orchestrator: identity line + ```json``` + ack-строка.
 *  ВАЖНО: content НЕ должен содержать токены FORBIDDEN_VOCAB orchestrator
 *  ("## PLAN", "# Implementation Plan", "plan-writer-", "research-writer-",
 *  "research-reviewer", "plan-reviewer-") и SELF_WORK_MARKERS
 *  ("## Findings", "## Analysis", "## Implementation", "## Root Cause"). */
function orchMsg(jsonObj, { identity = true, ack } = {}) {
  const ackLine = ack !== undefined ? ack
    : (jsonObj.next_agent
        ? `→ DELEGATED to ${jsonObj.next_agent} for: ${jsonObj.goal || 'goal'}`
        : '')
  return (identity ? '✓ IDENTITY VERIFIED: I am orchestrator (Conductor). I am NOT plankestrator.\n' : '') +
    '```json\n' + JSON.stringify(jsonObj) + '\n```\n' + ackLine
}

/** tool.execute.after для task — ОБЯЗАТЕЛЕН после успешного tryTask(keepDepth),
 *  иначе activeTaskDepth>0 молча отключает enforcement до конца сессии. */
async function endTask(args) {
  await plugin['tool.execute.after']({ tool: 'task', args }, { args })
}

/** Task-вызов. Успех → depth+1; баланс автоматом, кроме keepDepth=true
 *  (нужно для T21: reviewer-сообщения валидны только при depth>0). */
async function tryTask(subagent, { keepDepth = false } = {}) {
  const args = { subagent_type: subagent, description: 'd', prompt: 'p' }
  const r = await tryTool('task', args)
  if (r.ok && !keepDepth) await endTask(args)
  return r
}

/** Reviewer-JSON субагента (отправлять МЕЖДУ tryTask(keepDepth) и endTask).
 *  agent ∈ SEVERITY_AGENTS (:90) = dev-reviewer | consistency-checker | advisor. */
function reviewerMsg(agent, severity, text) {
  return '```json\n' + JSON.stringify({ agent, severity, findings: [{ text, severity }] }) + '\n```'
}

/** Probe gate 9.0в: 'clean' | текст throw (CONSUME-ONCE: флаг сбрасывается!).
 *  После первого успешного Task read блокирован (:1452) — это НЕ violation. */
async function probeGate() {
  const r = await tryTool('read')
  if (r.ok) return 'clean'
  if (r.message.includes('PRIMARY AGENT FORBIDDEN')) return 'clean'
  return r.message
}

function hasLog(substr) { return logs.some((m) => m.includes(substr)) }
async function newSession(agent = 'orchestrator') { await lockSession(agent); logs.length = 0 }
const clonePhases = (ph) => ph.map((p) => ({ ...p, depends_on: [...p.depends_on] }))
```

**Вставка после `:83`** (фикстуры; ключи сверены с PIPELINES :2222–2261):

```js
// v7 fixtures — canonical PIPELINE TABLE rows (validatePipeline keys)
const ROW1 = ['bugfix-triage']                                             // BUGFIX-null-null (+variants :2248)
const ROW1_SIMPLE = ['bugfix-triage', 'worker', 'utility']                 // BUGFIX variant SIMPLE
const ROW5 = ['dev-planner', 'dev-professor', 'advisor', 'dev-reviewer', 'consistency-checker', 'utility'] // DEV-COMPLEX-false
const DEVOPS_ROW = ['devops-agent', 'devops-reviewer']                     // DEVOPS-null-null
const HOOK = ['docs-writer', 'utility']                                    // DOCS_HOOK_CHAIN / DOCS-SIMPLE-any

const PH2 = [
  { id: 'P1', type: 'BUGFIX', complexity: null, plan_exists: null, goal: 'fix bug X', depends_on: [] },
  { id: 'P2', type: 'DEV', complexity: 'COMPLEX', plan_exists: false, goal: 'add feature Y', depends_on: ['P1'] },
]
const PH3 = [
  { id: 'P1', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'setup CI', depends_on: [] },
  { id: 'P2', type: 'DEV', complexity: 'SIMPLE', plan_exists: false, goal: 'add tests', depends_on: ['P1'] },
  { id: 'P3', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'deploy', depends_on: ['P2'] },
]
// Для T22: DEV-фаза первой (refinement complexity null→COMPLEX на DECOMPOSITION Turn B).
// plan_exists:false ОБЯЗАТЕЛЕН с самого начала — DEV-null-null fail-closed (deviation D, :2313–2318).
const PH_DEV_FIRST = [
  { id: 'P1', type: 'DEV', complexity: null, plan_exists: false, goal: 'add feature Y', depends_on: [] },
  { id: 'P2', type: 'BUGFIX', complexity: null, plan_exists: null, goal: 'fix bug X', depends_on: ['P1'] },
]

/** Валидный MULTI_PHASE-скелет со ВСЕМИ required-полями orchestrator (:56). */
function mp(over = {}) {
  return {
    agent: 'orchestrator', type: 'MULTI_PHASE', complexity: null, plan_exists: null,
    plan_source: null, goal: 'multi-phase task', next_agent: null, pipeline: [],
    state: null, phases: PH2, current_phase: null, ...over,
  }
}
```

**Verify Step 4.1:** `node plugins\test-workflow-enforcement.mjs` → T1–T8 по-прежнему `fail=0` (хелперы инертны до использования); синтаксис без ошибок.

### Step 4.2 — Тесты T9–T26

Каждый тест: `await newSession()` → `logs.length = 0` уже внутри → последовательность `sendMessage`/`tryTask`/`probeGate` → `check(...)`. Assert-подстроки копировать 1:1 из плагина (ссылки даны). Ниже — спецификация каждого теста.

---

#### T9 — Confirmation gate: AWAITING валиден + same-turn Task блокирован (механизм: arming :928–943, throw :1393–1411)

```js
await newSession()
const awaitId = await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
  { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }))
check('T9a AWAITING turn is VALID (no deferred flags)', await probeGate() === 'clean', ...)
check('T9b gate armed log', hasLog('Task calls blocked until the user replies'), logs.join(' | '))
const r = await tryTask('bugfix-triage')   // ТОТ ЖЕ ход (messageID = awaitId)
check('T9c same-turn Task blocked', !r.ok && r.message.includes('AWAITING USER CONFIRMATION'), ...)
check('T9d gate log', hasLog('CONFIRMATION GATE — Task blocked while AWAITING_CONFIRMATION'), ...)
// T9e: streaming re-fire ТОГО ЖЕ messageID не снимает gate (:583–585, :593)
await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
  { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }), { id: awaitId })
const r2 = await tryTask('bugfix-triage')
check('T9e re-fire same messageID keeps gate armed', !r2.ok && r2.message.includes('AWAITING USER CONFIRMATION'), ...)
```

Примечания: (a) AWAITING-проход валиден благодаря mpEmptyShapeOk (:808–820) + явной ветке validatePipeline (:2282–2292) + `next_agent:null` → validateNextAgent valid (:2417); (b) blocked Task НЕ инкрементирует depth (throw до :1886) — endTask не нужен; (c) blocked Task не потребляет per-turn quota (gate до :1419).

#### T10 — Gate cleared user-role сообщением (clearing :586–592)

Продолжение T9 (та же сессия) или свежая:

```js
await sendMessage('user', 'да')
check('T10a USER RESPONSE log', hasLog('USER RESPONSE RECEIVED — confirmation gate cleared'), ...)
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
  { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
const r = await tryTask('bugfix-triage')
check('T10b Task allowed after user reply', r.ok, r.message)
```

Примечание: user-сообщение НЕ армит identityMissing — `hasOutputtedJSON` уже true от AWAITING-хода (:635–637, :926).

#### T10b — Gate fallback: новый assistant messageID без user-role (:593–598)

```js
await newSession()
await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' })))       // msgId A
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }))) // msgId B
check('T10b-1 fallback log', hasLog('user reply implied'), ...)
const r = await tryTask('bugfix-triage')
check('T10b-2 Task allowed via messageID fallback', r.ok, r.message)
```

#### T11 — `state` с type≠MULTI_PHASE → invalid (validateJSONOutput v7 :2466–2469)

```js
await newSession()
await sendMessage('assistant', orchMsg({
  agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE', plan_exists: false, plan_source: null,
  goal: 'single dev', next_agent: 'worker', pipeline: ['worker', 'utility'],
  state: 'AWAITING_CONFIRMATION',
}))
const p = await probeGate()
check('T11a INVALID JSON via deferred gate',
  p !== 'clean' && p.includes('INVALID JSON OUTPUT') && p.includes('state field is only valid with type=MULTI_PHASE'), p)
check('T11b confirmation gate NOT armed for non-MULTI_PHASE', !hasLog('AWAITING USER CONFIRMATION'), ...)
```

**Питч:** pipeline обязан быть валидной DEV-строкой (`DEV-SIMPLE-false` = `['worker','utility']`), иначе pipelineMismatch (приоритет :1367) замаскирует invalidJSON-код.

#### T12 — Executing-ход MULTI_PHASE: per-phase валидация (ветка :2303–2333)

```js
await newSession()
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
  { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
check('T12a no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), logs.join(' | '))
const r = await tryTask('bugfix-triage')
check('T12b executing turn Task ok (key BUGFIX-null-null)', r.ok, r.message)
```

#### T13 — In-phase BUGFIX continuation (MP-2, whitelist :1050–1054, next-agent кейс 7 :878–883)

Продолжение T12 (depth сбалансирован):

```js
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' }),
  { ack: '→ PHASE 1/2 (P1): DELEGATED to worker for: fix bug X' }))
check('T13a MP-2 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-2 in-phase BUGFIX continuation'), logs.join(' | '))
const r = await tryTask('worker')
check('T13b continuation Task ok', r.ok, r.message)
```

Валидность: key BUGFIX-null-null + variant ROW1_SIMPLE (:2250); next='worker' = newPipeline[1] → isBugfixContMP.

#### T14 — Provisional trap fixed: нелегальная замена внутри frozen-фазы (fix :994–1000; ветка MP :1035–1085)

```js
await newSession()
const PHR = [
  { id: 'P1', type: 'DEV', complexity: 'COMPLEX', plan_exists: false, goal: 'add feature Y', depends_on: [] },
  { id: 'P2', type: 'BUGFIX', complexity: null, plan_exists: null, goal: 'fix bug X', depends_on: ['P1'] },
]
await sendMessage('assistant', orchMsg(mp({ phases: PHR, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' })))
const r1 = await tryTask('dev-planner')
check('T14a Turn1 lock ok', r1.ok, r1.message)
await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PHR), current_phase: 'P1',
  pipeline: ['worker', 'utility'], next_agent: 'worker' })))   // подмена цепочки
const p = await probeGate()
check('T14b illegal swap blocked (F-4 provisional НЕ срабатывает)',
  p !== 'clean' && p.includes('WORKFLOW VIOLATION') && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'), p)
```

Примечание: code в throw будет `PIPELINE VALIDATION FAILED` (приоритет флагов), но `violationDetail` в теле — `PIPELINE IMMUTABLE (MULTI_PHASE): illegal mutation …` (:1131–1137) — assert по detail. До v7 этот ход прошёл бы через F-4 (top-level complexity null → provisional=true).

#### T15 — Legal phase transition (MP-5, :1070–1073; next-agent кейс 5 :860–865)

```js
await newSession()
// P1 (BUGFIX) полностью: Turn1 → continuation → utility (advance step до 2)
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
await tryTask('bugfix-triage')
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' })))
await tryTask('worker')
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'utility' })))
await tryTask('utility')
// Barrier → transition
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
  { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
check('T15a MP-5 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-5 phase transition'), logs.join(' | '))
const r = await tryTask('dev-planner')
check('T15b transition Task ok', r.ok, r.message)
```

Turn `next_agent:'utility'` — pipeline unchanged, nextIdx=2 → advance (:1157–1158); validateNextAgent effectiveStep=2=pipeline[2] ✓.

#### T15b — Final turn clean (terminal-shape early return внутри ветки :2293–2302)

Продолжение T15 (или отдельная сессия с P2, доведённой до utility):

```js
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: [], next_agent: null })))
check('T15b-1 no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), ...)
check('T15b-2 no INVALID JSON OUTPUT', !hasLog('INVALID JSON OUTPUT'), ...)
check('T15b-3 no DEFERRED VIOLATION', !hasLog('DEFERRED VIOLATION ENFORCED'), ...)
check('T15b-4 probe clean', await probeGate() === 'clean', ...)
```

Форма: `state:null` + `pipeline:[]` + `next_agent:null` + `current_phase:'P2'` (id последней фазы) + phases без изменений → mpEmptyShapeOk (:808–813) + early return (:2299–2301); state block не трогается (newPipeline.length===0, :988); ack-audit пропущен (next_agent null, :1194).

#### T16 — Transition-skip (P1→P3) запрещён (MP-5 требует строго +1, :1051)

```js
await newSession()
await sendMessage('assistant', orchMsg(mp({ phases: PH3, current_phase: 'P1', pipeline: DEVOPS_ROW, next_agent: 'devops-agent' })))
await tryTask('devops-agent')
await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PH3), current_phase: 'P3', pipeline: DEVOPS_ROW, next_agent: 'devops-agent' })))
const p = await probeGate()
check('T16 skip transition blocked', p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'), p)
```

Примечание: validatePipeline per-phase для P3 (DEVOPS-null-null) ПРОХОДИТ, nextAgent — isLoopback; единственный флаг — pipelineImmutable (newIdx 2 ≠ prevIdx 0+1) → code в throw = `PIPELINE IMMUTABLE`.

#### T17 — Phases tampering на transition (phasesStableOrRefined :2168–2183)

```js
// как T16, но легальный переход P1→P2 с изменённым goal у P2:
const tampered = clonePhases(PH3); tampered[1].goal = 'TAMPERED goal'
await sendMessage('assistant', orchMsg(mp({ phases: tampered, current_phase: 'P2',
  pipeline: ['worker', 'utility'], next_agent: 'worker' })))
const p = await probeGate()
check('T17 phases tampering blocked', p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'), p)
```

(P2 = DEV-SIMPLE-false → `['worker','utility']` валиден per-phase; падает только whitelist: goal отличается → stableOrRefined=false.)

#### T18 — Структурные нарушения phases → fail-closed (validatePhasesStructure :2160–2166…; 5 sub-checks, каждая в свежей сессии)

Отправлять как AWAITING-ход (`state:'AWAITING_CONFIRMATION'`, pipeline [], next null) — structErr проверяется в обеих валидациях (:2287–2290, :2456–2460):

| Sub | Мутация phases | Assert (probe ≠ 'clean' И message/logs содержит) |
|---|---|---|
| T18a | 4 фазы (PH3 + P4 DEVOPS depends_on ['P3']) | `out of range [2..3]` |
| T18b | `[P1, {...P1}]` (дубль id) | `duplicate phase id` |
| T18c | P1.depends_on = ['P2'] (forward ref) | `depends_on must be []` |
| T18d | 2 фазы SUPERCOMPLEX (обе plan_exists:true) | `at most ONE SUPERCOMPLEX` |
| T18e | P2.depends_on = [] (два корня) | `depends_on must be ["P1"]` |

Каждая: `await newSession()` → `sendMessage(orchMsg(mp({ state:'AWAITING_CONFIRMATION', phases: <bad> })))` → `probeGate()` → check подстроки + `hasLog('PIPELINE VALIDATION FAILED')`. Дополнительно T18a: assert что gate НЕ вооружён (`!hasLog('Task calls blocked')`) — arming только в valid-ветке (:925–943).

#### T19 — CANCELLED shape (:2282–2292, defensive disarm :944–949)

```js
await newSession()
await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' })))
await sendMessage('user', 'отмена')
await sendMessage('assistant', orchMsg(mp({ state: 'CANCELLED' })))
check('T19a no DEFERRED VIOLATION', !hasLog('DEFERRED VIOLATION ENFORCED'), ...)
check('T19b no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), ...)
check('T19c probe clean (gate disarmed)', await probeGate() === 'clean', ...)
```

#### T20 — In-phase Auto-DOCS hook (MP-4, :1055–1058; validatePipeline :2309–2312; next-agent кейс 6 :866–874)

```js
await newSession()
// P1 BUGFIX до конца (3 хода как в T15: triage → worker → utility; currentStep=2 = len-1)
... (ROW1/next bugfix-triage; ROW1_SIMPLE/next worker; ROW1_SIMPLE/next utility — каждый с tryTask)
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: HOOK, next_agent: 'docs-writer' }),
  { ack: '→ PHASE 1/2 (P1): DELEGATED to docs-writer for: docs update' }))
check('T20a MP-4 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-4 in-phase Auto-DOCS hook'), logs.join(' | '))
const r = await tryTask('docs-writer')
check('T20b hook Task ok', r.ok, r.message)
```

Условие isDocsHookMP: `pState.currentStep >= pState.pipeline.length - 1` (2 ≥ 2) ✓, phase.type BUGFIX ∈ [BUGFIX, DEV] ✓.

#### T21 — blockerStop reset (edge case #2; escalation :507–531, gate :1364–1372, reset :1098–1109)

Двухчастный (consume-once gate заставляет реармить). R12-фолбэк: если depth-баланс в harness не сойдётся — деградировать до интеграционной проверки в живом пилоте (3 blocker → BLOCKER STOP → transition), зафиксировав в отчёте.

```js
await newSession()
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
// Part A: 3 blocker → gate блокирует
await tryTask('bugfix-triage', { keepDepth: true })
for (let i = 1; i <= 3; i++)
  await sendMessage('assistant', reviewerMsg('dev-reviewer', 'blocker', `blocking issue ${i}`))
await endTask({ subagent_type: 'bugfix-triage', description: 'd', prompt: 'p' })
check('T21a escalation counted 3/3', hasLog('BLOCKER ESCALATION COUNTED — 3/3'), ...)
const pA = await probeGate()
check('T21b gate blocks after 3 blockers', pA !== 'clean' && pA.includes('BLOCKER STOP AFTER 3'), pA)
// Part B: continuation (MP-2) → 4-й blocker (реарм) → transition MP-5 → reset
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' })))
await tryTask('worker', { keepDepth: true })
await sendMessage('assistant', reviewerMsg('dev-reviewer', 'blocker', 'blocking issue 4'))
await endTask({ subagent_type: 'worker', description: 'd', prompt: 'p' })
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
  { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
check('T21c BLOCKERSTOP RESET logged on MP-5', hasLog('BLOCKERSTOP RESET — legal multi-phase transition'), logs.join(' | '))
const r = await tryTask('dev-planner')
check('T21d Task ok after reset', r.ok, r.message)
```

Механика: reviewer-сообщения при depth>0 → subagent-ветка (:487–559); unique messageID (msgSeq) обходит дедуп `:blocker` (:519–521); 4-й blocker → bCount=4 ≥ 3 → rearm (:527–530); MP-5-ветка сбрасывает blockerStop + violationDetail (:1098–1109).

#### T22 — Phase refinement once (MP-1/MP-3 :1059–1062; unchanged-ветка refresh :1159–1173)

```js
await newSession()
// Turn A: DECOMPOSITION-диспетч внутри P1 (key DEV-null-false → variant ['dev-planner'], deviation D :2313–2318)
await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PH_DEV_FIRST), current_phase: 'P1',
  pipeline: ['dev-planner'], next_agent: 'dev-planner' })))
const rA = await tryTask('dev-planner')
check('T22a Turn A (decomposition dispatch) ok', rA.ok, rA.message)
// Turn B: refinement null→COMPLEX (ОДИН раз) + row5
const phB = clonePhases(PH_DEV_FIRST); phB[0].complexity = 'COMPLEX'
await sendMessage('assistant', orchMsg(mp({ phases: phB, current_phase: 'P1', plan_source: 'DECOMPOSITION',
  pipeline: ROW5, next_agent: 'dev-planner' })))
check('T22b refinement allowed (MP-1/MP-3)', hasLog('MP-1/MP-3 phase refinement / DECOMPOSITION'), logs.join(' | '))
const rB = await tryTask('dev-planner')   // isLoopback: slice(0,1) содержит dev-planner (:841–842)
check('T22c Turn B Task ok', rB.ok, rB.message)
// Turn C: ВТОРОЙ refinement COMPLEX→SIMPLE → заблокирован
const phC = clonePhases(phB); phC[0].complexity = 'SIMPLE'
await sendMessage('assistant', orchMsg(mp({ phases: phC, current_phase: 'P1',
  pipeline: ['worker', 'utility'], next_agent: 'worker' })))
const p = await probeGate()
check('T22d second refinement blocked', p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'), p)
```

Ключевое: refresh phases в unchanged-ветке (:1169–1173) гарантирует, что после Turn B снапшот хранит COMPLEX → Turn C не null→value → stableOrRefined=false. Turn C validatePipeline проходит (DEV-SIMPLE-false = ['worker','utility']) — падает только whitelist.

#### T23 — SUPERCOMPLEX phase (plan-структура :2172–2176; next-agent exempt :852–856)

```js
await newSession()
const PHS = [
  { id: 'P1', type: 'DEV', complexity: 'SUPERCOMPLEX', plan_exists: true, goal: 'big migration', depends_on: [] },
  { id: 'P2', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'deploy', depends_on: ['P1'] },
]
await sendMessage('assistant', orchMsg(mp({ phases: PHS, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' }),
  { ack: '→ PHASE 1/2 (P1), STEP 1/5 (S-1): DELEGATED to dev-planner' }))
const r1 = await tryTask('dev-planner')
check('T23a SUPERCOMPLEX phase turn ok (key DEV-SUPERCOMPLEX-true)', r1.ok, r1.message)
// per-step re-emission того же массива (unchanged-ветка, advance)
await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PHS), current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-professor' }),
  { ack: '→ PHASE 1/2 (P1), STEP 2/5 (S-2): DELEGATED to dev-professor' }))
check('T23b no violation on per-step re-emission', !hasLog('DEFERRED VIOLATION ENFORCED') && !hasLog('PIPELINE IMMUTABLE'), ...)
const r2 = await tryTask('dev-professor')
check('T23c per-step Task ok', r2.ok, r2.message)
// Негатив: SUPERCOMPLEX без plan_exists на executing-ходе → structErr
await newSession()
const PHX = clonePhases(PHS); PHX[0].plan_exists = null
await sendMessage('assistant', orchMsg(mp({ phases: PHX, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' })))
const p = await probeGate()
check('T23d SUPERCOMPLEX requires plan_exists=true (executing)', p !== 'clean' && p.includes('SUPERCOMPLEX requires plan_exists=true'), p)
```

Примечание: MP-6 label (:1064–1069) достижим только если массив ФАКТИЧЕСКИ меняется при SUPERCOMPLEX-фазе (identical re-emission идёт по unchanged-ветке) — assert на label не ставим (log-only паритет F-11), достаточно ok:true.

#### T24 — Ack audit: формы 7–9 без warn (regex :1204, warn :1205–1209)

```js
await newSession()
// Форма 7: PHASE + ':' + DELEGATED (audit срабатывает: next_agent truthy, :1194)
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
  { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
check('T24a form 7 no warn', !hasLog('ACK FORMAT INVALID'), logs.join(' | '))
await tryTask('bugfix-triage')
// Форма 8: PHASE + ',' + STEP (нужен новый msgId для ack-дeduп и quota)
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' }),
  { ack: '→ PHASE 1/2 (P1), STEP 2/5 (S-2): DELEGATED to worker' }))
check('T24b form 8 no warn', !hasLog('ACK FORMAT INVALID'), ...)
// Форма 9: AWAITING (next_agent null → audit пропущен; warn тоже не должно быть)
await newSession()
await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
  { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }))
check('T24c form 9 no warn', !hasLog('ACK FORMAT INVALID'), ...)
// Регрессия старой формы 1
await newSession()
await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null, plan_exists: null,
  plan_source: null, goal: 'fix bug X', next_agent: 'bugfix-triage', pipeline: ROW1 }))
check('T24d legacy form 1 no warn', !hasLog('ACK FORMAT INVALID'), ...)
```

**Питч:** ack-строка — ПОСЛЕДНЯЯ строка content, без хвостовых пробелов (regex `^→…$/m`); `→` — U+2192.

#### T25 — Resume в новой сессии (warn :1016–1032)

```js
await newSession()   // свежее состояние = «новая сессия»
await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
  { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
check('T25a RESUME warn logged', hasLog('MULTI_PHASE RESUME DETECTED'), logs.join(' | '))
const r = await tryTask('dev-planner')
check('T25b resume Turn1 lock + Task ok', r.ok, r.message)
```

(Turn-1 lock с mpIdx=1>0 — warn-only, ход легален.)

#### T26 — Single-phase регрессия (R4: v7 не ломает существующие сценарии) + sub-checks из обзора задания

Каждый сценарий в свежей сессии, JSON — обычный single-phase (БЕЗ полей state/phases/current_phase):

- **(a) BUGFIX Turn1 + continuation:** `type:'BUGFIX', pipeline:ROW1, next:'bugfix-triage'` → tryTask ok; затем `pipeline:ROW1_SIMPLE, next:'worker'` → ok (F-1/BUGFIX-исключение single-phase ветки :1075–1082).
- **(b) DECOMPOSITION A/B:** Turn A `type:'DEV', complexity:null, plan_exists:false, pipeline:['dev-planner'], next:'dev-planner'` → ok (variant DEV-null-false); Turn B `plan_source:'DECOMPOSITION', complexity:'COMPLEX', pipeline:ROW5, next:'dev-planner'` → ok (isLoopback).
- **(c) Auto-DOCS hook single-phase:** после BUGFIX-цепочки (3 хода как в T20) ход `type:'DOCS', complexity:'SIMPLE', plan_exists:null, pipeline:HOOK, next:'docs-writer'` → ok (F-12 + isDocsHook :848–849).
- **(d) nit-skip:** после Turn-1 lock ROW5 ход `severity:'nit', pipeline:['worker','utility'], complexity:'SIMPLE', plan_exists:false, next:'worker'` → ok (nit-исключение single-phase whitelist); assert `!hasLog('PIPELINE IMMUTABLE')`.
- **(e) F-4 provisional single-phase ЖИВ:** Turn A `type:'DEV', complexity:null, plan_exists:false, pipeline:['dev-planner'], next:'dev-planner'`; Turn B `complexity:'SIMPLE', plan_exists:false, pipeline:['worker','utility'], next:'worker'` → ok (provisional=true, т.к. type≠MULTI_PHASE — v7 fix не затрагивает single-phase).
- **(f) severity gate (обзор «T25»):** ход с `severity:'critical'` (вне nit|concern|blocker, :91) → probe ≠ clean, message содержит `INVALID SEVERITY` (:765–773).
- **(g) cross-routing prevention (обзор «T26»):** в сессии (a) после валидного JSON `tryTask('plan-writer-simple')` → `!ok` и message содержит `ROUTING TABLE ENFORCEMENT (identity lock active)` (:1814–1831).

**Verify Step 4.2 (итог):** все check T9–T26 PASS; T1–T8 без изменений.

### Step 4.2v — Прогон против live и repo (V-22)

```powershell
cd P:\Programming\Рефакторинг
node plugins\test-workflow-enforcement.mjs                     # LIVE (default candidate)
$env:WORKFLOW_PLUGIN = 'P:\Programming\Рефакторинг\plugins\workflow-enforcement.ts'
node plugins\test-workflow-enforcement.mjs                     # REPO (mirror check)
Remove-Item Env:\WORKFLOW_PLUGIN
```

**Verify:** оба прогона — `RESULT: pass=<N> fail=0`, exit 0; первая строка `PLUGIN:` указывает ожидаемый путь. Провал только в repo-прогоне ⇒ drift live/repo ⇒ `config-sync --save` и повтор.

### Step 4.3 — Пилоты S1–S7 (живые сессии)

**Предусловия (обязательны до первого пилота):**
1. **Restart opencode** — плагин и промпты подхватываются только новыми сессиями (PLAN :68, :971).
2. **Пилотный проект-песочница** (НЕ `P:\Programming\Рефакторинг`): S1/S5 вносят реальные изменения кода и deploy-операции. Рекомендация: scratch-repo с минимальным приложением; для S5 фаза «задеплой» = локальный тестовый скрипт (не прод).
3. Каждый пилот = **новая сессия** orchestrator. Логи opencode: `~\.local\share\opencode\log\` (Windows: `$env:USERPROFILE\.local\share\opencode\log\`).

**Канонические пилоты (PLAN §4.4 :930–938):**

| # | Запрос пользователя | Ожидание | Verify |
|---|---|---|---|
| S1 | «Auth middleware падает с race condition — исправь, и сразу добавь refresh-токены» | T0 YES → AWAITING (2 фазы, таблица «## MULTI-PHASE PLAN», ack form 9, Task НЕТ) → «да» → P1 BUGFIX (triage→continuation) → barrier (envelope + PHASE_STATE.md секция) → P2 DEV (Q1–Q5 с учётом конверта, refinement null→значение) → final summary по 2 фазам | Логи: `MULTI_PHASE AWAITING CONFIRMATION`, clearing-лог (см. Step 4.4), `MP-5 phase transition`, НЕТ `DEFERRED VIOLATION`/`ACK FORMAT INVALID`/`PIPELINE VALIDATION FAILED`. PHASE_STATE.md: `# PHASE_STATE` + секция P1. Envelope в Task-prompt P2 (storage: `~\.local\share\opencode\storage\`) — verbatim + фраза-контекст |
| S2 | «Исправь баг с авторизацией и обнови README» | Анти-триггер: single-phase BUGFIX (+ Auto-DOCS hook при requires_docs_update); **НЕТ** AWAITING-хода | В логах нет `MULTI_PHASE`; JSON-ходы type=BUGFIX |
| S3 | S1 + после показа плана ответ «измени: фичу делай SIMPLE» | Edit-round: повторный AWAITING с phases[P2].complexity=SIMPLE (пересчёт + каскад), лимит ≤2 раундов → «да» → старт P1 | Второй AWAITING-ход в логах; после «да» — executing P1 |
| S4 | S1 + ответ «отмена» | `state:"CANCELLED"`, pipeline [], next null, ноль Task, краткое резюме предложенного | Лог defensive disarm (:944–949); Task-вызовов в сессии нет |
| S5 | «1. Настрой CI github-actions. 2. Добавь unit-тесты для X. 3. Задеплой» | 3 фазы DEVOPS+DEV+DEVOPS (повтор типа легален); конверты передаются: имя workflow P1→P2, статус тестов P2→P3; две MP-5 границы | Логи: 2× `MP-5`; PHASE_STATE.md: секции P1, P2 (P3 — DEVOPS-хвост, секция НЕ пишется — MVP-ограничение, финальный summary текстом); ack `→ PHASE i/3 …` |
| S6 | «Исправь баг X и добавь фичу Y, без подтверждений — делай сразу» | Auto-approve override: план информативно + НЕМЕДЛЕННЫЙ старт P1 в том же ходе (без AWAITING JSON); Task не блокируется | В логах НЕТ `Task calls blocked`; есть Turn-1 lock MULTI_PHASE |
| S7 (негатив) | «Составь план рефакторинга и реализуй его» | T0 scope-guard: plan-deliverable → OUT OF SCOPE (type:null, pipeline []), НЕ multi-phase | JSON type=null; нет MULTI_PHASE-логов |

**Дополнительные пилоты (покрытие сценариев из обзора задания; выполнять после канонических, время permitting):**

| # | Сценарий | Запрос / действие | Verify |
|---|---|---|---|
| S7b | Негатив: invalid phase transition live (обзор S7) | В сессии S1 после старта P1: «пропусти P1 и сразу запускай P2» | Оркестратор отказывает ИЛИ плагин блокирует (`PIPELINE IMMUTABLE (MULTI_PHASE)` в логах) и модель восстанавливается; «тихого» скачка фаз нет |
| S8 | SUPERCOMPLEX + DEVOPS (обзор S3; research §3.3 Вариант A) | «Реализуй миграцию по шагам (SUPERCOMPLEX), затем прогони тесты и задеплой» (в проекте с готовым dev_plan.md) | ≤1 SUPERCOMPLEX-фаза; двухуровневый ack `→ PHASE 1/3 (P1), STEP j/m (S-j): DELEGATED to …` (форма 8, без warn); per-step механика внутри P1 без изменений; P2/P3 DEVOPS |
| S9 | Resume после fail-fast (обзор S5; PLAN Stage 5) | Довести фазу до FAILED (3× blocker в живой сессии — попросить reviewer-сценарий или спровоцировать на песочнице) → **новая сессия**: «продолжи с фазы P2» | ОДИН classification read PHASE_STATE.md; план не пересоздаётся; старт с P2 без повторного подтверждения; warn `MULTI_PHASE RESUME DETECTED` |
| S10 | Auto-DOCS dedup (обзор S6; R7 — prompt-level) | План BUGFIX + DEV + DOCS(3-я фаза), фикс требует docs (requires_docs_update:true) | Hook после P1/ P2 **подавлен**; envelope P1 несёт `docs_deferred_to:"P3"`; Task-prompt P3 получает envelope verbatim; проверка — storage Task-prompts + PHASE_STATE.md |

**Критерии приёмки всех пилотов (PLAN :940):** нет `WORKFLOW VIOLATION` в логах; ack-формы без warn-дрейфа; PHASE_STATE.md append-only с секциями всех utility-терминированных фаз; конверты в Task-prompts соответствуют «pointer, not transcript» (summary ≤3 предложений, facts ≤10 ключей).

**Команды проверки логов (после каждого пилота):**

```powershell
$log = Get-ChildItem "$env:USERPROFILE\.local\share\opencode\log\*.log" |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
Select-String -Path $log.FullName -Pattern 'MULTI_PHASE|USER RESPONSE RECEIVED|user reply implied|MP-\d|BLOCKERSTOP|DEFERRED VIOLATION|ACK FORMAT INVALID|PIPELINE VALIDATION FAILED|PIPELINE IMMUTABLE|ROUTING TABLE'
```

**Verify Step 4.3:** чек-лист S1–S7 (таблица) выполнен; отклонения зафиксированы (какой пилот, какой лог, гипотеза). Провал пилота НЕ блокирует Phase 4-отчёт, но блокирует объявление стабильности (PLAN R2) и требует отдельного разбора перед Phase 5.

### Step 4.4 — V-pilot-1: видимость user-role сообщений (PLAN §4.3)

Выполняется по логам S1/S3 (или отдельным мини-экспериментом):

1. Живая сессия: multi-phase запрос → AWAITING-ход → ответ «да».
2. В логе opencode искать ОДИН из двух маркеров (оба легальны, резолюция #10 PLAN :48):
   - `USER RESPONSE RECEIVED — confirmation gate cleared` → **opencode доставляет user-role сообщения в message.updated** (путь (a) :586–592 — основной);
   - `NEW ASSISTANT TURN after AWAITING — user reply implied` → user-role НЕ виден плагину → **fallback по messageID (turn-based гарантия) — постоянный основной механизм** (риск R1).
3. Результат зафиксировать письменно (заметка в отчёте Phase 4 → Phase 5 внесёт в CHANGELOG/Limitations): какой путь сработал, стабильно ли (проверить в S1, S3, S4 — три user-ответа).

**Дополнительная проверка (рекомендуется):** во время AWAITING-хода в живой сессии убедиться, что оркестратор НЕ делает Task (гейт не срабатывал — в логах нет `CONFIRMATION GATE — Task blocked`; модель сама остановилась). Если срабатывал — это нормально (throw обучает модель), зафиксировать частоту.

**Verify Step 4.4:** механизм clearing определён и задокументирован; подтверждение работает в живых сессиях стабильно (3 из 3 user-ответов сняли gate).

### Step 4.5 — Телеметрия (PLAN §4.5, данные для Stage 2)

В пилотах S1 и S5 зафиксировать:
- число ходов сессии (assistant-сообщений orchestrator) от старта до final summary;
- субъективная деградация JSON/ack-дисциплины к концу цепочки (дрейф полей, warn-логи);
- размер контекста: признаки приближения к лимиту (summarize-события opencode, если видны).

Append 2–5 строк в `RESEARCH_MULTI_PHASE_PIPELINES.md` §9.4 (follow-up: решение о summarizer между фазами). **Verify:** данные записаны; выводов о Stage 2 не принимаем (только факты).

---

## Edge Cases (питчи harness — проверены по коду плагина)

1. **Баланс activeTaskDepth.** Успешный `tryTool('task', …)` инкрементирует depth (:1802/:1886); пока depth>0, `tool.execute.before` байпасит ВСЕ гейты (:1304–1339), а `message.updated` уходит в subagent-ветку (:487). Поэтому: `tryTask` автоматически вызывает `endTask`; `keepDepth:true` — только в T21, и сразу после reviewer-сообщений — `endTask`. Заблокированный throw'ом Task depth НЕ трогает (F-3, :1310–1312) — endTask после него не нужен.
2. **Один Task на ход** (:1419–1445). Счётчик сбрасывается только новым messageID (:573–576). Перед КАЖДЫМ `tryTask` — свой `sendMessage` (новый ход). Второй Task в том же ходе → `MAX ONE TASK CALL PER TURN` (не путать с ожидаемыми violation в негативных тестах).
3. **Consume-once gate 9.0в** (:1376–1379): probe-вызов СБРАСЫВАET флаги. На одно нарушение — один probe; для повторной проверки — реарм (T21 Part B: 4-й blocker).
4. **Приоритет кодов vs detail** (:1366–1372): при нескольких флагах code в throw = старший (pipelineMismatch), а `violationDetail` в теле = последний записанный. В T14 assert делать по подстроке detail `PIPELINE IMMUTABLE (MULTI_PHASE)`, а не по коду.
5. **probeGate после первого Task**: `read` блокирован (:1452–1468) — хелпер трактует `PRIMARY AGENT FORBIDDEN` как 'clean' (гейт 9.0в срабатывает РАНЬШЕ :1364 — deferred-флаги всё равно проявятся).
6. **FORBIDDEN_VOCAB / SELF_WORK_MARKERS** (:235–246, :269–279): в content тестовых сообщений запрещены токены `## PLAN`, `# Implementation Plan`, `plan-writer-`, `research-writer-`, `research-reviewer`, `plan-reviewer-`, `## Findings/Analysis/Implementation/Root Cause`. Identity-строка хелпера безопасна («I am NOT plankestrator» не содержит «I am plankestrator»). Goals в фикстурах — нейтральные («fix bug X»).
7. **content — только строка** (:2106, :2123): `message.content` string c ```json-fence; parts-массивы НЕ поддерживаются экстракторами — sendMessage шлёт строку.
8. **Deviation D** (:2313–2318): ключ `DEV-null-null` fail-closed — DECOMPOSITION-ход внутри DEV-фазы ОБЯЗАН нести `plan_exists:false` (PH_DEV_FIRST уже содержит). `DOCS-null-any` тоже неизвестен — DOCS-фазы только SIMPLE/DEEP.
9. **Уникальность id blocker-сообщений** (:519–521): дедуп `:blocker` по messageID — msgSeq гарантирует уникальность; НЕ слать одно id дважды в T21.
10. **Мутация общих фикстур**: phases-массивы ОБЪЕКТОВ разделяются между тестами — везде, где тест меняет фазы, использовать `clonePhases()` (T14, T17, T22, T23d), иначе последующие тесты ломаются неявно.
11. **mpEmptyShapeOk** (:808–820) освобождает от `PIPELINE EMPTY` только MULTI_PHASE-формы — в T11 (type=DEV) pipeline обязан быть непустым и валидным, иначе код gate замаскирует целевую ошибку state.
12. **session.created child-guard** (:312–328): `lockSession` шлёт сессию БЕЗ parentID — полный сброс; не добавлять parentID в фикстуры.
13. **Не менять существующие хелперы** (`tryTool` c `sessionID:'s1'` ≠ topLevelSessionID `s-orchestrator`): при depth>0 параллельный Task с 's1' атрибутируется как nested (легальный) — в тестах не вызывать tryTask при depth>0 кроме T21-схемы (keepDepth→reviewer→endTask без промежуточных task).
14. **ack-regex построчный** (`/m`, :1204): ack — последняя строка, точно начинается с `→ ` (U+2192 + пробел), без trailing whitespace; JSON-блок выше не мешает.
15. **hasOutputtedJSON и user-сообщения**: user-сообщение ДО первого валидного JSON вооружило бы identityMissing (:635–637) — во всех тестах user-реплики идут ПОСЛЕ assistant-JSON (как в реальном flow).
16. **Node type-stripping**: .ts-импорт (:44) требует Node ≥22.6; при `cannot import plugin` — exit 2, проверить версию.
17. **logs accumulate**: mock-client (:63) пишет ВСЕ уровни в один массив — `newSession()` обязан обнулять logs, иначе hasLog ловит строки прошлых тестов (ложные PASS).

---

## Dependencies

1. **Phases 1–3 завершены** — подтверждено recon (live==repo, 2582 строки, все v7-маркеры). Перепроверить хешем в Step 4.0.3.
2. **Baseline T1–T8 зелёный** до правок harness (Step 4.0.2) — иначе сначала чинить окружение/плагин.
3. **Node ≥ 22.6** в PATH (type-stripping).
4. **Restart opencode** перед Step 4.3 (пилоты) — новые сессии подхватывают плагин v7 + orchestrator.md с секцией MULTI-PHASE PIPELINES (Phase 2 live уже содержит).
5. **Если тест T9–T26 выявляет баг плагина** (assert не сходится с документированным поведением PLAN Phase 3): правка в **live** → перепрогон harness (live) → `config-sync --save` → перепрогон (repo) → фикс входит в тот же атомарный коммит Phase 5.3 (промпт/плагин/harness неразделимы). НЕ маскировать баг ослаблением assert без пометки в отчёте.
6. **Пилоты**: песочница-проект (не production repo); для S8 — dev_plan.md в песочнице; для S9 — воспроизводимый FAILED фазы.
7. **Phase 5 не запускается** до: `fail=0` в обоих прогонах (V-22) + S1–S7 пройдены/задокументированы (V-23) + V-pilot-1 зафиксирован.

## Verification (маппинг на PLAN Verification Checklist)

- **V-22** ← Steps 4.0, 4.2v: T1–T8 + T9–T26 зелёные против LIVE и REPO (`WORKFLOW_PLUGIN`), `RESULT: fail=0`, exit 0.
- **V-23** ← Steps 4.3, 4.4: S1–S7 (+S7b/S8–S10 опц.) пройдены; V-pilot-1: механизм clearing (user-role vs messageID-fallback) определён по логам и записан.
- **V-24** ← Step 4.3 verify-колонка: PHASE_STATE.md создаётся (`# PHASE_STATE`) и дописывается append-only; конверты в Task-prompts — small data (summary ≤3 предложений, facts ≤10 ключей), verbatim + фраза-контекст на границе фаз.
- Финальный отчёт Phase 4: таблица «тест → статус», «пилот → статус → артефакты», вывод V-pilot-1, телеметрия S1/S5, список отклонений/багов (если есть) — вход для Phase 5 (CHANGELOG, коммит через агента git-commit).
