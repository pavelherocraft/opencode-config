#!/usr/bin/env node
/**
 * test-workflow-enforcement.mjs - runtime tests for the primary-agent HARD
 * GATE of workflow-enforcement.ts (PRIMARY_AGENT_ALLOWED_TOOLS):
 *
 *   orchestrator / plankestrator MAY inspect (task/read/glob/grep) but MUST
 *   NOT act (edit/write/bash/webfetch/todowrite/question/patch).
 *
 * The plugin is loaded as a real ES module (Node type-stripping, the only
 * import is type-only) and driven through its hooks with a mocked client.
 * No live config is modified - the plugin runs entirely in-process.
 *
 * v7 (Multi-Phase MVP): + message.updated simulation (confirmation gate,
 * MULTI_PHASE JSON), task-depth pairing helpers and tests T9-T26.
 * v7.1 (P0 event-shape fix): the simulation now matches opencode 1.18.34 —
 * session identity arrives on session.updated(info.agent); message text arrives
 * via message.part.updated (finalized by message.updated finish/time.completed);
 * T27 guards the reasoning-part filter.
 *
 * Plugin path resolution (first hit wins):
 *   1. WORKFLOW_PLUGIN env var
 *   2. live:  ~/.config/opencode/plugins/workflow-enforcement.ts
 *   3. repo:  ./workflow-enforcement.ts (next to this test)
 *
 * Usage:
 *   node test-workflow-enforcement.mjs
 *
 * Exit codes: 0 all passed, 1 failures, 2 environment error.
 */

import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const home = process.env.USERPROFILE || process.env.HOME
const here = path.dirname(fileURLToPath(import.meta.url))
const candidates = [
  process.env.WORKFLOW_PLUGIN || '',
  path.join(home, '.config', 'opencode', 'plugins', 'workflow-enforcement.ts'),
  path.join(here, 'workflow-enforcement.ts'),
]
const pluginPath = candidates.find((p) => p && existsSync(p))
if (!pluginPath) {
  console.error('FAIL: workflow-enforcement.ts not found in any candidate location')
  process.exit(2)
}
console.log(`PLUGIN: ${pluginPath}`)

let WorkflowEnforcement
let __testPipelineState
try {
  ({ WorkflowEnforcement, __testPipelineState } = await import(pathToFileURL(pluginPath).href))
} catch (e) {
  console.error(`FAIL: cannot import plugin: ${e?.message || e}`)
  process.exit(2)
}

let pass = 0
let fail = 0
function check(name, condition, detail = '') {
  if (condition) {
    pass += 1
    console.log(`PASS: ${name}`)
  } else {
    fail += 1
    console.log(`FAIL: ${name} -- ${detail}`)
  }
}

const logs = []
const client = { app: { log: async ({ body }) => { logs.push(String(body?.message ?? '')) } } }

const plugin = await WorkflowEnforcement({ client, $: {} })

let currentSessionID = 's-orchestrator'

async function lockSession(agent) {
  currentSessionID = `s-${agent}`
  // opencode 1.18.34 shape: session.created fires BEFORE the agent is bound
  // (its info has no agent field); the authoritative agent arrives on the NEXT
  // session.updated (info.agent). The permission rule list ({permission,pattern,
  // action}) must NOT be misread as built-in Plan mode.
  const permission = [
    { permission: 'question', pattern: '*', action: 'deny' },
    { permission: 'plan_enter', pattern: '*', action: 'deny' },
    { permission: 'plan_exit', pattern: '*', action: 'deny' },
  ]
  await plugin.event({
    event: {
      type: 'session.created',
      properties: { sessionID: currentSessionID, info: { id: currentSessionID, permission } },
    },
  })
  await plugin.event({
    event: {
      type: 'session.updated',
      properties: { sessionID: currentSessionID, info: { id: currentSessionID, agent, permission } },
    },
  })
}

async function tryTool(tool, args = {}) {
  try {
    await plugin['tool.execute.before']({ tool, args, sessionID: 's1' }, { args })
    return { ok: true }
  } catch (e) {
    return { ok: false, message: String(e?.message ?? e) }
  }
}

// ============================================================================
// v7.1 helpers — opencode 1.18.34 event-shape simulation
// (message text via message.part.updated; message finalized via message.updated)
// ============================================================================
let msgSeq = 0

/** Simulate one message turn on the 1.18.34 wire:
 *   1. message.part.updated (part.type="text", cumulative part.text)
 *   2. message.updated with properties.info (finish="stop" + time.completed for
 *      assistant turns; user messages carry no finish — matching the live dump).
 *  `{id}` re-fires the SAME messageID (streaming-simulation: gate stays armed). */
async function sendMessage(role, content, { id } = {}) {
  const mid = id || `m${++msgSeq}`
  const pid = `prt-${mid}`
  if (content !== undefined && content !== null) {
    await plugin.event({
      event: {
        type: 'message.part.updated',
        properties: {
          sessionID: currentSessionID,
          part: { id: pid, type: 'text', text: content, messageID: mid, sessionID: currentSessionID },
        },
      },
    })
  }
  const info = { id: mid, role, sessionID: currentSessionID }
  if (role !== 'user') {
    info.finish = 'stop'
    info.time = { created: Date.now(), completed: Date.now() }
  }
  await plugin.event({
    event: { type: 'message.updated', properties: { sessionID: currentSessionID, info } },
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
 *  (нужно для T21: reviewer-сообщения валидны только при depth>0).
 *  message нормализуется в '' на успехе — check()-детейлы вычисляются eagerly. */
async function tryTask(subagent, { keepDepth = false } = {}) {
  const args = { subagent_type: subagent, description: 'd', prompt: 'p' }
  const r = await tryTool('task', args)
  if (r.ok && r.message === undefined) r.message = ''
  if (r.ok && !keepDepth) await endTask(args)
  return r
}

/** Reviewer-JSON субагента (отправлять МЕЖДУ tryTask(keepDepth) и endTask).
 *  agent ∈ SEVERITY_AGENTS = dev-reviewer | consistency-checker | advisor. */
function reviewerMsg(agent, severity, text) {
  return '```json\n' + JSON.stringify({ agent, severity, findings: [{ text, severity }] }) + '\n```'
}

/** Probe gate 9.0в: 'clean' | текст throw (CONSUME-ONCE: флаг сбрасывается!).
 *  После первого успешного Task read блокирован — это НЕ violation. */
async function probeGate() {
  const r = await tryTool('read')
  if (r.ok) return 'clean'
  if (r.message.includes('PRIMARY AGENT FORBIDDEN')) return 'clean'
  return r.message
}

function hasLog(substr) { return logs.some((m) => m.includes(substr)) }
function countLog(substr) { return logs.filter((m) => m.includes(substr)).length }
async function newSession(agent = 'orchestrator') { await lockSession(agent); logs.length = 0 }
const clonePhases = (ph) => ph.map((p) => ({ ...p, depends_on: [...p.depends_on] }))

const FORBIDDEN = ['edit', 'write', 'bash', 'webfetch', 'todowrite', 'question', 'patch']
const ALLOWED = ['read', 'glob', 'grep']

// ============================================================================
// v7 fixtures — canonical PIPELINE TABLE rows (validatePipeline keys)
// ============================================================================
const ROW1 = ['bugfix-triage']                                             // BUGFIX-null-null (+variants)
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
// plan_exists:false ОБЯЗАТЕЛЕН с самого начала — DEV-null-null fail-closed (deviation D).
const PH_DEV_FIRST = [
  { id: 'P1', type: 'DEV', complexity: null, plan_exists: false, goal: 'add feature Y', depends_on: [] },
  { id: 'P2', type: 'BUGFIX', complexity: null, plan_exists: null, goal: 'fix bug X', depends_on: ['P1'] },
]

/** Валидный MULTI_PHASE-скелет со ВСЕМИ required-полями orchestrator. */
function mp(over = {}) {
  return {
    agent: 'orchestrator', type: 'MULTI_PHASE', complexity: null, plan_exists: null,
    plan_source: null, goal: 'multi-phase task', next_agent: null, pipeline: [],
    state: null, phases: PH2, current_phase: null, ...over,
  }
}

// ============================================================================
// T1: identity lock on session.created (agent=orchestrator)
// ============================================================================
logs.length = 0
await lockSession('orchestrator')
check('T1 identity locked as orchestrator',
  logs.some((m) => m.includes('agent LOCKED: orchestrator')),
  logs.join(' | '))

// ============================================================================
// T2: action tools are BLOCKED for the locked primary agent
// ============================================================================
for (const tool of FORBIDDEN) {
  const r = await tryTool(tool, { filePath: 'x.txt', command: 'dir' })
  check(`T2 ${tool} blocked for orchestrator`,
    !r.ok && r.message.includes('PRIMARY AGENT FORBIDDEN ACTION TOOL'),
    r.ok ? 'NOT blocked' : `unexpected error: ${r.message.split('\n')[0]}`)
}

// ============================================================================
// T3: inspection tools are ALLOWED for the locked primary agent
// ============================================================================
for (const tool of ALLOWED) {
  const r = await tryTool(tool, { filePath: 'x.txt' })
  check(`T3 ${tool} allowed for orchestrator`, r.ok, r.message)
}

// ============================================================================
// T4: task delegation is allowed (auxiliary identity-probe target)
// ============================================================================
{
  const args = { subagent_type: 'orchestrator-identity-probe', prompt: 'probe' }
  const r = await tryTool('task', args)
  check('T4 task (orchestrator-identity-probe) allowed', r.ok, r.message)
  await plugin['tool.execute.after']({ tool: 'task', args }, { args })
}

// ============================================================================
// T5: every violation is logged by the plugin
// ============================================================================
check('T5 violation logged for each blocked tool',
  logs.filter((m) => m.includes('PRIMARY AGENT ACTION TOOL VIOLATION')).length >= FORBIDDEN.length,
  `logged ${logs.filter((m) => m.includes('PRIMARY AGENT ACTION TOOL VIOLATION')).length}`)

// ============================================================================
// T6: the second primary agent (plankestrator) is blocked the same way
// ============================================================================
await lockSession('plankestrator')
{
  const r = await tryTool('edit')
  check('T6 edit blocked for plankestrator',
    !r.ok && r.message.includes('PRIMARY AGENT FORBIDDEN ACTION TOOL'),
    r.ok ? 'NOT blocked' : r.message.split('\n')[0])
}

// ============================================================================
// T7: a NON-primary agent session is NOT blocked by the primary gate
// ============================================================================
await lockSession('worker')
{
  const r = await tryTool('edit', { filePath: 'x.txt' })
  check('T7 edit NOT blocked for non-primary agent (identityLocked=false)', r.ok, r.message)
  const r2 = await tryTool('bash', { command: 'dir' })
  check('T7 bash NOT blocked for non-primary agent', r2.ok, r2.message)
}

// ============================================================================
// T8: reset-then-relock: after a non-primary session, re-locking as
//     orchestrator restores the block (state must not leak across sessions)
// ============================================================================
await lockSession('orchestrator')
{
  const r = await tryTool('bash')
  check('T8 edit/bash blocked again after re-lock',
    !r.ok && r.message.includes('PRIMARY AGENT FORBIDDEN ACTION TOOL'),
    r.ok ? 'NOT blocked' : r.message.split('\n')[0])
}

// ============================================================================
// T9 — Confirmation gate: AWAITING turn is VALID + same-turn Task blocked
// ============================================================================
await newSession()
{
  const awaitId = await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
    { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }))
  check('T9a AWAITING turn is VALID (no deferred flags)', await probeGate() === 'clean', logs.join(' | '))
  check('T9b gate armed log', hasLog('Task calls blocked until the user replies'), logs.join(' | '))
  const r = await tryTask('bugfix-triage')
  check('T9c same-turn Task blocked',
    !r.ok && r.message.includes('AWAITING USER CONFIRMATION'),
    r.ok ? 'NOT blocked' : r.message.split('\n')[0])
  check('T9d gate log', hasLog('CONFIRMATION GATE — Task blocked while AWAITING_CONFIRMATION'), logs.join(' | '))
  await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
    { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }), { id: awaitId })
  const r2 = await tryTask('bugfix-triage')
  check('T9e re-fire same messageID keeps gate armed',
    !r2.ok && r2.message.includes('AWAITING USER CONFIRMATION'),
    r2.ok ? 'NOT blocked' : r2.message.split('\n')[0])
}

// ============================================================================
// T10 — Gate cleared by a user-role message (same session as T9)
// ============================================================================
{
  await sendMessage('user', 'да')
  check('T10a USER RESPONSE log', hasLog('USER RESPONSE RECEIVED — confirmation gate cleared'), logs.join(' | '))
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
    { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
  const r = await tryTask('bugfix-triage')
  check('T10b Task allowed after user reply', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T10b — Gate fallback: a NEW assistant messageID without a user-role message
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' })))
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
  check('T10b-1 fallback log', hasLog('user reply implied'), logs.join(' | '))
  const r = await tryTask('bugfix-triage')
  check('T10b-2 Task allowed via messageID fallback', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T11 — state field with type≠MULTI_PHASE → INVALID JSON (not gate-armed)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg({
    agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE', plan_exists: false, plan_source: null,
    goal: 'single dev', next_agent: 'worker', pipeline: ['worker', 'utility'],
    state: 'AWAITING_CONFIRMATION',
  }))
  check('T11b confirmation gate NOT armed for non-MULTI_PHASE',
    !hasLog('Task calls blocked until the user replies'), logs.join(' | '))
  const p = await probeGate()
  check('T11a INVALID JSON via deferred gate',
    p !== 'clean' && p.includes('INVALID JSON OUTPUT') && p.includes('state field is only valid with type=MULTI_PHASE'),
    p === 'clean' ? 'gate clean (state accepted — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T12 — Executing MULTI_PHASE turn: per-phase validation (key BUGFIX-null-null)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
    { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
  check('T12a no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), logs.join(' | '))
  const r = await tryTask('bugfix-triage')
  check('T12b executing turn Task ok', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T13 — In-phase BUGFIX continuation (MP-2), same session as T12
// ============================================================================
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' }),
    { ack: '→ PHASE 1/2 (P1): DELEGATED to worker for: fix bug X' }))
  check('T13a MP-2 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-2 in-phase BUGFIX continuation'), logs.join(' | '))
  const r = await tryTask('worker')
  check('T13b continuation Task ok', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T14 — Provisional trap fixed: illegal swap inside a frozen phase
// ============================================================================
await newSession()
{
  const PHR = [
    { id: 'P1', type: 'DEV', complexity: 'COMPLEX', plan_exists: false, goal: 'add feature Y', depends_on: [] },
    { id: 'P2', type: 'BUGFIX', complexity: null, plan_exists: null, goal: 'fix bug X', depends_on: ['P1'] },
  ]
  await sendMessage('assistant', orchMsg(mp({ phases: PHR, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' })))
  const r1 = await tryTask('dev-planner')
  check('T14a Turn1 lock ok', r1.ok, r1.message.split('\n')[0])
  await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PHR), current_phase: 'P1',
    pipeline: ['worker', 'utility'], next_agent: 'worker' })))
  const p = await probeGate()
  // v8: an invalid incoming pipeline is now caught by the pipeline-TABLE
  // validation BEFORE the state block (deadlock fix) — the swap is still
  // blocked, just with the more fundamental violation code.
  check('T14b illegal swap blocked (F-4 provisional does NOT apply)',
    p !== 'clean' && p.includes('WORKFLOW VIOLATION') &&
      (p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)') || p.includes('PIPELINE VALIDATION FAILED')),
    p === 'clean' ? 'gate clean (swap allowed — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T15 — Legal phase transition (MP-5) after P1 runs to completion
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
  await tryTask('bugfix-triage')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' })))
  await tryTask('worker')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'utility' })))
  await tryTask('utility')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
    { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
  check('T15a MP-5 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-5 phase transition'), logs.join(' | '))
  const r = await tryTask('dev-planner')
  check('T15b transition Task ok', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T15b — Final turn clean (terminal shape inside the MULTI_PHASE branch)
// ============================================================================
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: [], next_agent: null })))
  check('T15b-1 no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), logs.join(' | '))
  check('T15b-2 no INVALID JSON OUTPUT', !hasLog('INVALID JSON OUTPUT'), logs.join(' | '))
  check('T15b-3 no DEFERRED VIOLATION', !hasLog('DEFERRED VIOLATION ENFORCED'), logs.join(' | '))
  check('T15b-4 probe clean', await probeGate() === 'clean', logs.join(' | '))
}

// ============================================================================
// T16 — Transition-skip (P1→P3) forbidden, identical chains (DEVOPS→DEVOPS)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ phases: PH3, current_phase: 'P1', pipeline: DEVOPS_ROW, next_agent: 'devops-agent' })))
  const r1 = await tryTask('devops-agent')
  check('T16a P1 Turn1 ok', r1.ok, r1.message.split('\n')[0])
  await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PH3), current_phase: 'P3',
    pipeline: DEVOPS_ROW, next_agent: 'devops-agent' })))
  const p = await probeGate()
  check('T16b skip transition (P1→P3) blocked',
    p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'),
    p === 'clean' ? 'gate clean (skip allowed — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T17 — Phases tampering on a legal transition (goal changed)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ phases: PH3, current_phase: 'P1', pipeline: DEVOPS_ROW, next_agent: 'devops-agent' })))
  await tryTask('devops-agent')
  const tampered = clonePhases(PH3); tampered[1].goal = 'TAMPERED goal'
  await sendMessage('assistant', orchMsg(mp({ phases: tampered, current_phase: 'P2',
    pipeline: ['worker', 'utility'], next_agent: 'worker' })))
  const p = await probeGate()
  check('T17 phases tampering blocked',
    p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'),
    p === 'clean' ? 'gate clean (tamper allowed — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T18 — Structural phases violations → fail-closed (fresh session each)
// ============================================================================
{
  const cases = [
    { name: 'T18a 4 phases out of range', gate: true,
      phases: [...clonePhases(PH3), { id: 'P4', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'monitor', depends_on: ['P3'] }],
      substr: 'out of range [2..3]' },
    { name: 'T18b duplicate phase id', gate: false,
      phases: [clonePhases(PH3)[0], { ...clonePhases(PH3)[0] }],
      substr: 'duplicate phase id' },
    { name: 'T18c forward depends_on ref', gate: false,
      phases: (() => { const ph = clonePhases(PH3); ph[0].depends_on = ['P2']; return ph })(),
      substr: 'depends_on must be []' },
    { name: 'T18d two SUPERCOMPLEX phases', gate: false,
      phases: [
        { id: 'P1', type: 'DEV', complexity: 'SUPERCOMPLEX', plan_exists: true, goal: 'big migration', depends_on: [] },
        { id: 'P2', type: 'DEV', complexity: 'SUPERCOMPLEX', plan_exists: true, goal: 'another migration', depends_on: ['P1'] },
      ],
      substr: 'at most ONE SUPERCOMPLEX' },
    { name: 'T18e two roots (P2 deps emptied)', gate: false,
      phases: (() => { const ph = clonePhases(PH3); ph[1].depends_on = []; return ph })(),
      substr: 'depends_on must be ["P1"]' },
  ]
  for (const c of cases) {
    await newSession()
    await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION', phases: c.phases })))
    const structLogged = hasLog('PIPELINE VALIDATION FAILED')
    if (c.gate)
      check('T18a+ gate NOT armed on invalid phases', !hasLog('Task calls blocked until the user replies'), logs.join(' | '))
    const p = await probeGate()
    check(c.name, p !== 'clean' && p.includes(c.substr) && structLogged,
      p === 'clean' ? 'gate clean (structure accepted — BUG)' : `${p.split('\n')[0]} | structLogged=${structLogged}`)
  }
}

// ============================================================================
// T19 — CANCELLED shape (defensive disarm; no violation flags)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' })))
  await sendMessage('user', 'отмена')
  await sendMessage('assistant', orchMsg(mp({ state: 'CANCELLED' })))
  check('T19a no DEFERRED VIOLATION', !hasLog('DEFERRED VIOLATION ENFORCED'), logs.join(' | '))
  check('T19b no PIPELINE VALIDATION FAILED', !hasLog('PIPELINE VALIDATION FAILED'), logs.join(' | '))
  check('T19c probe clean (gate disarmed)', await probeGate() === 'clean', logs.join(' | '))
}

// ============================================================================
// T20 — In-phase Auto-DOCS hook (MP-4) after the phase's final step
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
  await tryTask('bugfix-triage')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' })))
  await tryTask('worker')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'utility' })))
  await tryTask('utility')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: HOOK, next_agent: 'docs-writer' }),
    { ack: '→ PHASE 1/2 (P1): DELEGATED to docs-writer for: docs update' }))
  check('T20a MP-4 allowed', hasLog('MULTI_PHASE MUTATION ALLOWED — MP-4 in-phase Auto-DOCS hook'), logs.join(' | '))
  const r = await tryTask('docs-writer')
  check('T20b hook Task ok', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T21 — blockerStop reset on a legal MP-5 transition (two-part: the
//       consume-once gate forces re-arming via FRESH blockers)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })))
  // Part A — 3 reviewer blockers inside the bugfix-triage Task → blockerStop
  const argsA = { subagent_type: 'bugfix-triage', description: 'd', prompt: 'p' }
  const tA = await tryTask('bugfix-triage', { keepDepth: true })
  check('T21a Part A Task ok (depth held)', tA.ok, tA.message.split('\n')[0])
  for (let i = 1; i <= 3; i++)
    await sendMessage('assistant', reviewerMsg('dev-reviewer', 'blocker', `blocking issue ${i}`))
  await endTask(argsA)
  check('T21b escalation counted 3/3', hasLog('BLOCKER ESCALATION COUNTED — 3/3'), logs.join(' | '))
  const pA = await probeGate()
  check('T21c gate blocks after 3 blockers (BLOCKER STOP)',
    pA !== 'clean' && pA.includes('BLOCKER STOP AFTER 3'),
    pA === 'clean' ? 'gate clean (blockerStop not enforced)' : pA.split('\n')[0])
  // Part B — the MP-2 continuation RESETS the escalation counter (new loop
  // context), so blockerStop must be re-armed by 3 FRESH blockers before the
  // MP-5 transition can demonstrably reset it.
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' })))
  const argsB = { subagent_type: 'worker', description: 'd', prompt: 'p' }
  const tB = await tryTask('worker', { keepDepth: true })
  check('T21d Part B continuation Task ok (MP-2, depth held)', tB.ok, tB.message.split('\n')[0])
  for (let i = 4; i <= 6; i++)
    await sendMessage('assistant', reviewerMsg('dev-reviewer', 'blocker', `blocking issue ${i}`))
  await endTask(argsB)
  check('T21e blockerStop re-armed (second 3/3 count)',
    countLog('BLOCKER ESCALATION COUNTED — 3/3') >= 2, logs.join(' | '))
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
    { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
  check('T21f BLOCKERSTOP RESET logged on MP-5', hasLog('BLOCKERSTOP RESET — legal multi-phase transition'), logs.join(' | '))
  const r = await tryTask('dev-planner')
  check('T21g Task ok after reset', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T22 — Phase refinement once (MP-1/MP-3) then a second refinement blocked
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PH_DEV_FIRST), current_phase: 'P1',
    pipeline: ['dev-planner'], next_agent: 'dev-planner' })))
  const rA = await tryTask('dev-planner')
  check('T22a Turn A (decomposition dispatch) ok', rA.ok, rA.message.split('\n')[0])
  const phB = clonePhases(PH_DEV_FIRST); phB[0].complexity = 'COMPLEX'
  await sendMessage('assistant', orchMsg(mp({ phases: phB, current_phase: 'P1', plan_source: 'DECOMPOSITION',
    pipeline: ROW5, next_agent: 'dev-planner' })))
  check('T22b refinement allowed (MP-1/MP-3)', hasLog('MP-1/MP-3 phase refinement / DECOMPOSITION'), logs.join(' | '))
  const rB = await tryTask('dev-planner')
  check('T22c Turn B Task ok (isLoopback)', rB.ok, rB.message.split('\n')[0])
  const phC = clonePhases(phB); phC[0].complexity = 'SIMPLE'
  await sendMessage('assistant', orchMsg(mp({ phases: phC, current_phase: 'P1',
    pipeline: ['worker', 'utility'], next_agent: 'worker' })))
  const p = await probeGate()
  check('T22d second refinement blocked',
    p !== 'clean' && p.includes('PIPELINE IMMUTABLE (MULTI_PHASE)'),
    p === 'clean' ? 'gate clean (double refinement allowed — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T23 — SUPERCOMPLEX phase: per-step re-emission + plan_exists requirement
// ============================================================================
await newSession()
{
  const PHS = [
    { id: 'P1', type: 'DEV', complexity: 'SUPERCOMPLEX', plan_exists: true, goal: 'big migration', depends_on: [] },
    { id: 'P2', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'deploy', depends_on: ['P1'] },
  ]
  await sendMessage('assistant', orchMsg(mp({ phases: PHS, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' }),
    { ack: '→ PHASE 1/2 (P1), STEP 1/5 (S-1): DELEGATED to dev-planner' }))
  const r1 = await tryTask('dev-planner')
  check('T23a SUPERCOMPLEX phase turn ok (key DEV-SUPERCOMPLEX-true)', r1.ok, r1.message.split('\n')[0])
  await sendMessage('assistant', orchMsg(mp({ phases: clonePhases(PHS), current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-professor' }),
    { ack: '→ PHASE 1/2 (P1), STEP 2/5 (S-2): DELEGATED to dev-professor' }))
  check('T23b no violation on per-step re-emission',
    !hasLog('DEFERRED VIOLATION ENFORCED') && !hasLog('PIPELINE IMMUTABLE'), logs.join(' | '))
  const r2 = await tryTask('dev-professor')
  check('T23c per-step Task ok', r2.ok, r2.message.split('\n')[0])
}
await newSession()
{
  const PHX = [
    { id: 'P1', type: 'DEV', complexity: 'SUPERCOMPLEX', plan_exists: null, goal: 'big migration', depends_on: [] },
    { id: 'P2', type: 'DEVOPS', complexity: null, plan_exists: null, goal: 'deploy', depends_on: ['P1'] },
  ]
  await sendMessage('assistant', orchMsg(mp({ phases: PHX, current_phase: 'P1', pipeline: ROW5, next_agent: 'dev-planner' })))
  const p = await probeGate()
  check('T23d SUPERCOMPLEX requires plan_exists=true (executing)',
    p !== 'clean' && p.includes('SUPERCOMPLEX requires plan_exists=true'),
    p === 'clean' ? 'gate clean (accepted — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T24 — Ack audit: v7 forms 7–9 (and legacy form 1) produce no warn
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' }),
    { ack: '→ PHASE 1/2 (P1): DELEGATED to bugfix-triage for: fix bug X' }))
  check('T24a form 7 no warn', !hasLog('ACK FORMAT INVALID'), logs.join(' | '))
  await tryTask('bugfix-triage')
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1_SIMPLE, next_agent: 'worker' }),
    { ack: '→ PHASE 1/2 (P1), STEP 2/5 (S-2): DELEGATED to worker' }))
  check('T24b form 8 no warn', !hasLog('ACK FORMAT INVALID'), logs.join(' | '))
}
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ state: 'AWAITING_CONFIRMATION' }),
    { ack: '→ PHASE PLAN AWAITING CONFIRMATION (2 phases)' }))
  check('T24c form 9 no warn', !hasLog('ACK FORMAT INVALID'), logs.join(' | '))
}
await newSession()
{
  await sendMessage('assistant', orchMsg({
    agent: 'orchestrator', type: 'BUGFIX', complexity: null, plan_exists: null,
    plan_source: null, goal: 'fix bug X', next_agent: 'bugfix-triage', pipeline: ROW1,
  }))
  check('T24d legacy form 1 no warn', !hasLog('ACK FORMAT INVALID'), logs.join(' | '))
}

// ============================================================================
// T25 — Resume in a fresh session (Turn-1 lock with currentPhaseIdx > 0)
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P2', pipeline: ROW5, next_agent: 'dev-planner' }),
    { ack: '→ PHASE 2/2 (P2): DELEGATED to dev-planner for: add feature Y' }))
  check('T25a RESUME warn logged', hasLog('MULTI_PHASE RESUME DETECTED'), logs.join(' | '))
  const r = await tryTask('dev-planner')
  check('T25b resume Turn1 lock + Task ok', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T26 — Single-phase regression (v7 must not break pre-v7 scenarios)
// ============================================================================
await newSession()
{
  // (a) BUGFIX Turn 1 + continuation
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'bugfix-triage', pipeline: ROW1 }))
  const r1 = await tryTask('bugfix-triage')
  check('T26a BUGFIX Turn1 Task ok', r1.ok, r1.message.split('\n')[0])
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'worker', pipeline: ROW1_SIMPLE }))
  const r2 = await tryTask('worker')
  check('T26a2 BUGFIX continuation Task ok', r2.ok, r2.message.split('\n')[0])
  // (g) cross-routing prevention (identity lock active); the JSON itself must
  // stay step-consistent (ROW1_SIMPLE step 2 = utility) so the deferred gate
  // does not mask the routing throw.
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'utility', pipeline: ROW1_SIMPLE }))
  const rg = await tryTask('plan-writer-simple')
  check('T26g cross-routing blocked (identity lock active)',
    !rg.ok && rg.message.includes('ROUTING TABLE ENFORCEMENT (identity lock active)'),
    rg.ok ? 'NOT blocked' : rg.message.split('\n')[0])
}
await newSession()
{
  // (b) DECOMPOSITION A/B (Q3 COMPLEX outcome: plan_exists stays false)
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: null,
    plan_exists: false, plan_source: null, goal: 'add feature Y', next_agent: 'dev-planner',
    pipeline: ['dev-planner'] }))
  const rA = await tryTask('dev-planner')
  check('T26b DECOMPOSITION Turn A ok (provisional)', rA.ok, rA.message.split('\n')[0])
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'COMPLEX',
    plan_exists: false, plan_source: null, goal: 'add feature Y', next_agent: 'dev-planner',
    pipeline: ROW5 }))
  const rB = await tryTask('dev-planner')
  check('T26b2 DECOMPOSITION Turn B ok (F-4 provisional replacement)', rB.ok, rB.message.split('\n')[0])
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'COMPLEX',
    plan_exists: false, plan_source: 'DECOMPOSITION', goal: 'add feature Y', next_agent: 'dev-planner',
    pipeline: ROW5 }))
  const p = await probeGate()
  check('T26b3 plan_source requires plan_exists=true (negative)',
    p !== 'clean' && p.includes('plan_source requires plan_exists=true'),
    p === 'clean' ? 'gate clean (accepted — BUG)' : p.split('\n')[0])
}
await newSession()
{
  // (c) Auto-DOCS hook single-phase (F-12, type DOCS after a BUGFIX chain)
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'bugfix-triage', pipeline: ROW1 }))
  await tryTask('bugfix-triage')
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'worker', pipeline: ROW1_SIMPLE }))
  await tryTask('worker')
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', next_agent: 'utility', pipeline: ROW1_SIMPLE }))
  await tryTask('utility')
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DOCS', complexity: 'SIMPLE',
    plan_exists: null, plan_source: null, goal: 'docs update', next_agent: 'docs-writer', pipeline: HOOK }))
  const r = await tryTask('docs-writer')
  check('T26c Auto-DOCS hook (type DOCS) ok', r.ok, r.message.split('\n')[0])
}
await newSession()
{
  // (d) nit-skip after a Turn-1 row-5 lock
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'COMPLEX',
    plan_exists: false, plan_source: null, goal: 'add feature Y', next_agent: 'dev-planner', pipeline: ROW5 }))
  await tryTask('dev-planner')
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE',
    plan_exists: false, plan_source: null, goal: 'add feature Y', severity: 'nit',
    next_agent: 'worker', pipeline: ['worker', 'utility'] }))
  check('T26d nit-skip no IMMUTABLE', !hasLog('PIPELINE IMMUTABLE'), logs.join(' | '))
  const r = await tryTask('worker')
  check('T26d2 nit-skip Task ok', r.ok, r.message.split('\n')[0])
}
await newSession()
{
  // (e) F-4 provisional single-phase stays ALIVE (v7 fix scoped to MULTI_PHASE)
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: null,
    plan_exists: false, plan_source: null, goal: 'add feature Y', next_agent: 'dev-planner',
    pipeline: ['dev-planner'] }))
  await tryTask('dev-planner')
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE',
    plan_exists: false, plan_source: null, goal: 'add feature Y', next_agent: 'worker',
    pipeline: ['worker', 'utility'] }))
  const r = await tryTask('worker')
  check('T26e F-4 provisional replacement ok (single-phase untouched)', r.ok, r.message.split('\n')[0])
}
await newSession()
{
  // (f) severity gate: invalid severity value in the PRIMARY JSON
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'BUGFIX', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix bug X', severity: 'critical',
    next_agent: 'bugfix-triage', pipeline: ROW1 }))
  const p = await probeGate()
  check('T26f invalid severity rejected',
    p !== 'clean' && p.includes('INVALID SEVERITY'),
    p === 'clean' ? 'gate clean (accepted — BUG)' : p.split('\n')[0])
}

// ============================================================================
// T27 — reasoning filter (B2): part.type="reasoning" (and its field="text"
// deltas) MUST be ignored; only part.type="text" feeds JSON extraction. A decoy
// ```json fence placed in a reasoning part would be picked FIRST by
// extractJSONFromMessage if reasoning leaked into the buffer.
// ============================================================================
await newSession()
{
  const mid = `m${++msgSeq}`
  await plugin.event({
    event: {
      type: 'message.part.updated',
      properties: {
        sessionID: currentSessionID,
        part: {
          id: `prt-${mid}-r`, type: 'reasoning',
          text: '```json\n{"agent":"orchestrator","type":"NOPE"}\n```',
          messageID: mid, sessionID: currentSessionID,
        },
      },
    },
  })
  await sendMessage('assistant', orchMsg(mp({ current_phase: 'P1', pipeline: ROW1, next_agent: 'bugfix-triage' })), { id: mid })
  check('T27a reasoning ignored (turn stays clean)', await probeGate() === 'clean', logs.join(' | '))
  const r = await tryTask('bugfix-triage')
  check('T27b Task ok despite decoy reasoning part', r.ok, r.message.split('\n')[0])
}

// ============================================================================
// T28 — deadlock regression (v8): an INVALID Turn-1 pipeline must NOT be
// locked as the baseline, otherwise the corrective message hits Phase 17.2
// (pipelineImmutable) and no recovery can clear it — a permanent deadlock.
// ============================================================================
await newSession()
{
  // (a) Turn 1 — orchestrator emits an INVALID pipeline
  // (DEV-SIMPLE-false expects [worker, utility]).
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE',
    plan_exists: false, plan_source: null, goal: 'refactor', next_agent: 'worker',
    pipeline: ['worker', 'utility', 'git-commit'] }))
  const p = await probeGate()
  check('T28a invalid pipeline blocked (PIPELINE VALIDATION FAILED; state NOT locked)',
    p !== 'clean' && p.includes('PIPELINE VALIDATION FAILED'),
    p === 'clean' ? 'gate clean (invalid pipeline accepted — BUG)' : p.split('\n')[0])
  // (b) Turn 2 — corrected pipeline must be ACCEPTED. If the invalid pipeline
  // had been locked as the Turn-1 baseline, this turn would hit
  // PIPELINE IMMUTABLE and deadlock the session.
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE',
    plan_exists: false, plan_source: null, goal: 'refactor', next_agent: 'worker',
    pipeline: ['worker', 'utility'] }))
  const r = await tryTask('worker')
  check('T28b corrected pipeline Task allowed (no IMMUTABLE deadlock)',
    r.ok && !hasLog('PIPELINE IMMUTABLE'),
    r.ok ? 'unexpected: ' + logs.join(' | ') : r.message.split('\n')[0])
}
// (c) self-heal — inject a POISONED lock directly into pipelineState (no valid
// event sequence can produce one: simulates a session locked by a pre-fix
// build). The next valid pipeline must RECAPTURE, not throw IMMUTABLE.
// currentStep=-1 → the healing turn re-announces pipeline[0] (effectiveStep 0).
if (__testPipelineState) {
  await newSession()
  __testPipelineState.set('orchestrator', {
    pipeline: ['worker', 'utility', 'git-commit'], currentStep: -1, provisional: false,
    type: 'DEV', complexity: 'SIMPLE', planExists: false,
  })
  logs.length = 0
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEV', complexity: 'SIMPLE',
    plan_exists: false, plan_source: null, goal: 'refactor', next_agent: 'worker',
    pipeline: ['worker', 'utility'] }))
  const r = await tryTask('worker')
  check('T28c self-heal recapture on poisoned baseline (no IMMUTABLE)',
    r.ok && hasLog('SELF-HEAL RECAPTURE') && !hasLog('PIPELINE IMMUTABLE'),
    r.ok ? 'unexpected: ' + logs.join(' | ') : r.message.split('\n')[0])
} else {
  check('T28c self-heal seam available', false, 'plugin export __testPipelineState missing')
}

// ============================================================================
// T29 — CUSTOM PIPELINE COMPOSITION (v8): pipeline_source_rows = the EXACT
// concatenation of canonical PIPELINE TABLE rows — a lighter alternative to
// MULTI_PHASE (no confirmation round-trip; the explicit user request is the
// mandate). type/complexity/plan_exists = the FIRST row's values.
// ============================================================================
await newSession()
{
  const composed = [...DEVOPS_ROW, 'worker', 'utility']   // DEVOPS-null-null + DEV-SIMPLE-false
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEVOPS', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix CI and update the README', next_agent: 'devops-agent',
    pipeline: composed, pipeline_source_rows: ['DEVOPS-null-null', 'DEV-SIMPLE-false'] }))
  const r = await tryTask('devops-agent')
  const locked = __testPipelineState?.get('orchestrator')
  check('T29 composed pipeline allowed + locked (no VALIDATION FAILED / IMMUTABLE)',
    r.ok && !hasLog('PIPELINE VALIDATION FAILED') && !hasLog('PIPELINE IMMUTABLE') &&
      !!locked && JSON.stringify(locked.pipeline) === JSON.stringify(composed) &&
      locked.type === 'DEVOPS' && locked.complexity === null && locked.planExists === null,
    r.ok ? `lock: ${JSON.stringify(locked)}` : r.message.split('\n')[0])
}

// ============================================================================
// T30a — composition mismatch: pipeline_source_rows intact, pipeline agents
// permuted → BLOCKED with the concatenation error (state NOT locked).
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEVOPS', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix CI and update the README', next_agent: 'devops-agent',
    pipeline: ['devops-agent', 'devops-reviewer', 'utility', 'worker'],
    pipeline_source_rows: ['DEVOPS-null-null', 'DEV-SIMPLE-false'] }))
  const r = await tryTask('devops-agent')
  check('T30a permuted pipeline rejected (concatenation mismatch; Task BLOCKED)',
    !r.ok && r.message.includes('PIPELINE VALIDATION FAILED') &&
      r.message.includes('does not match the concatenation of pipeline_source_rows'),
    r.ok ? 'NOT blocked' : r.message.split('\n')[0])
}

// ============================================================================
// T30b — composition with an UNKNOWN row key → BLOCKED ("unknown row(s)").
// ============================================================================
await newSession()
{
  await sendMessage('assistant', orchMsg({ agent: 'orchestrator', type: 'DEVOPS', complexity: null,
    plan_exists: null, plan_source: null, goal: 'fix CI and update the README', next_agent: 'devops-agent',
    pipeline: ['devops-agent', 'devops-reviewer', 'worker', 'utility'],
    pipeline_source_rows: ['DEVOPS-null-null', 'NO-SUCH-ROW'] }))
  const r = await tryTask('devops-agent')
  check('T30b unknown row key rejected (unknown row(s); Task BLOCKED)',
    !r.ok && r.message.includes('PIPELINE VALIDATION FAILED') && r.message.includes('unknown row(s)'),
    r.ok ? 'NOT blocked' : r.message.split('\n')[0])
}

console.log('')
console.log(`RESULT: pass=${pass} fail=${fail}`)
process.exit(fail ? 1 : 0)
