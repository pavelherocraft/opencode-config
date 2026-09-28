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
try {
  ({ WorkflowEnforcement } = await import(pathToFileURL(pluginPath).href))
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

async function lockSession(agent) {
  await plugin.event({
    event: { type: 'session.created', properties: { session: { agent, id: `s-${agent}` } } },
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

const FORBIDDEN = ['edit', 'write', 'bash', 'webfetch', 'todowrite', 'question', 'patch']
const ALLOWED = ['read', 'glob', 'grep']

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

console.log('')
console.log(`RESULT: pass=${pass} fail=${fail}`)
process.exit(fail ? 1 : 0)
