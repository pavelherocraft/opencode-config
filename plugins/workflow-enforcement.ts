import type { Plugin } from "@opencode-ai/plugin"

// ============================================================
// Routing Tables — which agents each primary agent can call
// ============================================================
const ROUTING_TABLES = {
  orchestrator: [
    "orchestrator-identity-probe",
    "dev-reviewer",
    "dev-professor",
    "mcp-github",
    "worker",
    "bugfix",
    "rework",
    "mcp-read",
    "utility",
    "bugfix-triage",
    "plan-bug",
    "devops-agent",
    "devops-reviewer",
    "dev-planner",
    "mcp-search",
    "docs-writer",
    "summarizer",
    "execute-bug",
    "consistency-checker",
    "view-image",
    "docs-planner",
    "image-creator",
    "video-generator",
    "git-commit",
    "advisor",
    "voice-synthesizer",
    "voice-transcriber",
    "voice-clone",
    "codebase-analyzer"
  ],
  plankestrator: [
    "plankestrator-identity-probe",
    "plan-writer-simple",
    "plan-writer-complex",
    "plan-reviewer-simple",
    "plan-reviewer-complex",
    "research-writer-simple",
    "research-writer-complex",
    "research-reviewer",
    "devops-readonly",
    "view-image"
  ]
}

// ============================================================
// JSON Validation Rules
// ============================================================
const REQUIRED_JSON_FIELDS: Record<string, string[]> = {
  orchestrator: ["agent", "type", "complexity", "plan_exists", "plan_source", "goal", "next_agent", "pipeline"],
  plankestrator: ["agent", "state", "type", "complexity", "goal", "next_agent", "pipeline"]
}

const VALID_VALUES: Record<string, Record<string, (string | null)[]>> = {
  orchestrator: {
    agent: ["orchestrator"],
    type: ["BUGFIX", "DEVOPS", "DEV", "DOCS", "MULTI_PHASE", null],
    complexity: ["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX", null],
    // v7 (Multi-Phase MVP): optional state — validated only if present (null is a
    // legal value; single-phase turns never carry the field). state is
    // MULTI_PHASE-only for orchestrator — enforced in validateJSONOutput (v7 block).
    state: ["AWAITING_CONFIRMATION", "CANCELLED", null]
  },
  plankestrator: {
    agent: ["plankestrator"],
    state: ["CLASSIFY", "EXECUTE", "REVIEW", "COMPLETE"],
    type: ["PLAN", "RESEARCH", "RESEARCH+PLAN", null],
    complexity: ["SIMPLE", "COMPLEX", null]
  }
}

const IDENTITY_PROBE_AGENTS = [
  "orchestrator-identity-probe",
  "plankestrator-identity-probe"
]

// ============================================================
// v5 (OMP P0-1) — Reviewer severity taxonomy (Emission-Guard-аналог).
// Источник: RESEARCH_OMP_FEATURES.md, Recommendation P0-1.
// nit → логируется, НЕ триггерит rework; concern → rework-loop;
// blocker → triggered turn (немедленный rework + эскалация).
// Fail-closed: отсутствие severity orchestrator трактует как concern.
// ============================================================
const SEVERITY_AGENTS = ["dev-reviewer", "consistency-checker", "advisor"]
const VALID_SEVERITIES = ["nit", "concern", "blocker"]
// Фильтр пустых фраз (OMP emission-guard, п.2): шумовые «замечания» не считаются findings
const EMPTY_FINDING_PHRASES = [
  "stop", "done", "lgtm", "no issues", "nothing to add",
  "looks good", "ok", "fine", "no problems", "all good"
]
// Бюджет на update (OMP emission-guard, п.4): max 4 non-blocker; blocker освобождён
const MAX_NON_BLOCKER_FINDINGS_PER_UPDATE = 4
// Session-scoped дедупликация точного текста (OMP emission-guard, п.3):
// agent → набор нормализованных текстов замечаний; сброс на session.created top-level
let seenFindings: Map<string, Set<string>> = new Map()

// ============================================================
// v5 (OMP P0-3) — Per-audience context files (WATCHDOG.md-аналог).
// Reviewer-агенты читают REVIEW_CONTEXT.md (project root → user level);
// плагин дополнительно инжектит указатель в Task-prompt (belt-and-braces).
// ============================================================
const CONTEXT_FILE_AGENTS = [
  "dev-reviewer", "consistency-checker", "devops-reviewer",
  "plan-reviewer-simple", "plan-reviewer-complex", "research-reviewer",
  "advisor"
]
const REVIEW_CONTEXT_FILE = "REVIEW_CONTEXT.md"

// ============================================================
// Plugin State (per-process, reset on session.created)
// ============================================================
let currentAgent: string | null = null
let identityLocked: boolean = false
let lockedAgentName: string | null = null
let hasOutputtedJSON: Map<string, boolean> = new Map()
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
// Стек запущенных Task-субагентов (верхний = текущий acting agent). Зеркалит
// push/pop активногоTaskDepth: пока depth>0 currentAgent — это РОДИТЕЛЬСКИЙ
// primary (дочерние сессии его не перезаписывают), поэтому .md-бан атрибутирует
// вызов инструмента по вершине стека, а не по currentAgent.
let subagentStack: string[] = []
// Track if primary agent has made first Task call (for read/grep/glob lock)
const primaryAgentFirstTaskCall = new Map<string, boolean>()

// ============================================================
// v6 (Part II, Phase 9.0а/б + 10.1 + 13.1 + 14.1) — deferred violation flags
// and pipeline-step tracking. Pattern: selfWorkDetected (set in message.updated,
// consumed in tool.execute.before). A throw inside the event hook is INERT —
// the message is already sent; only the unified gate in tool.execute.before
// (Phase 9.0в) blocks the real action.
// Consume-once: flags reset after the throw; recovery — a clean valid message
// clears message-derived flags (latest-message-wins; message.updated re-fires
// per streaming chunk, early chunks may lack identity/JSON).
// ============================================================
let identityMissing = false      // Phase 9.1  — primary message without identity line
let pipelineMismatch = false     // Phase 9.2  — pipeline violates PIPELINE TABLE
let nextAgentMismatch = false    // Phase 9.3  — next_agent violates pipeline step
let invalidJSON = false          // Phase 9.4  — JSON schema violation (incl. severity, Phase 15)
let forbiddenIdentity = false    // Phase 9.5  — foreign identity claim ("I am plankestrator")
let pipelineImmutable = false    // Phase 17.2 — pipeline changed after Turn 1
let blockerStop = false          // Phase 14.3 — 3 blockers; NOT cleared by recovery (cumulative)
let violationDetail = ""         // detail text for the deferred THROW message

// v6 (Phase 9.0б): dedup of NON-idempotent operations by messageID (streaming re-fires)
const processedMessageIDs = new Set<string>()

// v6 (Phase 13.2б): top-level session ID — attribution of a parallel Task
// (caller = primary vs caller = subagent performing a legitimate nested delegation)
let topLevelSessionID: string | null = null

// v6 (Phase 10.1): pipeline step tracking — replaces the `const currentStep = 0` TODO stub.
// Key = primary agent name (hasOutputtedJSON / primaryAgentFirstTaskCall pattern).
// currentStep semantics: index of the LAST DISPATCHED agent (dispatch happens in the
// same turn whose JSON set the state); expected next_agent of the following turn =
// pipeline[currentStep + 1].
// provisional=true: classification turn with complexity=null (DECOMPOSITION Turn A,
// codebase-analyzer helper, BUGFIX/DEVOPS Turn 1) — the pipeline is NOT frozen yet and
// may be freely replaced by the next turn (correction F-4).
// type: last locked type — used by the Auto-DOCS hook exception (correction F-12).
// v7 (Multi-Phase MVP): + phases/currentPhaseIdx — MULTI_PHASE-only snapshot for the
// phase-mutation whitelist MP-1..MP-6 (undefined for single-phase entries; existing
// fields and semantics untouched).
const pipelineState = new Map<string, {
  pipeline: string[]; currentStep: number; provisional: boolean; type: string | null;
  // v8: classification snapshot captured at lock time — lets the Phase 17.2
  // self-heal re-validate the LOCKED baseline against its OWN classification.
  complexity: string | null; planExists: boolean | null;
  phases?: any[]; currentPhaseIdx?: number
}>()

// v8 (regression T28c): test seam — direct handle on the pipeline lock map.
// Production paths never read it; the harness uses it to inject a POISONED
// lock (an invalid baseline that no valid event sequence can produce) and to
// assert the Phase 17.2 self-heal recapture instead of a permanent IMMUTABLE.
export const __testPipelineState = pipelineState

// v6 (Phase 13.1): max ONE Task call per turn
const taskCallsPerTurn = new Map<string, number>()   // agent → Task calls in current turn
const lastTurnMessageID = new Map<string, string>()  // agent → messageID of current turn (reset dedup)

// v6 (Phase 14.1): rework loop max 3 + BLOCKER STOP after 3 — PER REWORK-LOOP,
// not per session (advisor Note 2): SUPERCOMPLEX runs a full rework loop PER PLAN
// STEP; session-scoped counting would exhaust the max-3 quota by the 3rd plan step.
// The counters reset when a new loop context begins (see the pipeline state block).
const reworkCount = new Map<string, number>()        // agent → rework dispatches in current loop
const blockerEscalations = new Map<string, number>() // agent → reviewer severity=blocker in current loop
// v6 (advisor Note 2): furthest pipeline index dispatched — detects new loop context
// (forward progress past the max, or a backward jump >= 2 = a new chain cycle).
const maxStepReached = new Map<string, number>()     // agent → furthest pipeline index dispatched

// v6 (correction F-4): auxiliary agents of classification turns — NOT pipeline steps
// (same semantics as AUXILIARY_TASK_TARGETS in the Task section): their turns skip
// next_agent validation and do not lock pipelineState.
const AUXILIARY_NEXT_AGENTS = [...IDENTITY_PROBE_AGENTS, "view-image"]

// v6 (correction F-11 / risk R15): row-6 SUPERCOMPLEX semantics are not fully
// formalized — the rework-loop agent is ABSENT from the base array ("full chain PER
// PLAN STEP", orchestrator.md SUPERCOMPLEX Stage 2 item 6) and per-step re-emission
// may vary the array. Strict 10.3/17.2 checks would produce GUARANTEED false
// positives → log-only for complexity==="SUPERCOMPLEX" until the format is formalized.
const SUPERCOMPLEX_STRICT = false

// ============================================================
// v7 (Multi-Phase MVP) — phase-level state + confirmation gate.
// MVP: linear chain, MULTI_PHASE_MIN..MAX phases, depends_on = [previous].
// Stage 2 backlog: MAX → 4, explicit DAG, continue_on_error.
// ============================================================
const MULTI_PHASE_MIN = 2
const MULTI_PHASE_MAX = 3
const MULTI_PHASE_TYPES = ["BUGFIX", "DEVOPS", "DEV", "DOCS"]
const MULTI_PHASE_STATES = ["AWAITING_CONFIRMATION", "CANCELLED"]
const DOCS_HOOK_CHAIN = ["docs-writer", "utility"]

// ============================================================
// HARD BAN on .md / .markdown edits — only these agents may modify
// documentation. Enforced in tool.execute.before BEFORE the depth-guard
// (subagent calls included). All other agents must route doc updates
// through requires_docs_update: true → Auto-DOCS hook.
// ============================================================
const DOCS_WHITELIST = [
  "docs-writer",
  "docs-planner",
  "plan-writer-simple",
  "plan-writer-complex",
  "research-writer-simple",
  "research-writer-complex"
]

// Confirmation gate: true between an AWAITING_CONFIRMATION JSON and the user's
// reply. Clearing: (a) a user-role message (role pattern of the self-work guard
// below), or (b) ANY new assistant messageID — turn-based guarantee: the primary
// only wakes on user input or Task completion, and Task is blocked while awaiting,
// so a new assistant turn IMPLIES a user reply (fallback if opencode does not
// surface user-role messages to plugins — risk R1, V-pilot-1 in Phase 4).
let awaitingConfirmation = false
let awaitingMsgId: string | null = null

// ============================================================
// v7.1 (P0 event-shape fix, opencode 1.18.34) — message TEXT transport.
// message.updated carries NO content: the assistant's text arrives as
// `message.part.updated` (type="text", cumulative `part.text`) and
// `message.part.delta` (incremental chunks). Buffers are keyed by messageID /
// partID; a message is only validated once FINALIZED (finish="stop" or
// time.completed). Reasoning parts are ignored ENTIRELY — their deltas also use
// field="text" and would corrupt JSON extraction if merged.
// ============================================================
const TEXT_BUFFER_CAP = 200
let partTypes: Map<string, string> = new Map()       // partID → type (text|reasoning|…)
let partTexts: Map<string, string> = new Map()       // partID → latest full text (from part.updated)
let partDeltas: Map<string, string> = new Map()      // partID → accumulated deltas
let messageParts: Map<string, string[]> = new Map()  // messageID → ordered unique TEXT partIDs

// ============================================================
// Forbidden vocabulary per agent — sanity check on message text.
// If the agent claims identity X but writes text characteristic of Y,
// the plugin rejects the message instead of silently warning.
// ============================================================
const FORBIDDEN_VOCAB: Record<string, string[]> = {
  orchestrator: [
    "I am plankestrator", "I'm plankestrator", "I am the Plankestrator",
    "## PLAN", "# Implementation Plan", "research-writer-", "plan-writer-",
    "research-reviewer", "plan-reviewer-"
  ],
  plankestrator: [
    "I am orchestrator", "I'm orchestrator", "I am the Conductor",
    "I am the Task classifier", "Task classifier and router",
    "bugfix-triage", "execute-bug", "devops-agent", "consistency-checker"
  ]
}

// v6 (Phase 9.5): identity-subset of FORBIDDEN_VOCAB — these ESCALATE to a deferred
// THROW (gate 9.0в). Agent-name tokens stay log-only (legitimate cross-references,
// e.g. orchestrator quoting "plan-writer-" in prose — rationale of the old :641–644
// comment holds for names).
const FORBIDDEN_IDENTITY_TOKENS: Record<string, string[]> = {
  orchestrator: ["I am plankestrator", "I'm plankestrator", "I am the Plankestrator"],
  plankestrator: ["I am orchestrator", "I'm orchestrator", "I am the Conductor",
                   "I am the Task classifier", "Task classifier and router"]
}

// ============================================================
// Self-work markers (v4; v6 Phase 12: + orchestrator) — маркеры САМОСТОЯТЕЛЬНОЙ
// plan/research/implementation-работы
// в сообщении locked primary-агента (исследование: Пробел 3, Рек. 3).
// Намеренно НЕ смешиваются с FORBIDDEN_VOCAB: тот логируется как
// "contains {otherAgent} terminology" (стр. 420) — семантика другая.
// Заголовочные токены ("## ...") снижают false-positive: обычные слова
// ("research", "findings") встречались бы в легальной маршрутной прозе
// и именах файлов ("RESEARCH.md"). Русские маркеры добавлены сверх
// списка исследования: модель отвечает пользователю по-русски.
// ============================================================
const SELF_WORK_MARKERS: Record<string, string[]> = {
  // v6 (Phase 12): orchestrator self-work = writing analysis/implementation yourself
  // instead of delegating (worker / dev-planner / bugfix-triage / docs-writer).
  // Heading tokens ("## ...") keep the false-positive rate low (same rationale as v4).
  orchestrator: ["## Findings", "## Analysis", "## Implementation", "## Root Cause"],
  plankestrator: [
    "## Findings", "## Research", "Executive Summary", "## Analysis",
    "### Root Cause", "## Recommendations", "## Overview",
    "## Выводы", "## Результаты исследования"
  ]
}

// ============================================================
// Plugin Entry Point
// ============================================================
export const WorkflowEnforcement: Plugin = async ({ client, $ }) => {
  await client.app.log({
    body: {
      service: "workflow-enforcement",
      level: "info",
      message: "Workflow enforcement plugin initialized (v2 — correct hooks)"
    }
  })

  return {
    // ==========================================================
    // "event" hook — handles session lifecycle, identity tracking,
    // and JSON validation. Replaces the broken "session.created",
    // "session.updated", "session.idle", and "message.updated"
    // top-level hooks (which don't exist in the opencode API).
    // ==========================================================
    event: async ({ event }) => {
      // ----------------------------------------------------------
      // session.created — detect initial agent identity
      // ----------------------------------------------------------
      if (event.type === "session.created") {
        // v4: ДОЧЕРНИЕ сессии (Task-субагенты) НЕ должны стирать identity-lock и
        // workflow-состояние РОДИТЕЛЬСКОЙ primary-сессии. Без этого guard'а первая
        // же делегация сбрасывает identityLocked=false и workflowSteps=[]
        // (безусловный reset ниже), молча отключая Gate A, routing enforcement и
        // INSPECTION GATE на остаток сессии родителя. Вызовы инструментов
        // субагентов атрибутируются отдельно через activeTaskDepth
        // (depth-guard в tool.execute.before / message.updated).
        // v7.1 (P0 event-shape fix): opencode 1.18.34 ships the session as
        // properties.info (legacy: properties.session). resolveSessionData()
        // preserves the legacy fallbacks for backward compatibility.
        const childCheckData = resolveSessionData(event)
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
        // session BEFORE attempting detection. Plugin state persists across
        // sessions within the same opencode process. Without this reset, a
        // build-agent session (or any non-primary agent) would inherit
        // identityLocked=true and lockedAgentName="orchestrator" from a
        // previous session, causing edit/write/bash to be incorrectly blocked.
        //
        // The header comment claims "reset on session.created", but the prior
        // implementation only reset when detectAgentFromSessionData() returned
        // a primary agent. For non-primary agents (build, explore, general,
        // custom specialists) detection returns null and the stale lock
        // leaked across sessions. This block makes the reset unconditional.
        currentAgent = null
        identityLocked = false
        lockedAgentName = null
        hasOutputtedJSON = new Map()
        selfWorkDetected = false
        activeTaskDepth = 0
        subagentStack = []
        seenFindings = new Map()  // v5: сброс дедуп-журнала замечаний
        primaryAgentFirstTaskCall.clear()

        // v6 (Phase 9.0д + 10.4 + 13.2б + 14.4): reset deferred-violation state,
        // pipeline tracking and counters. CRITICAL: this lives in the unconditional
        // reset block AFTER the parentID guard — a child (Task subagent) session must
        // NOT wipe the parent's state (same bug the guard was written for).
        identityMissing = pipelineMismatch = nextAgentMismatch = invalidJSON =
          forbiddenIdentity = pipelineImmutable = blockerStop = false
        violationDetail = ""
        pipelineState.clear()
        taskCallsPerTurn.clear()
        lastTurnMessageID.clear()
        reworkCount.clear()
        blockerEscalations.clear()
        maxStepReached.clear()
        processedMessageIDs.clear()
        // v7.1 (P0): message-text transport buffers (reset per top-level session).
        partTypes.clear()
        partTexts.clear()
        partDeltas.clear()
        messageParts.clear()
        // v7 (Multi-Phase MVP): confirmation gate state (V-21)
        awaitingConfirmation = false
        awaitingMsgId = null
        // v6 (Phase 13.2б): remember the top-level session ID for parallel-Task
        // attribution. childCheckData is in scope (defined above, before the guard).
        // If extraction fails (field names differ), topLevelSessionID stays null and
        // 13.2б degrades to the pre-existing warn (safe fallback).
        topLevelSessionID = String((event as any).properties?.sessionID
          || (event as any).sessionID || (event as any).session_id
          || childCheckData?.id || "") || null

        // Try to detect agent from event data (v7.1: resolve properties.info too)
        const sessionData = resolveSessionData(event)

        // NEW: Detect OpenCode's built-in Plan mode (Shift+Tab toggle).
        // Built-in Plan mode is a UI-level read-only mode that uses the
        // default primary agent (e.g. "build"), NOT orchestrator/plankestrator.
        // Custom agent routing must be bypassed in this mode.
        const previousMode = currentMode
        currentMode = detectPlanMode(sessionData)
        if (currentMode === "plan") {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Built-in Plan mode detected — workflow enforcement BYPASSED (mode: ${previousMode} → ${currentMode})`
            }
          })
        } else {
          // DEBUG-DUMP: detector returned "build". If the user is actually
          // in built-in Plan mode, this dump will reveal the real field
          // name(s) OpenCode uses, so detectPlanMode() can be updated.
          const sessionKeys = sessionData && typeof sessionData === "object"
            ? Object.keys(sessionData)
            : []
          const suspectFields = ["agent", "mode", "planMode", "plan_mode", "permission", "plan", "title", "parentID", "time", "primary"]
          const foundFields: Record<string, unknown> = {}
          for (const f of suspectFields) {
            if (sessionData && f in sessionData) {
              foundFields[f] = (sessionData as any)[f]
            }
          }
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `[DEBUG-DUMP] session.created — plan mode NOT detected. sessionData keys: [${sessionKeys.join(", ")}]`,
              extra: {
                foundFields,
                fullKeys: sessionKeys
              }
            }
          })
        }

        const detected = detectAgentFromSessionData(sessionData)

        if (detected) {
          currentAgent = detected
          identityLocked = true
          lockedAgentName = detected
          hasOutputtedJSON.set(detected, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Session created — agent LOCKED: ${detected} (identity will be enforced strictly)`,
              extra: { sessionId: (event as any).session_id || (event as any).sessionID, locked: true }
            }
          })

          // Inject JSON requirement reminder for primary agents
          if (detected === "orchestrator" || detected === "plankestrator") {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "MANDATORY: You MUST output JSON before any Task tool call. Format: 1) IDENTITY VERIFIED line, 2) JSON code block, 3) Task tool call. NO EXCEPTIONS."
              }
            })
          }
        } else {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: "Session created — agent not yet detected, will detect from output"
            }
          })
        }

        // Reset workflow tracking for new session
        workflowSteps = []
      }

      // ----------------------------------------------------------
      // session.updated — identity detection for opencode 1.18.34.
      // session.created fires BEFORE the agent is bound (its info has no agent
      // field); the authoritative agent arrives on the NEXT session.updated
      // (info.agent = "orchestrator"). Without this handler currentAgent stays
      // null and ALL message-level enforcement is inert (P0).
      // ----------------------------------------------------------
      if (event.type === "session.updated") {
        const suData = resolveSessionData(event)
        const suParentID = suData?.parentID
          || (event as any).properties?.parentID
          || (event as any).parentID
        if (suParentID) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `CHILD session updated (parentID=${suParentID}) — primary-agent state PRESERVED`,
              extra: { parentID: String(suParentID) }
            }
          })
          return
        }
        // Plan-mode re-check (detectPlanMode is guarded: a custom primary agent
        // is NEVER built-in Plan mode — see the permission-rule guard below).
        const suMode = detectPlanMode(suData)
        const suModeChanged = suMode !== currentMode
        if (suModeChanged) {
          const prevMode = currentMode
          currentMode = suMode
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Mode changed (session.updated): ${prevMode} → ${suMode} — ${suMode === "plan" ? "enforcement BYPASSED" : "enforcement ACTIVE"}`
            }
          })
        }
        const suDetected = detectAgentFromSessionData(suData)
        const suAgentChanged = !!suDetected && (!identityLocked || lockedAgentName !== suDetected)
        if (suDetected && suAgentChanged) {
          currentAgent = suDetected
          identityLocked = true
          lockedAgentName = suDetected
          if (!hasOutputtedJSON.has(suDetected)) hasOutputtedJSON.set(suDetected, false)
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Session updated — agent LOCKED: ${suDetected} (identity will be enforced strictly)`,
              extra: { sessionId: (event as any).properties?.sessionID, locked: true }
            }
          })
        }
        // v8: deadlock fix — a mode/agent switch (e.g. plan→build) invalidates
        // any Turn-1 baseline locked in the OLD context. Drop the deferred
        // flags and the pipeline lock so a stale lock cannot outlive its
        // context. identityLocked / currentAgent are deliberately NOT touched
        // (their logic lives above); workflowSteps stays session.created-only.
        if (suModeChanged || suAgentChanged) {
          identityMissing = pipelineMismatch = nextAgentMismatch = invalidJSON =
            forbiddenIdentity = pipelineImmutable = blockerStop = false
          violationDetail = ""
          pipelineState.clear()
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Session updated — deferred flags + pipelineState CLEARED (mode/agent switched)`,
              extra: { modeChanged: suModeChanged, agentChanged: suAgentChanged }
            }
          })
        }
        // NOTE: do NOT reset workflow state here — only session.created resets.
        return
      }

      // ----------------------------------------------------------
      // session.idle — log workflow summary
      // ----------------------------------------------------------
      if (event.type === "session.idle") {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "info",
            message: "Session idle — workflow summary",
            extra: {
              agent: currentAgent,
              totalSteps: workflowSteps.length,
              steps: workflowSteps.slice(-10)
            }
          }
        })
      }

      // ----------------------------------------------------------
      // message.part.updated / message.part.delta — TEXT transport (v7.1).
      // opencode 1.18.34 delivers the assistant's text here, not in
      // message.updated. Only part.type === "text" is buffered; reasoning parts
      // (whose deltas ALSO use field="text") are ignored to keep JSON extraction
      // clean. Buffers are reset per top-level session and capped (LRU ~200).
      // ----------------------------------------------------------
      if (event.type === "message.part.updated") {
        const part = (event as any).properties?.part || (event as any).part
        if (!part) return
        const pType = String(part.type || "")
        const pid = String(part.id || "")
        const mid = String(part.messageID || "")
        if (pid) {
          partTypes.set(pid, pType)
          if (partTypes.size > TEXT_BUFFER_CAP * 4) {
            const oldest = partTypes.keys().next().value
            if (oldest !== undefined && oldest !== pid) partTypes.delete(oldest)
          }
        }
        if (pType === "text" && mid && pid) {
          partTexts.set(pid, String(part.text ?? ""))
          rememberMessagePart(mid, pid)
        }
        return
      }
      if (event.type === "message.part.delta") {
        const props = (event as any).properties || {}
        const pid = String(props.partID || "")
        const mid = String(props.messageID || "")
        // Reasoning filter: only deltas of a KNOWN text part are accumulated.
        if (String(props.field) === "text" && pid && mid && partTypes.get(pid) === "text") {
          partDeltas.set(pid, (partDeltas.get(pid) ?? "") + String(props.delta ?? ""))
          rememberMessagePart(mid, pid)
        }
        return
      }

      // ----------------------------------------------------------
      // message.updated — validate JSON output + detect agent
      // ----------------------------------------------------------
      if (event.type === "message.updated") {
        // v7.1 (P0 event-shape fix): opencode 1.18.34 ships the message as
        // properties.info (legacy: properties.message) and carries NO content —
        // text arrives via message.part.updated/delta and is assembled from the
        // per-messageID buffer. A message is validated ONLY once FINALIZED
        // (finish="stop" or time.completed), when the full text is available.
        const resolvedMessage = resolveMessage(event)
        if (!resolvedMessage) return
        const turnMsgId = String((resolvedMessage as any).id || (resolvedMessage as any).info?.id || "")
        const msgRole = String((resolvedMessage as any).role || (resolvedMessage as any).info?.role || "assistant")
        const msgFinish = String((resolvedMessage as any).finish || (resolvedMessage as any).info?.finish || "")
        const msgCompleted = !!(resolvedMessage as any).time?.completed
          || !!(resolvedMessage as any).info?.time?.completed
        // Backward compatibility: a LEGACY message carrying inline content is
        // complete by definition (old transport) — validate it immediately.
        const hasInlineContent = typeof (resolvedMessage as any).content === "string"
          || typeof (resolvedMessage as any).text === "string"
        const finalized = msgFinish === "stop" || msgCompleted || hasInlineContent
        const message: any = {
          ...resolvedMessage,
          id: turnMsgId,
          role: msgRole,
          content: assembleMessageContent(turnMsgId, resolvedMessage),
        }

        // v4: сообщения, созданные ПОКА выполняется Task-субагент, принадлежат
        // субагенту (writer легально пишет "## Findings" и свой JSON) —
        // enforcement атрибутирован родителю, пропускаем.
        if (activeTaskDepth > 0) {
          // v5 (OMP P0-1): сообщения субагентов не проходят primary-валидацию,
          // НО JSON reviewer-агентов проверяется на severity (warn-only: плагин
          // не может блокировать вывод субагента; fail-closed потребление —
          // в промпте orchestrator'а: missing severity = concern).
          const subMessage = message
          const subJson = subMessage ? extractJSONFromMessage(subMessage) : null
          const subAgent = subJson?.agent ? String(subJson.agent) : null
          if (subJson && subAgent && SEVERITY_AGENTS.includes(subAgent)) {
            // 1. Присутствие и валидность severity
            if (!subJson.severity) {
              await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                message: `REVIEWER SEVERITY MISSING — ${subAgent} JSON без severity; orchestrator MUST treat as "concern" (fail-closed)`,
                extra: { agent: subAgent } } })
            } else if (!VALID_SEVERITIES.includes(String(subJson.severity))) {
              await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                message: `REVIEWER SEVERITY INVALID — ${subAgent}: "${subJson.severity}", expected: ${VALID_SEVERITIES.join("|")}`,
                extra: { agent: subAgent, severity: String(subJson.severity) } } })
            }
            // 2. blocker → error-level (triggered turn: немедленный rework + эскалация)
            if (String(subJson.severity) === "blocker") {
              await client.app.log({ body: { service: "workflow-enforcement", level: "error",
                message: `BLOCKER FINDING — ${subAgent} вернул severity=blocker; orchestrator: немедленный rework + ⚠️ BLOCKER ack + эскалация пользователю при персистировании`,
                extra: { agent: subAgent } } })
              // v6 (Phase 14.3): BLOCKER STOP after 3 (orchestrator.md SEVERITY RULES —
              // "if a blocker persists after the 3rd rework iteration → STOP and report").
              // Reviewer JSON arrives in SUBAGENT messages (this depth>0 branch); a throw
              // in the event hook is inert → the blockerStop flag is consumed by gate 9.0в:
              // it blocks the primary's NEXT tool call, forcing the final summary instead
              // of a 4th iteration. blockerStop is NOT cleared by recovery (cumulative
              // session state) — only session.created resets it. MessageID dedup is
              // mandatory (streaming re-fires; suffixed key avoids collision with 10.2).
              const blockerMsgId = String((subMessage as any).id || (subMessage as any).info?.id || "")
              if (blockerMsgId && !processedMessageIDs.has(blockerMsgId + ":blocker")) {
                processedMessageIDs.add(blockerMsgId + ":blocker")
                const bCount = (blockerEscalations.get(currentAgent ?? "") || 0) + 1
                blockerEscalations.set(currentAgent ?? "", bCount)
                await client.app.log({ body: { service: "workflow-enforcement", level: "error",
                  message: `BLOCKER ESCALATION COUNTED — ${bCount}/3 (${subAgent})`,
                  extra: { agent: currentAgent, reviewer: subAgent, count: bCount } } })
                if (bCount >= 3) {
                  blockerStop = true
                  violationDetail = `BLOCKER STOP AFTER 3: blocker persisted after 3 rework iterations (${subAgent}). Escalate to the user in the final summary — do NOT dispatch another Task.`
                }
              }
            }
            // 3. Дедуп + фильтр пустых фраз + бюджет (emission-guard)
            const seen = seenFindings.get(subAgent) ?? new Set<string>()
            let nonBlockerCount = 0
            for (const f of collectFindings(subJson)) {
              const norm = normalizeFinding(f.text)
              if (!norm || EMPTY_FINDING_PHRASES.includes(norm)) {
                await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                  message: `EMPTY FINDING FILTERED — ${subAgent}: "${f.text.slice(0, 80)}"`, extra: { agent: subAgent } } })
                continue
              }
              if (seen.has(norm)) {
                await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                  message: `DUPLICATE FINDING SUPPRESSED — ${subAgent} повторно вернул замечание (между итерациями rework-loop)`,
                  extra: { agent: subAgent, finding: norm.slice(0, 120) } } })
                continue
              }
              seen.add(norm)
              if (f.severity !== "blocker") nonBlockerCount++
            }
            seenFindings.set(subAgent, seen)
            if (nonBlockerCount > MAX_NON_BLOCKER_FINDINGS_PER_UPDATE) {
              await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                message: `FINDING BUDGET EXCEEDED — ${subAgent}: ${nonBlockerCount} non-blocker findings (max ${MAX_NON_BLOCKER_FINDINGS_PER_UPDATE}); избыток — шум`,
                extra: { agent: subAgent, count: nonBlockerCount, budget: MAX_NON_BLOCKER_FINDINGS_PER_UPDATE } } })
            }
          }
          return
        }

        // v6 (Phase 13.3): turn boundary = a NEW primary message. Dedup by messageID:
        // message.updated fires per streaming chunk — the counter resets ONLY when the
        // message changes (an unconditional reset would zero the counter between two Task
        // calls of the SAME message, making the 13.2 gate inert — source-plan correction).
        // Subagent messages never reach here (the depth>0 branch returns earlier).
        if (currentAgent && turnMsgId && lastTurnMessageID.get(currentAgent) !== turnMsgId) {
          lastTurnMessageID.set(currentAgent, turnMsgId)
          taskCallsPerTurn.set(currentAgent, 0)
        }

        // v7 (Multi-Phase MVP): confirmation gate CLEARING. (a) explicit user-role
        // message (role pattern of the self-work guard below); (b) FALLBACK — any NEW
        // assistant messageID: the primary only wakes on user input or Task completion,
        // and Task is blocked while awaiting ⇒ a new assistant turn implies the user
        // replied (robust even if user messages never reach message.updated — R1).
        // Streaming re-fires of the SAME AWAITING message (turnMsgId === awaitingMsgId)
        // do NOT clear — same-messageID Task calls stay blocked (gate in
        // tool.execute.before). Subagent messages never reach here (depth guard above).
        if (awaitingConfirmation) {
          const gateRole = String((message as any).role || (message as any).info?.role || "assistant")
          if (gateRole === "user") {
            awaitingConfirmation = false
            awaitingMsgId = null
            await client.app.log({ body: { service: "workflow-enforcement", level: "info",
              message: "USER RESPONSE RECEIVED — confirmation gate cleared" } })
          } else if (turnMsgId && turnMsgId !== awaitingMsgId) {
            awaitingConfirmation = false
            awaitingMsgId = null
            await client.app.log({ body: { service: "workflow-enforcement", level: "info",
              message: "NEW ASSISTANT TURN after AWAITING — user reply implied (turn-based guarantee); gate cleared" } })
          }
        }

        // v7.1 (P0): only FINALIZED messages are validated — user messages were
        // already handled by the gate-clearing block above; streaming chunks without
        // finish/completed cannot be trusted for identity/JSON extraction.
        if (!finalized) return

        // v6 (Phase 9.0г, correction F-9): per-event marker — "a deferred flag was set
        // DURING THIS message.updated run". The recovery in the valid-JSON else-branch
        // clears only flags left by PREVIOUS messages, never the ones set by this
        // event's validations (:556–602 run BEFORE the else-branch in the same run).
        let v6FlagSetThisEvent = false

        // NEW: Detect mode change mid-session (user toggles Shift+Tab).
        // Some opencode versions include session metadata in the message
        // event payload, so re-check the plan mode indicator here.
        const sessionDataMid = (event as any).properties?.session
          || (event as any).session
        if (sessionDataMid) {
          const newMode = detectPlanMode(sessionDataMid)
          if (newMode !== currentMode) {
            const prevMode = currentMode
            currentMode = newMode
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Mode changed mid-session: ${prevMode} → ${newMode} — ${newMode === "plan" ? "enforcement BYPASSED" : "enforcement ACTIVE"}`
              }
            })
          }
        }

        const jsonContent = extractJSONFromMessage(message)
        const identityText = extractIdentityFromMessage(message)

        // v6 (Phase 9.0г-1): recovery — identity line present → clear identityMissing
        // (latest-message-wins: an early streaming chunk may not contain the line yet).
        if (identityText) identityMissing = false

        // NEW: Block primary agents without identity line in first message
        if ((currentAgent === "orchestrator" || currentAgent === "plankestrator") &&
            !identityText &&
            !hasOutputtedJSON.get(currentAgent)) {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "error",
              message: `PRIMARY AGENT MISSING IDENTITY — ${currentAgent} did not start with "IDENTITY VERIFIED: I am ${currentAgent}"`,
              extra: { agent: currentAgent }
            }
          })
          // v6 (Phase 9.1): escalate log-only → deferred THROW (gate 9.0в blocks the
          // next tool call of this primary). Recovery: the next message containing the
          // identity line clears the flag (9.0г-1).
          identityMissing = true
          violationDetail = `PRIMARY AGENT MISSING IDENTITY — ${currentAgent} did not start with "IDENTITY VERIFIED: I am ${currentAgent}"`
        }

        // FIX: Use IDENTITY VERIFIED text to detect agent FIRST (highest priority)
        if (identityText && !currentAgent) {
          if (identityText === "orchestrator" || identityText === "plankestrator") {
            currentAgent = identityText
            hasOutputtedJSON.set(identityText, false)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected from IDENTITY VERIFIED text: ${identityText}`
              }
            })
          }
        }

        // FIX: Use JSON output to detect agent if not yet detected
        if (jsonContent?.agent && !currentAgent) {
          const agentName = String(jsonContent.agent)
          if (agentName === "orchestrator" || agentName === "plankestrator") {
            currentAgent = agentName
            hasOutputtedJSON.set(agentName, false)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected from JSON output: ${agentName}`
              }
            })
          }
        }

        // FIX: If both IDENTITY VERIFIED text and JSON exist, use IDENTITY VERIFIED as primary
        // This prevents drift detection when session data incorrectly identified agent
        if (identityText && currentAgent && identityText !== currentAgent) {
          const previousAgent = currentAgent
          currentAgent = identityText
          hasOutputtedJSON.set(identityText, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "Agent corrected from IDENTITY VERIFIED text",
              extra: {
                previousAgent,
                newAgent: currentAgent
              }
            }
          })
        }

        // Check for identity drift from JSON (lower priority than IDENTITY VERIFIED text)
        // CHANGED v3: when identity is LOCKED (session.created detected a real agent),
        // drift is a HARD ERROR — we DO NOT silently switch agents anymore. This is
        // the fix for orchestrator↔plankestrator confusion: the agent cannot drift
        // once the session has been bound to a specific identity.
        if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent && !identityText) {
          if (identityLocked) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: "IDENTITY DRIFT REJECTED — agent attempted to claim a different identity than session lock",
                extra: {
                  lockedAgent: lockedAgentName,
                  claimedAgent: String(jsonContent.agent),
                  sessionId: (event as any).session_id || (event as any).sessionID
                }
              }
            })
            // v6 (Phase 9.6): escalate — drift under identity lock is a terminal
            // violation. currentAgent is NOT updated (locked identity preserved); the
            // throw aborts the remaining message.updated processing for this event.
            // CAVEAT: a throw in an event hook does NOT retract the message and may be
            // swallowed by the opencode runtime (effect = error log + aborted handler).
            // If Verification V-A5 shows the stream continues harmlessly — degrade to a
            // deferred flag (`identityDrift`) consumed by gate 9.0в (add to state block A1).
            throw new Error(`
⛔ IDENTITY DRIFT REJECTED — session is LOCKED to ${lockedAgentName}.
Claimed identity: ${String(jsonContent.agent)}. Identity cannot be changed mid-session.
            `)
          } else {
            const previousAgent = currentAgent
            currentAgent = String(jsonContent.agent)
            hasOutputtedJSON.set(currentAgent, false)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "IDENTITY DRIFT DETECTED (unlocked — correcting)",
                extra: {
                  previousAgent,
                  newAgent: currentAgent
                }
              }
            })
          }
        }

        // Validate JSON if we know which agent is running
        if (jsonContent && currentAgent) {
          // v8: deadlock fix — per-event gate for the pipeline capture below.
          // An INVALID pipeline must never be locked as the Turn-1 baseline:
          // the corrective message would then hit Phase 17.2 (pipelineImmutable)
          // and no recovery could clear it (the flag re-arms on every mismatch)
          // — a permanent deadlock blocking even read/grep.
          let pipelineOk = true
          // NEW: Validate pipeline and next_agent for primary agents
          if (jsonContent && (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {
            // v6 (Phase 15): severity in the PRIMARY's JSON — validate against the
            // taxonomy (VALID_SEVERITIES, not a duplicated literal). Previously severity
            // was checked only on subagent messages (SEVERITY_AGENTS branch); a primary
            // re-emitting reviewer JSON (rework loop) could carry an invalid value.
            // null/undefined are tolerated — severity is NOT part of the primary required
            // schema. Escalates via invalidJSON (Phase 9.4 mechanism → gate 9.0в).
            if (jsonContent.severity !== undefined && jsonContent.severity !== null &&
                !VALID_SEVERITIES.includes(String(jsonContent.severity))) {
              invalidJSON = true
              v6FlagSetThisEvent = true
              violationDetail = `INVALID SEVERITY: ${String(jsonContent.severity)}, expected ${VALID_SEVERITIES.join("|")}`
              await client.app.log({ body: { service: "workflow-enforcement", level: "error",
                message: `PRIMARY SEVERITY INVALID — ${currentAgent}: ${violationDetail}`,
                extra: { agent: currentAgent, severity: String(jsonContent.severity) } } })
            }

            const type = jsonContent.type
            const complexity = jsonContent.complexity
            const planExists = jsonContent.plan_exists
            const pipeline = jsonContent.pipeline
            const nextAgent = jsonContent.next_agent

            // Validate pipeline (v6 Phase 9.2: log escalated to deferred THROW via
            // pipelineMismatch; log preserved for audit)
            if (pipeline && Array.isArray(pipeline)) {
              const pipelineValidation = validatePipeline(currentAgent, type, complexity, planExists, pipeline, jsonContent)
              if (!pipelineValidation.valid) {
                await client.app.log({
                  body: {
                    service: "workflow-enforcement",
                    level: "error",
                    message: `PIPELINE VALIDATION FAILED — ${pipelineValidation.error}`,
                    extra: { agent: currentAgent, pipeline }
                  }
                })
                pipelineMismatch = true
                pipelineOk = false   // v8: an invalid pipeline must NOT lock the Turn-1 baseline
                v6FlagSetThisEvent = true
                violationDetail = `PIPELINE VALIDATION FAILED — ${pipelineValidation.error}`
              }
            }

            // Primary agents: pipeline must be non-empty unless state="COMPLETE"
            // v7 (Multi-Phase MVP): AWAITING_CONFIRMATION / CANCELLED / terminal shapes
            // of a MULTI_PHASE session legally carry pipeline=[] + next_agent=null (the
            // explicit MULTI_PHASE branch of validatePipeline validates them). Without
            // this exemption every such turn arms pipelineMismatch — the deferred gate
            // 9.0в would then mask the confirmation-gate message (T9) and break the
            // "AWAITING turn is VALID" design (T15b/T19). Single-phase semantics
            // (incl. OUT OF SCOPE type=null) are UNCHANGED (R4).
            const mpEmptyShapeOk = currentAgent === "orchestrator" &&
              String(jsonContent.type) === "MULTI_PHASE" &&
              (jsonContent.state === "AWAITING_CONFIRMATION" ||
               jsonContent.state === "CANCELLED" ||
               ((jsonContent.state === null || jsonContent.state === undefined) &&
                (jsonContent.next_agent === null || jsonContent.next_agent === undefined)))
            if ((currentAgent === "orchestrator" || currentAgent === "plankestrator") &&
                jsonContent.state !== "COMPLETE" && !mpEmptyShapeOk &&
                (!pipeline || pipeline.length === 0)) {
              pipelineMismatch = true
              pipelineOk = false   // v8: same reason as the validation branch above
              v6FlagSetThisEvent = true
              violationDetail = `PIPELINE EMPTY — state="${jsonContent.state}" requires non-empty pipeline`
            }

            // Validate next_agent (v6 Phase 10.3 + 9.3 — real step tracking replaces
            // the `const currentStep = 0` TODO stub; violation escalates via the
            // nextAgentMismatch deferred flag, NOT a direct throw — throws in
            // message.updated are inert).
            // F-4: auxiliary classification turns (identity probes, view-image) are NOT
            // pipeline steps — skip (AUXILIARY_TASK_TARGETS semantics of the Task section).
            if (nextAgent !== undefined && pipeline && Array.isArray(pipeline) &&
                !AUXILIARY_NEXT_AGENTS.includes(String(nextAgent))) {
              const pState = pipelineState.get(currentAgent)
              // Turn 1: state not set yet (the state block runs below, in the valid-JSON
              // else-branch) → effectiveStep = 0.
              const effectiveStep = pState ? pState.currentStep + 1 : 0
              const nextAgentValidation = validateNextAgent(nextAgent, pipeline, effectiveStep)
              if (!nextAgentValidation.valid) {
                // Whitelist exceptions:
                // (1) loopback into the completed prefix (rework loop / escalate_to /
                //     DECOMPOSITION re-dispatch / SUPERCOMPLEX per-step dev-planner).
                //     Cap effectiveStep <= length (F-12): re-dispatch AFTER exhaustion
                //     is a violation (the final turn must carry next_agent=null).
                const isLoopback = nextAgent !== null && effectiveStep <= pipeline.length &&
                  pipeline.slice(0, effectiveStep).includes(String(nextAgent))
                // (2) severity-nit skip over rework (orchestrator SEVERITY RULES)
                const isReworkSkip = pipeline[effectiveStep] === "rework" &&
                  nextAgent === pipeline[effectiveStep + 1]
                // (3) F-12: Auto-DOCS hook — legitimate pipeline switch to DOCS after the
                //     main pipeline completed (orchestrator TURN ALGORITHM: requires_docs_update).
                const isDocsHook = !!pState && pState.type !== "DOCS" &&
                  jsonContent.type === "DOCS" && String(nextAgent) === pipeline[0]
                // (4) F-11 (R15): SUPERCOMPLEX row-6 semantics not fully formalized
                //     (rework absent from the base array; per-step re-emission) → log-only.
                //     v7: extended to a SUPERCOMPLEX PHASE inside a MULTI_PHASE session.
                const isSupercomplexExempt = !SUPERCOMPLEX_STRICT &&
                  (jsonContent.complexity === "SUPERCOMPLEX" ||
                   (jsonContent.type === "MULTI_PHASE" &&
                    String(resolveCurrentPhase(jsonContent)?.complexity) === "SUPERCOMPLEX"))
                // (5) v7 (Multi-Phase MVP): phase transition (MP-5) — next_agent = the
                //     first agent of the NEW phase's chain; effectiveStep still points
                //     into the OLD phase's pipeline → the mismatch is structural.
                const isPhaseTransitionMP = !!pState && pState.type === "MULTI_PHASE" &&
                  jsonContent.type === "MULTI_PHASE" &&
                  (pState.currentPhaseIdx ?? -1) >= 0 &&
                  Array.isArray(jsonContent.phases) &&
                  jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase) === (pState.currentPhaseIdx ?? -1) + 1 &&
                  String(nextAgent) === String((Array.isArray(jsonContent.pipeline) ? jsonContent.pipeline[0] : ""))
                // (6) v7: MULTI_PHASE in-phase Auto-DOCS hook (MP-4) — next_agent =
                //     "docs-writer" = newPipeline[0] of the canonical hook chain (case (3)
                //     isDocsHook keys on jsonContent.type === "DOCS", which never holds
                //     for MULTI_PHASE turns).
                const isDocsHookMP = !!pState && pState.type === "MULTI_PHASE" &&
                  jsonContent.type === "MULTI_PHASE" &&
                  JSON.stringify(jsonContent.pipeline ?? null) === JSON.stringify(DOCS_HOOK_CHAIN) &&
                  String(nextAgent) === "docs-writer" &&
                  (pState.currentStep >= pState.pipeline.length - 1)   // hook fires after the phase's final step
                // (7) v7: MULTI_PHASE in-phase BUGFIX continuation (MP-2) — same phase,
                //     prev pipeline ["bugfix-triage"], new pipeline = a BUGFIX variant
                //     (re-validated by validatePipeline), next_agent = newPipeline[1].
                const isBugfixContMP = !!pState && pState.type === "MULTI_PHASE" &&
                  jsonContent.type === "MULTI_PHASE" &&
                  (pState.currentPhaseIdx ?? -1) === (Array.isArray(jsonContent.phases)
                    ? jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase) : -2) &&
                  JSON.stringify(pState.pipeline) === JSON.stringify(["bugfix-triage"]) &&
                  String(nextAgent) === String((jsonContent.pipeline ?? [])[1] ?? "")
                if (!(isLoopback || isReworkSkip || isDocsHook || isSupercomplexExempt ||
                      isPhaseTransitionMP || isDocsHookMP || isBugfixContMP)) {
                  nextAgentMismatch = true  // Phase 9.3 → THROW via gate 9.0в
                  v6FlagSetThisEvent = true
                  violationDetail = `NEXT_AGENT MISMATCH at step ${effectiveStep} — ${nextAgentValidation.error}`
                }
                await client.app.log({
                  body: {
                    service: "workflow-enforcement",
                    level: "error",
                    message: `NEXT_AGENT VALIDATION FAILED — ${nextAgentValidation.error}`,
                    extra: { agent: currentAgent, nextAgent, pipeline, effectiveStep,
                      whitelisted: isLoopback || isReworkSkip || isDocsHook || isSupercomplexExempt ||
                        isPhaseTransitionMP || isDocsHookMP || isBugfixContMP }
                  }
                })
              }
            }
          }

          const validation = validateJSONOutput(jsonContent, currentAgent)

          if (!validation.valid) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: "INVALID JSON OUTPUT",
                extra: {
                  agent: currentAgent,
                  errors: validation.errors,
                  missingFields: validation.missingFields
                }
              }
            })
            // v6 (Phase 9.4): escalate log-only → deferred THROW (gate 9.0в). Previously
            // the violation blocked Task only INDIRECTLY (hasOutputtedJSON not set →
            // JSON-before-Task gate); the flag blocks ANY tool call directly.
            invalidJSON = true
            v6FlagSetThisEvent = true
            violationDetail = `INVALID JSON OUTPUT — errors: ${validation.errors.join("; ")}, missing: ${validation.missingFields.join(", ")}`
          } else {
            hasOutputtedJSON.set(currentAgent, true)

            // v7 (Multi-Phase MVP): confirmation gate ARMING — a VALID
            // AWAITING_CONFIRMATION JSON arms the gate; Task calls are blocked until
            // the user replies (direct throw in tool.execute.before — a throw here in
            // message.updated would be inert). Idempotent assignments; the warn is
            // deduped because message.updated re-fires per streaming chunk.
            if (currentAgent === "orchestrator" && String(jsonContent.type) === "MULTI_PHASE" &&
                String(jsonContent.state) === "AWAITING_CONFIRMATION") {
              const alreadyArmed = awaitingConfirmation && awaitingMsgId === (turnMsgId || null)
              awaitingConfirmation = true
              awaitingMsgId = turnMsgId || null
              if (!alreadyArmed) {
                await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                  message: "MULTI_PHASE AWAITING CONFIRMATION — Task calls blocked until the user replies",
                  extra: { agent: currentAgent, msgId: turnMsgId } } })
              }
            }
            // v7: CANCELLED — defensive disarm (normally already cleared by the new
            // messageID in the gate-clearing block)
            if (currentAgent === "orchestrator" && jsonContent?.state === "CANCELLED") {
              awaitingConfirmation = false
              awaitingMsgId = null
            }

            // v6 (Phase 9.0г-2): recovery — latest-message-wins. A clean valid-JSON
            // message clears message-derived deferred flags left by PREVIOUS messages /
            // early streaming chunks. Flags set during THIS event (v6FlagSetThisEvent)
            // survive. blockerStop is NOT cleared (cumulative session state, Phase 14.3).
            if (!v6FlagSetThisEvent) {
              pipelineMismatch = nextAgentMismatch = invalidJSON =
                forbiddenIdentity = pipelineImmutable = false
              violationDetail = ""
            }

            // v6 (correction F-10): messageID for dedup + observability (V-A11 verifies
            // the extraction; if empty, non-idempotent counters of Stage C stay disabled).
            const msgId = String((message as any).id || (message as any).info?.id || "")

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: "Valid JSON output detected — Task tool now allowed",
                extra: { agent: currentAgent, msgId }
              }
            })

            // ==========================================================
            // v6 (Phase 10.2 + 17.1 + 17.2): UNIFIED PIPELINE STATE BLOCK.
            // Runs AFTER validations, ONLY for valid JSON, ONCE per message (msgId dedup).
            // F-10: with an empty msgId the block still executes — every mutation below
            // is an idempotent ASSIGNMENT (never an increment), so streaming re-fires
            // cannot double-advance the step.
            // ==========================================================
            if (!msgId || !processedMessageIDs.has(msgId)) {
              if (msgId) processedMessageIDs.add(msgId)
              const prev = pipelineState.get(currentAgent)
              const newPipeline = Array.isArray(jsonContent.pipeline) ? jsonContent.pipeline as string[] : null
              const nextAgentIsAux = AUXILIARY_NEXT_AGENTS.includes(String(jsonContent.next_agent))
              // F-4: OUT OF SCOPE / no-pipeline turns and auxiliary turns (identity probes,
              // view-image) do NOT lock state — classification is not finished yet.
              // v8: + pipelineOk — an invalid pipeline must never be locked either
              // (deadlock fix; see the pipelineOk declaration above).
              if (pipelineOk && newPipeline && newPipeline.length > 0 && !nextAgentIsAux) {
                const nextIdx = jsonContent.next_agent
                  ? newPipeline.indexOf(String(jsonContent.next_agent)) : -1
                // F-4: classification turns with complexity=null (DECOMPOSITION Turn A,
                // codebase-analyzer helper, BUGFIX/DEVOPS Turn 1) lock a PROVISIONAL
                // pipeline — the next turn may replace it freely.
                // v7 fix (provisional trap — research §7.3-2, risk R9): top-level
                // complexity of MULTI_PHASE turns is ALWAYS null → without this guard
                // F-4 would allow ANY pipeline replacement for the whole multi-phase
                // session. MULTI_PHASE immutability is governed by the MP-1..MP-6
                // whitelist instead (below). Single-phase semantics unchanged.
                const provisional = (jsonContent.complexity === null || jsonContent.complexity === undefined) &&
                  String(jsonContent.type) !== "MULTI_PHASE"
                const newType = jsonContent.type !== undefined && jsonContent.type !== null
                  ? String(jsonContent.type) : null
                if (!prev) {
                  // Turn 1 — lock the pipeline (Phase 17.1: first valid JSON wins;
                  // the dedup guard above protects against streaming overwrites).
                  // v7 (Multi-Phase MVP): + phases[]/current_phase snapshot for the
                  // MP-1..MP-6 whitelist. For MULTI_PHASE the Turn-1 lock happens on
                  // the first EXECUTING turn (the AWAITING turn carries pipeline=[]
                  // and never locks state).
                  const mpPhases = newType === "MULTI_PHASE" && Array.isArray(jsonContent.phases)
                    ? jsonContent.phases : undefined
                  const mpIdx = newType === "MULTI_PHASE"
                    ? (Array.isArray(jsonContent.phases)
                        ? jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase)
                        : -1)
                    : undefined
                  pipelineState.set(currentAgent, {
                    pipeline: newPipeline,
                    currentStep: nextIdx >= 0 ? nextIdx : 0,
                    provisional,
                    type: newType,
                    // v8: classification snapshot for the Phase 17.2 self-heal
                    complexity: jsonContent.complexity ?? null,
                    planExists: jsonContent.plan_exists ?? null,
                    phases: mpPhases,
                    currentPhaseIdx: mpIdx
                  })
                  // v7: resume scenario (MULTI-PHASE Stage 5, prefer-new-session) —
                  // the session starts mid-chain; prior phase results must exist in
                  // PHASE_STATE.md (orchestrator reads it as a classification read).
                  if (mpIdx !== undefined && mpIdx > 0) {
                    await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                      message: `MULTI_PHASE RESUME DETECTED — current_phase ≠ phases[0]; verify prior phase results exist in PHASE_STATE.md`,
                      extra: { agent: currentAgent, currentPhaseIdx: mpIdx } } })
                  }
                } else if (JSON.stringify(newPipeline) !== JSON.stringify(prev.pipeline) ||
                    // v7 fix (test T16 — unchanged-pipeline phase jump): phases sharing an
                    // IDENTICAL chain (DEVOPS→DEVOPS, DEV-SIMPLE→DEV-SIMPLE) must still pass
                    // the MP-1..MP-6 whitelist. Previously such a turn landed in the
                    // unchanged-advance branch below, which blindly refreshed
                    // currentPhaseIdx — a phase SKIP (P1→P3) or a backward jump with an
                    // unchanged pipeline was silently accepted. Route any MULTI_PHASE turn
                    // whose phase index CHANGES into this whitelist branch: a legal +1
                    // transition gets full MP-5 semantics (stability check, counters +
                    // blockerStop reset, observability log); anything else fails closed.
                    // Single-phase turns (R4) never match — types are not MULTI_PHASE.
                    ((prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE") &&
                     Array.isArray(jsonContent.phases) &&
                     jsonContent.phases.findIndex((p: any) => p?.id === jsonContent?.current_phase) !== prev.currentPhaseIdx)) {
                  // Phase 17.2 — pipeline changed after being locked
                  // v7 (Multi-Phase MVP): TWO branches — a CLOSED whitelist MP-1..MP-6
                  // for MULTI_PHASE sessions (F-4 provisional does NOT apply — see the
                  // provisional fix above) vs the legacy single-phase exceptions
                  // (verbatim, UNCHANGED — R4 regression safety).
                  let isException: boolean
                  let mpCase: string | null = null
                  if (prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE") {
                    const newPhases = Array.isArray(jsonContent.phases) ? jsonContent.phases : []
                    const prevIdx = prev.currentPhaseIdx ?? -1
                    const newIdx = newPhases.findIndex((p: any) => p?.id === jsonContent?.current_phase)
                    const samePhase = prevIdx >= 0 && newIdx === prevIdx
                    const phaseAdvanced = prevIdx >= 0 && newIdx === prevIdx + 1   // MVP: strictly +1
                    const stableOrRefined = phasesStableOrRefined(prev.phases ?? [], newPhases, jsonContent?.current_phase)
                    const prevPhase = (prev.phases ?? [])[prevIdx]
                    const newPhase = newPhases[newIdx]
                    // MP-2: in-phase BUGFIX continuation (triage → expanded variant;
                    // variants are re-validated by validatePipeline)
                    const isBugfixContinuationMP = samePhase && String(prevPhase?.type) === "BUGFIX" &&
                      JSON.stringify(prev.pipeline) === JSON.stringify(["bugfix-triage"]) &&
                      newPipeline.length > 1 && newPipeline[0] === "bugfix-triage"
                    // MP-4: in-phase Auto-DOCS hook (canonical 2-agent chain only —
                    // mechanical check, safe)
                    const isDocsHookMP = samePhase && JSON.stringify(newPipeline) === JSON.stringify(DOCS_HOOK_CHAIN) &&
                      ["BUGFIX", "DEV"].includes(String(newPhase?.type ?? prevPhase?.type))
                    // MP-1/MP-3: phase refinement (null→resolved, once) / in-phase
                    // DECOMPOSITION dispatch
                    const isDecompMP = samePhase && (jsonContent.plan_source === "DECOMPOSITION" ||
                      (newPipeline.length === 1 && ["dev-planner", "codebase-analyzer"].includes(newPipeline[0])))
                    if (samePhase && stableOrRefined && (isDecompMP || isBugfixContinuationMP || isDocsHookMP ||
                        String(newPhase?.complexity) === "SUPERCOMPLEX" /* MP-6, F-11 parity — log-only */)) {
                      isException = true
                      mpCase = isDocsHookMP ? "MP-4 in-phase Auto-DOCS hook"
                        : isBugfixContinuationMP ? "MP-2 in-phase BUGFIX continuation"
                        : isDecompMP ? "MP-1/MP-3 phase refinement / DECOMPOSITION"
                        : "MP-6 SUPERCOMPLEX per-step re-emission"
                    } else if (phaseAdvanced && stableOrRefined) {
                      // MP-5: legal phase transition (+1, phases stable)
                      isException = true
                      mpCase = "MP-5 phase transition"
                    } else {
                      isException = false
                    }
                  } else {
                    isException =
                      prev.provisional ||                                     // F-4: provisional classification pipeline (single-phase only — v7)
                      jsonContent.type === "BUGFIX" ||                        // BUGFIX continuation (one-time expansion)
                      jsonContent.plan_source === "DECOMPOSITION" ||          // DECOMPOSITION Turn B (Q3)
                      jsonContent.severity === "nit" ||                       // nit-skip re-emission
                      (prev.type !== "DOCS" && newType === "DOCS") ||         // F-12: Auto-DOCS hook
                      (!SUPERCOMPLEX_STRICT && jsonContent.complexity === "SUPERCOMPLEX") // F-11 / R15
                  }
                  if (isException) {
                    // v6 (advisor Note 2): pipeline replacement = a new chain/stage
                    // context (SUPERCOMPLEX per-plan-step re-emission, BUGFIX
                    // continuation, DECOMPOSITION Turn B, Auto-DOCS hook; v7: MP-1..MP-6)
                    // → the previous rework loop is finished; reset its counters.
                    if ((reworkCount.get(currentAgent) || 0) > 0 || (blockerEscalations.get(currentAgent) || 0) > 0) {
                      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                        message: `REWORK/BLOCKER COUNTERS RESET — pipeline replaced, new loop context`,
                        extra: { agent: currentAgent } } })
                    }
                    reworkCount.delete(currentAgent)
                    blockerEscalations.delete(currentAgent)
                    // v7 (Multi-Phase MVP): blockerStop reset is SCOPED to the legal
                    // phase transition ONLY (MP-5 = new fail-fast context; resume after
                    // fail-fast in the SAME session — R10). Single-phase semantics
                    // "cumulative, only session.created clears" are UNCHANGED (V-17).
                    // The detail is cleared only if THIS message set no other flag
                    // (otherwise the fresh violation detail must survive).
                    if (mpCase === "MP-5 phase transition" && blockerStop) {
                      blockerStop = false
                      if (!v6FlagSetThisEvent) violationDetail = ""
                      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                        message: "BLOCKERSTOP RESET — legal multi-phase transition (new phase = new fail-fast context)" } })
                    }
                    if (mpCase) {
                      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                        message: `MULTI_PHASE MUTATION ALLOWED — ${mpCase}`, extra: { agent: currentAgent, mpCase } } })
                    }
                    maxStepReached.set(currentAgent, nextIdx >= 0 ? nextIdx : 0)
                    prev.pipeline = newPipeline
                    // F-1: currentStep = indexOf(next_agent), NO "-1". The message
                    // announces the dispatch happening NOW — after this turn the last
                    // dispatched agent is next_agent itself. (The "-1" variant of the
                    // source plan produced a false NEXT_AGENT MISMATCH on BUGFIX
                    // continuation Turn 3; DECOMPOSITION re-dispatch is covered by the
                    // isLoopback whitelist in 10.3.)
                    if (nextIdx >= 0) prev.currentStep = nextIdx
                    prev.provisional = provisional
                    prev.type = newType
                    // v8: keep the classification snapshot in sync with the
                    // replaced pipeline (the Phase 17.2 self-heal relies on it)
                    prev.complexity = jsonContent.complexity ?? null
                    prev.planExists = jsonContent.plan_exists ?? null
                    // v7: refresh the multi-phase snapshot (refined phases + new index)
                    if (newType === "MULTI_PHASE") {
                      prev.phases = Array.isArray(jsonContent.phases) ? jsonContent.phases : prev.phases
                      const idx = (prev.phases ?? []).findIndex((p: any) => p?.id === jsonContent?.current_phase)
                      if (idx >= 0) prev.currentPhaseIdx = idx
                    }
                  } else {
                    // v8 self-heal: if the LOCKED baseline is itself invalid, the
                    // lock is poisoned — replace it with the incoming pipeline
                    // instead of throwing (heals deadlocked sessions). The
                    // baseline is re-validated against ITS OWN locked
                    // classification snapshot (never the current turn's), so a
                    // legitimate mid-flight re-classification still fails closed.
                    const baselineStillValid = validatePipeline(
                      currentAgent,
                      prev.type,
                      prev.complexity ?? null,
                      prev.planExists ?? null,
                      prev.pipeline,
                      prev.type === "MULTI_PHASE"
                        ? { ...jsonContent, state: null, phases: prev.phases,
                            current_phase: (prev.phases ?? [])[prev.currentPhaseIdx ?? -1]?.id ?? null,
                            plan_source: null }
                        : { ...jsonContent, plan_source: null }
                    ).valid
                    if (!baselineStillValid) {
                      await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                        message: "SELF-HEAL RECAPTURE — locked baseline pipeline is INVALID (poisoned lock); replacing it with the incoming pipeline",
                        extra: { agent: currentAgent, poisonedBaseline: prev.pipeline, incomingPipeline: newPipeline } } })
                      reworkCount.delete(currentAgent)
                      blockerEscalations.delete(currentAgent)
                      maxStepReached.set(currentAgent, nextIdx >= 0 ? nextIdx : 0)
                      prev.pipeline = newPipeline
                      prev.currentStep = nextIdx >= 0 ? nextIdx : 0
                      prev.provisional = provisional
                      prev.type = newType
                      prev.complexity = jsonContent.complexity ?? null
                      prev.planExists = jsonContent.plan_exists ?? null
                      if (newType === "MULTI_PHASE") {
                        prev.phases = Array.isArray(jsonContent.phases) ? jsonContent.phases : prev.phases
                        const idx = (prev.phases ?? []).findIndex((p: any) => p?.id === jsonContent?.current_phase)
                        if (idx >= 0) prev.currentPhaseIdx = idx
                      }
                    } else {
                      pipelineImmutable = true
                      v6FlagSetThisEvent = true
                      violationDetail = (prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE")
                        ? `PIPELINE IMMUTABLE (MULTI_PHASE): illegal mutation — allowed: phase refinement (null→resolved, once), in-phase BUGFIX continuation / DECOMPOSITION / Auto-DOCS hook, phase transition (+1, phases stable). Got: [${prev.pipeline.join(", ")}] → [${newPipeline.join(", ")}], current_phase idx ${prev.currentPhaseIdx} → ${jsonContent?.current_phase}`
                        : `PIPELINE IMMUTABLE: pipeline changed after Turn 1 — [${prev.pipeline.join(", ")}] → [${newPipeline.join(", ")}] (exceptions: provisional classification, BUGFIX continuation, DECOMPOSITION, nit-skip, Auto-DOCS hook)`
                    }
                  }
                } else if (nextIdx >= 0) {
                  // pipeline unchanged — advance the step to the actual next_agent
                  // (single rule covers forward moves, rework loopbacks and nit-skip).
                  // v6 (advisor Note 2): a NEW rework-loop context begins when
                  // (a) the step advances PAST the previous maximum (the loop for the
                  // prior stage is finished), or (b) the step jumps BACKWARD by >= 2
                  // (a new chain cycle — SUPERCOMPLEX per-plan-step re-dispatch of an
                  // early agent with an identical re-emitted array; rework loopbacks
                  // are always -1 hops reviewer<->rework and do NOT reset).
                  const prevMax = maxStepReached.get(currentAgent) ?? prev.currentStep
                  if (nextIdx > prevMax || prev.currentStep - nextIdx >= 2) {
                    if ((reworkCount.get(currentAgent) || 0) > 0 || (blockerEscalations.get(currentAgent) || 0) > 0) {
                      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                        message: `REWORK/BLOCKER COUNTERS RESET — new loop context (step ${prev.currentStep} → ${nextIdx}, max ${prevMax})`,
                        extra: { agent: currentAgent, from: prev.currentStep, to: nextIdx, prevMax } } })
                    }
                    reworkCount.delete(currentAgent)
                    blockerEscalations.delete(currentAgent)
                  }
                  maxStepReached.set(currentAgent, Math.max(prevMax, nextIdx))
                  prev.currentStep = nextIdx
                  // v7 fix (advisor MP-1 "refinement once per phase"): a phase
                  // refinement (complexity/plan_exists null→resolved) does NOT
                  // change the pipeline agent array, so this turn lands in the
                  // "pipeline unchanged" branch — yet the phases snapshot MUST be
                  // refreshed here too. Otherwise the stale nulls let
                  // `phasesStableOrRefined` accept the same refinement again on a
                  // later turn (unbounded refinement). This mirrors the legal-
                  // mutation branch above (refresh phases + recompute the index
                  // from current_phase id; never assign the id as an index).
                  // Guard = the multiphase context, on either side of the turn.
                  if (prev.type === "MULTI_PHASE" || newType === "MULTI_PHASE") {
                    if (Array.isArray(jsonContent.phases)) prev.phases = jsonContent.phases
                    const idx = (prev.phases ?? []).findIndex((p: any) => p?.id === jsonContent?.current_phase)
                    if (idx >= 0) prev.currentPhaseIdx = idx
                  }
                  // v8: classification snapshot refresh (pipeline unchanged —
                  // a refinement turn may re-declare complexity/plan_exists)
                  prev.complexity = jsonContent.complexity ?? null
                  prev.planExists = jsonContent.plan_exists ?? null
                }
              }
            }

            // v6 (Phase 16): strict ack format audit (WARN-ONLY — never blocks; a
            // measurable format-drift signal before any future escalation). Only for
            // delegation turns (next_agent truthy); OUT OF SCOPE and final turns
            // (next_agent=null) require no ack. Correction F-5 — NINE legal ack variants
            // verified against the CURRENT prompts (post-Part I; v7 Multi-Phase adds 7–9):
            //   1. "→ DELEGATED to <agent> for: <goal>"                 (both TURN ALGORITHMs)
            //   2. "→ STEP <i>/<N> (<id>): DELEGATED to <agent>"        (orchestrator SUPERCOMPLEX Stage 2)
            //   3. "→ DELEGATED to advisor (step <N>, notes so far: <c>)" (orchestrator ADVISOR STEP RULES)
            //   4. "→ rework SKIPPED (dev-reviewer severity=nit)"       (orchestrator SEVERITY RULES)
            //   5. "→ SUPERCOMPLEX steps (<N>): [...] (source: ...)"    (orchestrator SUPERCOMPLEX Stage 1 echo)
            //   6. "→ DECOMPOSITION requested from dev-planner for: <goal>" (orchestrator Q3)
            //   7. "→ PHASE <i>/<n> (<id>): DELEGATED to <agent> for: <goal>"           (v7 MULTI-PHASE Stage 2–4)
            //   8. "→ PHASE <i>/<n> (<id>), STEP <j>/<m> (<sid>): DELEGATED to <agent>" (v7 SUPERCOMPLEX inside a phase)
            //   9. "→ PHASE PLAN AWAITING CONFIRMATION (<n> phases)"                    (v7 AWAITING turn; future-proof — next_agent=null skips the audit today)
            // `[\w-]+` (not `\w+`) — agent names contain hyphens (plan-writer-simple).
            // Post-ack prose checking ("no analysis after the ack") is OUT of scope (R16).
            if (jsonContent.next_agent && msgId && !processedMessageIDs.has(msgId + ":ack")) {
              processedMessageIDs.add(msgId + ":ack")
              const ackContent = String(message.content || message.text || "")
              // v7: + optional "PHASE <i>/<n> (<id>)" prefix with ":" OR "," separator
              // (forms 7–8), + barrier form "PHASE <i>/<n> (<id>): <STATUS>" and
              // "PHASE PLAN AWAITING CONFIRMATION (<n> phases)" (form 9).
              // FIX of the master-plan regex (deviation B): the prefix MUST accept ":"
              // — "PHASE 1/2 (P1): DELEGATED …" is the primary phase-ack form; the
              // plan's "(?:,\s*)?" matched only the comma form and would warn on every
              // phase delegation (T24). Old forms 1–6 are untouched (regression-safe).
              const ackPattern = /^→ (?:(?:PHASE \d+\/\d+\s*\([^)]*\)\s*(?::\s*|,\s*))?(?:(?:STEP \d+\/\d+\s*(?:\([^)]*\))?\s*:\s*)?DELEGATED to [\w-]+(?:\s*\(step [^)]*\)| for: .+)?|PHASE \d+\/\d+\s*\([^)]*\)\s*:\s*[A-Z+]+|PHASE PLAN AWAITING CONFIRMATION \(\d+ phases?\)|DECOMPOSITION requested from [\w-]+ for: .+|rework SKIPPED \(.+\)|SUPERCOMPLEX steps \(\d+\):.*\(source: .+\)))\s*$/m
              if (!ackPattern.test(ackContent)) {
                await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                  message: `ACK FORMAT INVALID — ${currentAgent}: expected one of the 9 legal ack forms (see the Phase 16 comment)`,
                  extra: { agent: currentAgent, excerpt: ackContent.slice(0, 200) } } })
              }
            }
          }
        }

        // Forbidden-vocabulary sanity check: if the locked agent's message contains
        // terminology that belongs to the OTHER primary agent, log a hard error.
        // This catches the orchestrator→plankestrator and plankestrator→orchestrator
        // confusion mode where the model produces text from the wrong agent's playbook.
        if (identityLocked && lockedAgentName && message) {
          const content = String(message.content || message.text || "")
          const otherAgent = lockedAgentName === "orchestrator" ? "plankestrator" : "orchestrator"
          const forbidden = FORBIDDEN_VOCAB[lockedAgentName] || []
          const violations = forbidden.filter(token => content.includes(token))

          if (violations.length > 0) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: `FORBIDDEN VOCABULARY DETECTED — ${lockedAgentName} message contains ${otherAgent} terminology`,
                extra: {
                  lockedAgent: lockedAgentName,
                  otherAgent,
                  violations,
                  excerpt: content.slice(0, 200)
                }
              }
            })
            // v6 (Phase 9.5): we do NOT throw for AGENT-NAME tokens — legitimate
            // cross-references exist (e.g. orchestrator mentioning "plan-writer" in an
            // OUT OF SCOPE message); downstream checks (identity drift, routing table)
            // catch the actual violation. IDENTITY-claim tokens DO escalate — via the
            // deferred forbiddenIdentity flag consumed by gate 9.0в.
            // TS2538: narrowing of the mutable `let lockedAgentName` is not
            // preserved inside this callback, even though line 965 guards it.
            // Non-null assertion is safe: the enclosing `if` guarantees it's a string.
            const identityViolations = violations.filter(t =>
              (FORBIDDEN_IDENTITY_TOKENS[lockedAgentName!] || []).includes(t))
            if (identityViolations.length > 0) {
              forbiddenIdentity = true
              violationDetail = `FORBIDDEN IDENTITY CLAIM — ${lockedAgentName} message claims foreign identity: ${identityViolations.join(", ")}`
            }
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

    // ==========================================================
    // "tool.execute.before" — routing table enforcement
    // ==========================================================
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      // HARD BAN: .md / .markdown edits — DOCS_WHITELIST only. Проверка ДО
      // depth-guard'а ниже: tool-вызовы субагента
      // (activeTaskDepth > 0) атрибутируются по вершине subagentStack —
      // по одному currentAgent вышло бы родительское имя (orchestrator) и
      // docs-writer блокировался бы сам. Блок прямым throw — конвенция
      // остальных gate'ов этого хука (a throw in tool.execute.before blocks
      // the call itself).
      if (input.tool === "edit" || input.tool === "write" || input.tool === "patch") {
        const filePath = String((output as any)?.args?.filePath || (input as any)?.args?.filePath
          || (input as any).path || (input as any).file || "")
        if (filePath.endsWith(".md") || filePath.endsWith(".markdown")) {
          const actingAgent = subagentStack.length > 0
            ? subagentStack[subagentStack.length - 1]
            : currentAgent
          if (!DOCS_WHITELIST.includes(actingAgent ?? "")) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: `DOCUMENTATION VIOLATION — ${actingAgent ?? "unknown"} attempted ${input.tool} on ${filePath}`,
                extra: { agent: actingAgent ?? null, tool: input.tool, filePath }
              }
            })
            throw new Error(`
⛔ DOCUMENTATION VIOLATION: ${actingAgent ?? "unknown"} cannot edit .md files.
Only ${DOCS_WHITELIST.join(", ")} can modify documentation.
Use requires_docs_update: true to trigger Auto-DOCS hook.
            `)
          }
        }
      }

      // v4: пока выполняется Task-субагент (activeTaskDepth > 0), ЛЮБОЙ tool-вызов
      // принадлежит субагенту, а не locked primary-агенту (родитель приостановлен
      // в ожидании результата). Enforcement атрибутирован только родительской
      // сессии → пропускаем. Вложенные делегирования (субагент → суб-субагент)
      // поддерживают баланс счётчика: +1 здесь, -1 в tool.execute.after.
      if (activeTaskDepth > 0) {
        if (input.tool === "task") {
          // v6 (Phase 13.2б): caller attribution — a parallel Task from the PRIMARY
          // (top-level session) is a violation; a nested delegation from a RUNNING
          // subagent (child session) is legitimate (research-writer-complex scout wave —
          // RESEARCH COMPLEX row 4/6 plankestrator; ARCHITECTURE.md §2 Internal fan-out).
          // F-3: the throw MUST happen BEFORE `activeTaskDepth += 1` — a blocked call
          // never executes, so tool.execute.after never fires; incrementing first would
          // leak depth > 0 forever and silently disable ALL enforcement.
          const callerSessionID = String((input as any).sessionID || "") || null
          if (topLevelSessionID && callerSessionID && callerSessionID === topLevelSessionID) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: `PARALLEL TASK FROM PRIMARY BLOCKED — ${currentAgent} (depth=${activeTaskDepth})`,
                extra: { agent: currentAgent, depth: activeTaskDepth, callerSessionID, topLevelSessionID }
              }
            })
            throw new Error(`
⛔ PARALLEL TASK CALL BLOCKED — a subagent is already running (depth=${activeTaskDepth}).
Primary agent dispatches EXACTLY ONE Task per turn and waits for the result.
            `)
          }
          subagentStack.push(String((output as any)?.args?.subagent_type
            || (input as any)?.args?.subagent_type || "unknown"))
          activeTaskDepth += 1
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "TASK CALL WHILE SUBAGENT ACTIVE — routing check skipped (nested delegation, or prohibited parallel Task from primary agent)",
              extra: { depth: activeTaskDepth, callerSessionID, topLevelSessionID }
            }
          })
        }
        return
      }

      // BYPASS: Built-in OpenCode Plan mode (Shift+Tab toggle).
      // In Plan mode the user is on the default primary agent (e.g. "build")
      // with read-only restrictions enforced by OpenCode itself. Custom agent
      // routing tables and JSON-output requirements do NOT apply here.
      if (currentMode === "plan") {
        const targetForLog = input.tool === "task"
          ? ((output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type)
          : undefined
        workflowSteps.push({
          timestamp,
          tool: input.tool,
          agent: "plan-mode-bypass",
          target: targetForLog
        })
        return
      }

      // v6 (Phase 9.0в): UNIFIED DEFERRED-VIOLATION GATE — consumes flags set in
      // message.updated. A throw inside the event hook is inert (the message is already
      // sent); only THIS throw blocks the real action. The depth-bypass above guarantees
      // only primary-agent calls at activeTaskDepth === 0 reach here — subagent tool
      // calls are never blocked for the primary's violations. Consume-once: flags are
      // reset right before the throw, so a corrected message passes on the next call.
      if (currentAgent && (identityMissing || pipelineMismatch || nextAgentMismatch ||
          invalidJSON || forbiddenIdentity || pipelineImmutable || blockerStop)) {
        const code = identityMissing ? "IDENTITY MISSING"
          : pipelineMismatch ? "PIPELINE VALIDATION FAILED"
          : nextAgentMismatch ? "NEXT_AGENT MISMATCH"
          : invalidJSON ? "INVALID JSON OUTPUT"
          : forbiddenIdentity ? "FORBIDDEN IDENTITY CLAIM"
          : pipelineImmutable ? "PIPELINE IMMUTABLE"
          : "BLOCKER STOP AFTER 3"
        await client.app.log({ body: { service: "workflow-enforcement", level: "error",
          message: `DEFERRED VIOLATION ENFORCED — ${code}`,
          extra: { agent: currentAgent, detail: violationDetail, attemptedTool: input.tool } } })
        const detail = violationDetail
        identityMissing = pipelineMismatch = nextAgentMismatch = invalidJSON =
          forbiddenIdentity = pipelineImmutable = blockerStop = false
        violationDetail = ""
        throw new Error(`
⛔ WORKFLOW VIOLATION — ${code}

${detail}

Your previous message violated plugin validation and was REJECTED before any tool
could run. Fix: re-issue a corrected message in the required order:
1. "IDENTITY VERIFIED: I am ${currentAgent}..."
2. Valid JSON block (all required fields, pipeline per PIPELINE TABLE)
3. THEN the Task call.
        `)
      }

      // v7 (Multi-Phase MVP): CONFIRMATION GATE — direct throw (blocks the call itself;
      // a throw inside message.updated would be inert). Scope: Task ONLY — read/glob/grep
      // stay legal (re-planning on edit rounds may need a classification read).
      // Same-turn violation: the AWAITING JSON and a Task call in one message share the
      // messageID → the gate is still armed. Placed AFTER gate 9.0в (deferred violations
      // take priority) and BEFORE the Phase 13.2 counter (a blocked call must not
      // consume the per-turn Task quota).
      if (awaitingConfirmation && currentAgent === "orchestrator" && input.tool === "task") {
        await client.app.log({ body: { service: "workflow-enforcement", level: "error",
          message: "CONFIRMATION GATE — Task blocked while AWAITING_CONFIRMATION",
          extra: { agent: currentAgent, awaitingMsgId } } })
        throw new Error(`
⛔ AWAITING USER CONFIRMATION (MULTI_PHASE):
You presented a phase plan with state="AWAITING_CONFIRMATION". Do NOT dispatch any
Task until the USER replies. Your turn ended with the plan + ack line.
On the user's approval: identity line → JSON (state: null, current_phase: "P1",
pipeline = P1's chain, next_agent = pipeline[0]) → ONE Task call.
        `)
      }

      // v6 (Phase 13.2): max ONE Task call per turn (PROHIBITIONS of both primaries:
      // "No more than ONE Task call per turn"). Only at activeTaskDepth === 0 — the
      // depth-bypass above already filtered subagent calls (correction 13.2(а): a nested
      // scout wave is legitimate). Turn boundary = a NEW primary message (13.3 dedup by
      // messageID). The counter increments only for allowed calls; calls blocked by
      // downstream gates (JSON-before-Task, routing) reset with the next message anyway.
      if (input.tool === "task" &&
          (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {
        // v6 (advisor Note 3 fix): the per-turn counter is meaningful ONLY when
        // messageID extraction works — the 13.3 turn-boundary reset keys on the
        // message id. If extraction yields "" (payload shape changed), the counter
        // would NEVER reset and block the 2nd Task call of the entire SESSION.
        // Degrade explicitly (F-10 philosophy: no observability → Stage C counter
        // disabled): skip the gate with a warn instead of a stuck hard block.
        if (!lastTurnMessageID.has(currentAgent)) {
          await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
            message: `TURN TRACKING DEGRADED — messageID unavailable for ${currentAgent}; max-one-Task-per-turn gate DISABLED (no false block)`,
            extra: { agent: currentAgent } } })
        } else {
          const count = taskCallsPerTurn.get(currentAgent) || 0
          if (count >= 1) {
            await client.app.log({ body: { service: "workflow-enforcement", level: "error",
              message: `SECOND TASK CALL IN SAME TURN — ${currentAgent} (count=${count})`,
              extra: { agent: currentAgent, count } } })
            throw new Error(`
⛔ MAX ONE TASK CALL PER TURN: already made 1 Task call in this turn.
Wait for the subagent result, then issue the NEXT message:
identity line → JSON → ONE Task call → ack.
            `)
          }
          taskCallsPerTurn.set(currentAgent, count + 1)
        }
      }

      // NEW: Track first Task call for primary agents
      if (input.tool === "task" && (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {
        primaryAgentFirstTaskCall.set(currentAgent, true)
      }

      // NEW: Block analysis tools (read/grep/glob) for primary agents after first Task call
      // Primary agents should only classify and route, not analyze after delegation
      if ((input.tool === "read" || input.tool === "grep" || input.tool === "glob") &&
          (currentAgent === "orchestrator" || currentAgent === "plankestrator") &&
          primaryAgentFirstTaskCall.get(currentAgent)) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "error",
            message: `ANALYSIS AFTER DELEGATION — ${currentAgent} attempted ${input.tool} after first Task call`,
            extra: { agent: currentAgent, tool: input.tool }
          }
        })
        throw new Error(`
⛔ ANALYSIS AFTER DELEGATION — PLUGIN ENFORCEMENT

Primary agents (orchestrator/plankestrator) must NOT use read/grep/glob after the first Task call.

Workflow:
1. Turn 1: Analyze (read/grep/glob allowed) → classify → JSON → Task
2. Turns 2+: Receive result → JSON with next_agent → Task (NO analysis)

You have already delegated to a subagent. Now you should only route, not analyze.

This is enforced by the workflow-enforcement plugin.
        `)
      }

      // v6 (Phase 12.2): self-work consumption for orchestrator (mirror of the
      // plankestrator branch in the INSPECTION GATE below). Without this block Phase
      // 12.1 would be log-only: the existing consumption is locked inside the
      // plankestrator-only INSPECTION GATE. ONLY inspection tools are blocked; Task
      // calls are NOT — delegation IS the desired correction (v4 semantics).
      // Real added value: Turn 1 BEFORE the first Task (after it, inspections are
      // already blocked by the read-lock above).
      if (selfWorkDetected && lockedAgentName === "orchestrator" &&
          (input.tool === "read" || input.tool === "grep" || input.tool === "glob")) {
        await client.app.log({ body: { service: "workflow-enforcement", level: "error",
          message: `INSPECTION BLOCKED — self-work content detected in previous orchestrator message`,
          extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool } } })
        throw new Error(`
⛔ SELF-WORK CONTENT DETECTED IN YOUR PREVIOUS MESSAGE

You are running as: orchestrator (identity-locked).
Your last message contained analysis/implementation markers (e.g. "## Findings",
"## Analysis", "## Implementation", "## Root Cause"). Producing such CONTENT is
self-work — it belongs to worker / dev-planner / bugfix-triage / docs-writer, NOT to you.

Fix: Identity line → JSON block → ONE Task call with next_agent from your routing table → ack line.
        `)
      }

      // HARD GATE: primary agents (orchestrator / plankestrator) are restricted at
      // the frontmatter level. The model CAN use inspection tools (task, read, glob,
      // grep) to make good routing decisions. The model CANNOT use action tools
      // (bash, edit, write, webfetch, todowrite, question) — those are worker/
      // specialist tools. If something bypasses the frontmatter (opencode.json
      // override, MCP tool added later, future tool), this runtime gate catches it.
      const PRIMARY_AGENT_ALLOWED_TOOLS = new Set(["task", "read", "glob", "grep"])
      if (
        identityLocked &&
        (lockedAgentName === "orchestrator" || lockedAgentName === "plankestrator") &&
        !PRIMARY_AGENT_ALLOWED_TOOLS.has(input.tool)
      ) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "error",
            message: `PRIMARY AGENT ACTION TOOL VIOLATION — ${lockedAgentName} tried to call "${input.tool}"`,
            extra: {
              lockedAgent: lockedAgentName,
              attemptedTool: input.tool,
              allowedTools: Array.from(PRIMARY_AGENT_ALLOWED_TOOLS),
              rule: "primary agents MAY inspect (task/read/glob/grep) but MUST NOT act (bash/edit/write/etc.)"
            }
          }
        })
        throw new Error(`
⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL

You are running as: ${lockedAgentName}
You tried to call: ${input.tool}

${lockedAgentName} is a PRIMARY AGENT. Action tools are FORBIDDEN — only inspection is allowed.

Allowed (read-only / delegation):
   - task     (delegate to a specialist subagent)
   - read     (inspect a file to inform routing)
   - glob     (list files to assess scope)
   - grep     (find references to inform classification)

Forbidden (action tools — these belong to specialist agents):
   - bash, edit, write, webfetch, todowrite, question, and any MCP action tool

Why: inspection helps you choose the right pipeline. Action tools (running commands,
     editing files, writing code) are for specialist agents like worker, bugfix,
     execute-bug, devops-agent, docs-writer, plan-writer-*, research-writer-*.

Fix: do NOT call ${input.tool} directly. Instead, call Task with the appropriate
     subagent_type from your routing table:
${(ROUTING_TABLES[lockedAgentName as keyof typeof ROUTING_TABLES] || []).map(a => `       - ${a}`).join("\n")}
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

      // REMOVED: state mutation from reverse routing lookup.
      //
      // The previous implementation set currentAgent based on which subagent
      // was called, assuming any task call to a whitelisted subagent must
      // come from the matching primary agent. That assumption is wrong:
      // build/plan/custom agents can ALSO call task with the same subagent
      // names (e.g. "worker", "plan-writer-simple"). Setting currentAgent
      // via reverse routing incorrectly locked build agents as orchestrator/
      // plankestrator, causing subsequent edit/write/bash to be blocked by
      // the HARD BLOCK enforcement below.
      //
      // Race conditions (where session.created has not detected yet but
      // the orchestrator/plankestrator is about to call task) are handled by:
      //   - session.created state reset (no stale lock from previous session)
      //   - The `if (!currentAgent) return` early-out at the routing check,
      //     which means unknown agents proceed without enforcement
      //
      // Kept as a hint-only diagnostic. NO state mutation:
      if (!currentAgent && input.tool === "task") {
        const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type
        if (targetAgent) {
          const detected = detectAgentFromSubagent(targetAgent)
          if (detected) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Reverse routing hint (not enforced): ${detected} would be inferred from subagent ${targetAgent}`,
                extra: {
                  targetAgent,
                  hint: detected,
                  note: "currentAgent not mutated — unknown agent proceeds without enforcement"
                }
              }
            })
          }
        }
      }

      // Track this tool call in the workflow log
      const targetForLog = input.tool === "task"
        ? ((output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type)
        : undefined

      workflowSteps.push({
        timestamp,
        tool: input.tool,
        agent: currentAgent || "unknown",
        target: targetForLog
      })

      // ==========================================================
      // NOTE: Gate A (above, lines ~463-507) already enforces that
      // primary agents MAY use {task, read, glob, grep} and MUST NOT
      // use {bash, edit, write, webfetch, patch}. No second gate
      // needed here — adding one caused Gate B vs Gate A
      // contradiction that blocked read/glob/grep despite the prompt
      // advertising them as allowed inspection tools.
      //
      // Primary agents that need heavy investigation should still
      // delegate to mcp-read / mcp-search / devops-readonly via Task —
      // direct read/glob/grep is a convenience for quick lookups, not
      // a substitute for delegation.
      // ==========================================================

      const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type

      if (!currentAgent) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "warn",
            message: "Current agent not detected, cannot enforce routing table"
          }
        })
        return
      }

      // Block execution tools (edit/write/bash/patch) before JSON classification.
      // Analysis tools (read/grep/glob) are ALLOWED before JSON — they are the
      // instruments of the ANALYZE step; execution must follow classification.
      if (input.tool === "edit" || input.tool === "write" || input.tool === "bash" || input.tool === "patch") {
        const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
        if (!agentJSONStatus) {
          throw new Error(`
⛔ CLASSIFICATION REQUIRED — PLUGIN ENFORCEMENT

Primary agents (orchestrator/plankestrator) must classify the task BEFORE executing.

Workflow:
1. Analyze the task using read/grep/glob (allowed)
2. Build the pipeline (determine which agents to call)
3. Output JSON with classification (type, complexity, pipeline)
4. THEN use execution tools (via Task delegation)

Direct execution without classification violates the routing contract.
          `)
        }
      }

      // Task tool requires JSON (classification must come first)
      if (input.tool === "task") {
        const AUXILIARY_TASK_TARGETS = [...IDENTITY_PROBE_AGENTS, "view-image"]
        const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
        if (!agentJSONStatus && targetAgent && !AUXILIARY_TASK_TARGETS.includes(targetAgent)) {
          throw new Error(`
⛔ JSON OUTPUT REQUIRED — PLUGIN ENFORCEMENT

You MUST output valid JSON BEFORE calling the Task tool.

Workflow:
1. Analyze the task using read/grep/glob (allowed)
2. Build the pipeline (determine which agents to call)
3. Output JSON with classification (type, complexity, pipeline)
4. THEN call Task tool with the first agent

This is enforced by the workflow-enforcement plugin.
        `)
        }
      }

      // Only enforce routing on "task" tool calls (agent delegation)
      if (input.tool !== "task") return

      // v6 (Phase 14.2): rework loop max 3 (orchestrator.md SEVERITY RULES: "if a blocker
      // persists after the 3rd rework iteration → STOP and report failure to the user").
      // A DIRECT throw is legitimate here — tool.execute.before blocks the call itself.
      // Note on ordering: the counter increments BEFORE the downstream gates
      // (JSON-before-Task, routing-table) — a 4th rework blocked by one of those would
      // still count. Accepted: a rework call without JSON / off-table is already a
      // violation; exact counting in a crashed session is irrelevant.
      if (targetAgent === "rework") {
        const count = reworkCount.get(currentAgent) || 0
        if (count >= 3) {
          await client.app.log({ body: { service: "workflow-enforcement", level: "error",
            message: `REWORK LOOP MAX 3 EXCEEDED — ${currentAgent} (count=${count})`,
            extra: { agent: currentAgent, count } } })
          throw new Error(`
⛔ REWORK LOOP MAX 3: rework already invoked 3 times for THIS pipeline stage.
The blocker is persistent — STOP the loop and escalate to the user:
final summary with the unresolved findings (BLOCKER ack format per SEVERITY RULES).
          `)
        }
        reworkCount.set(currentAgent, count + 1)
      }

      // BUILT-IN OPENCODE AGENTS — never block these, even when enforcement is active.
      // These are native OpenCode subagents (not custom agents in our routing tables)
      // and are safe to call from any primary agent / mode, including built-in Plan mode.
      const BUILTIN_OPENCODE_AGENTS = ["explore", "general"]
      if (targetAgent && BUILTIN_OPENCODE_AGENTS.includes(targetAgent)) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "info",
            message: `Bypass: built-in OpenCode agent ${targetAgent} (routing bypassed)`,
            extra: { currentAgent, mode: currentMode }
          }
        })
        subagentStack.push(targetAgent)
        activeTaskDepth += 1 // v4: built-in агент (explore/general) тоже субагент
        return
      }

      // Check: target agent must be in the current agent's routing table
      const allowedAgents = ROUTING_TABLES[currentAgent as keyof typeof ROUTING_TABLES] || []
      if (targetAgent && !allowedAgents.includes(targetAgent)) {
        // FALLBACK: Check if targetAgent is in the OTHER agent's whitelist
        // (race condition mitigation — message.updated may not have fired yet)
        const otherAgent = currentAgent === "orchestrator" ? "plankestrator" : "orchestrator"
        const otherAllowedAgents = ROUTING_TABLES[otherAgent as keyof typeof ROUTING_TABLES] || []
        
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
          // Neither whitelist includes targetAgent → genuine violation
          throw new Error(`
WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT

Current Agent: ${currentAgent}
Attempted Call: ${targetAgent}
Allowed Agents: ${allowedAgents.join(", ")}

This violates the routing table configuration.
Please follow the correct workflow for your agent type.

Orchestrator handles: BUGFIX, DEVOPS, DEV, DOCS
Plankestrator handles: PLAN, RESEARCH, RESEARCH+PLAN
          `)
        }
      }

      // v5 (OMP P0-3): инъекция указателя контекстного файла в Task-prompt
      // reviewer-агентам. Если мутация output.args не поддержана рантаймом —
      // не страшно: промпты reviewer'ов содержат самостоятельное чтение файла.
      if (targetAgent && CONTEXT_FILE_AGENTS.includes(targetAgent)) {
        const taskArgs = (output as any)?.args
        if (taskArgs && typeof taskArgs.prompt === "string" && !taskArgs.prompt.includes(REVIEW_CONTEXT_FILE)) {
          taskArgs.prompt = `[CONTEXT FILE] Before starting, read ${REVIEW_CONTEXT_FILE} in the project root (if absent — ~/.config/opencode/${REVIEW_CONTEXT_FILE}). It contains reviewer-specific priorities, known traps and the severity taxonomy. Then proceed with the task below.\n\n` + taskArgs.prompt
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Context file pointer injected into Task prompt for ${targetAgent} (${REVIEW_CONTEXT_FILE})`,
              extra: { targetAgent, contextFile: REVIEW_CONTEXT_FILE }
            }
          })
        }
      }

      // v4: родительский Task-вызов прошёл routing — сейчас запустится субагент.
      // Пока activeTaskDepth > 0, все tool-вызовы и сообщения принадлежат СУБАГЕНТУ
      // (родитель приостановлен) → enforcement для них подавляется (см. depth-guard).
      subagentStack.push(String(targetAgent || "unknown"))
      activeTaskDepth += 1

      // Log valid routing
      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Valid routing: ${currentAgent} → ${targetAgent}`,
          extra: { allowed: true }
        }
      })
    },

    // ==========================================================
    // "tool.execute.after" — log tool completion
    // ==========================================================
    "tool.execute.after": async (input, output) => {
      // v4: Task-субагент завершён (успешно или с ошибкой — after-хук fires в обоих
      // случаях, см. success-флаг ниже) → вернуть enforcement в родительскую сессию.
      if (input.tool === "task") {
        activeTaskDepth = Math.max(0, activeTaskDepth - 1)
        subagentStack.pop()
      }
      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Tool completed: ${input.tool}`,
          extra: {
            agent: currentAgent,
            success: !(output as any)?.error
          }
        }
      })
    }
  }
}

// ============================================================
// Agent Detection Helpers
// ============================================================

/**
 * Detect agent from session event data.
 * Priority order (highest first):
 *   1. sessionData.agent === "orchestrator" | "plankestrator"  (authoritative — opencode's choice)
 *   2. sessionData.parent_agent / sessionData.primary_agent
 *   3. sessionData.title contains "orchestrator" or "plankestrator" (user-named sessions)
 *   4. sessionData.description contains the agent name (custom field convention)
 * Returns the agent name if found, null otherwise.
 */
function detectAgentFromSessionData(sessionData: any): string | null {
  if (!sessionData) return null

  // Method 1 (PRIMARY, AUTHORITATIVE): explicit agent field from opencode.
  // If opencode has set an explicit agent name, that is the source of truth.
  //
  // CRITICAL: if the explicit agent is set but is NOT orchestrator/plankestrator
  // (e.g. "build", "plan", "explore", "general", or any custom agent), we MUST
  // return null IMMEDIATELY. Falling through to title/description heuristics
  // would risk locking a build agent as orchestrator if its session title
  // contains the substring "orchestrator" or "plankestrator" — which is a
  // common naming convention (e.g. "orchestrator — fix login bug").
  //
  // The rule: an explicit non-primary agent declaration overrides any
  // title/description text heuristic. The plugin's enforcement applies
  // ONLY to orchestrator and plankestrator; it must not silently relabel
  // other agents.
  if (typeof sessionData.agent === "string") {
    if (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator") {
      return sessionData.agent
    }
    return null
  }

  // Methods 2-5 (FALLBACKS): only run when no explicit agent field is set
  // (typeof check above failed). These exist for older opencode versions or
  // unusual payload shapes where the agent name is conveyed via title or
  // description rather than a dedicated field.

  // Method 2: alternate agent-field names used by some opencode versions
  const altAgent = sessionData.parent_agent || sessionData.primary_agent || sessionData.agentName
  if (altAgent === "orchestrator" || altAgent === "plankestrator") {
    return altAgent
  }

  // Method 3: nested in properties (some opencode versions wrap payload)
  const props = (sessionData as any).properties
  if (props) {
    if (props.agent === "orchestrator" || props.agent === "plankestrator") {
      return props.agent
    }
  }

  // Method 4: session title (user-named sessions — only reachable when
  // no explicit agent field is set, see Method 1's early return above)
  if (sessionData.title) {
    const title = String(sessionData.title).toLowerCase()
    if (title.includes("orchestrator")) return "orchestrator"
    if (title.includes("plankestrator")) return "plankestrator"
  }

  // Method 5: session description (same fallback-only constraint as Method 4)
  if (sessionData.description) {
    const desc = String(sessionData.description).toLowerCase()
    if (desc.includes("orchestrator") && !desc.includes("plankestrator")) return "orchestrator"
    if (desc.includes("plankestrator") && !desc.includes("orchestrator")) return "plankestrator"
  }

  return null
}

/**
 * Detect OpenCode's built-in Plan mode (Shift+Tab toggle).
 * Plan mode is a UI-level read-only mode that uses a DEDICATED primary
 * agent named "plan" (NOT "build" and NOT orchestrator/plankestrator).
 * Custom agent routing tables and JSON-output requirements must be
 * bypassed in this mode.
 *
 * The most reliable signal — confirmed from OpenCode LLM logs — is
 * that `sessionData.agent === "plan"` when Plan mode is active, and
 * `sessionData.agent === "build"` otherwise. This check is checked
 * first because it is the source of truth.
 *
 * Other detection methods are kept as fallbacks for other OpenCode
 * versions / payload shapes. Defaults to "build" (enforce) when
 * uncertain — conservative.
 */
function detectPlanMode(sessionData: any): "plan" | "build" {
  if (!sessionData) return "build"

  // v7.1 (P0 event-shape fix): an explicit CUSTOM primary agent (orchestrator /
  // plankestrator) is NEVER built-in Plan mode — built-in Plan uses agent "plan".
  // session.updated.info carries agent + a permission RULE list ({permission,
  // pattern, action}); the permission heuristics below would misread that list as
  // read-only and return "plan", silently bypassing ALL enforcement (the P0 root
  // cause). Guard BEFORE every heuristic.
  if (typeof sessionData.agent === "string" &&
      (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator")) {
    return "build"
  }

  // Method 1 (PRIMARY): agent name itself is the mode indicator.
  // OpenCode switches the primary agent from "build" to "plan" on Shift+Tab.
  // This is verified from real LLM-request logs (agent=plan, mode=primary).
  if (typeof sessionData.agent === "string") {
    const a = sessionData.agent.toLowerCase()
    if (a === "plan" || a === "plan-mode" || a === "planning") return "plan"
    if (a === "build" || a === "build-mode" || a === "normal" || a === "edit") return "build"
  }

  // Method 2: explicit planMode boolean flag
  if (sessionData.planMode === true || sessionData.plan_mode === true) {
    return "plan"
  }

  // Method 3: mode field as string
  if (typeof sessionData.mode === "string") {
    const m = sessionData.mode.toLowerCase()
    if (m === "plan" || m === "planning") return "plan"
    if (m === "build" || m === "normal" || m === "edit") return "build"
  }

  // Method 4: permission field restricted to read-only indicates plan
  const perm = sessionData.permission
  if (perm === "read" || perm === "readonly" || perm === "plan") {
    return "plan"
  }

  // Method 5: nested in properties (some opencode versions wrap it)
  const props = (sessionData as any).properties
  if (props) {
    if (props.planMode === true || props.plan_mode === true) return "plan"
    if (typeof props.mode === "string" && props.mode.toLowerCase() === "plan") {
      return "plan"
    }
    if (typeof props.agent === "string" && props.agent.toLowerCase() === "plan") {
      return "plan"
    }
  }

  // Method 6: nested plan object
  if (sessionData.plan && typeof sessionData.plan === "object") {
    return "plan"
  }

  // Method 7: permissions object without write/edit/bash tools (read-only mode).
  // Newer OpenCode versions represent Plan mode as a permissions map with only
  // read-only tools allowed (no edit, write, bash, or task). If we see such a
  // shape, treat it as plan-mode regardless of agent/mode fields.
  if (perm && typeof perm === "object" && !Array.isArray(perm)) {
    const writeLikeKeys = ["edit", "write", "bash", "task", "patch", "apply"]
    const hasWriteLike = writeLikeKeys.some(k => k in perm)
    if (!hasWriteLike) {
      return "plan"
    }
  }
  if (Array.isArray(perm)) {
    // v7.1 (P0): a permission-rule LIST (opencode 1.18.34 ships
    // [{permission,pattern,action}]) is NOT a read-only tool-name set — it must
    // NOT be interpreted as Plan mode. Without this guard the whole enforcement
    // is bypassed on every orchestrator session.
    if (perm.some((p: any) => p && typeof p === "object" && "permission" in p)) {
      return "build"
    }
    // permission array of allowed tool names
    const writeLike = new Set(["edit", "write", "bash", "task", "patch", "apply"])
    const hasWriteLike = perm.some((p: any) => typeof p === "string" && writeLike.has(p))
    if (!hasWriteLike) {
      return "plan"
    }
  }

  return "build"
}

/**
 * Reverse routing lookup — given a subagent name, find which
 * primary agent is allowed to call it. Used as a fallback when
 * the agent wasn't detected from session events or JSON output.
 */
function detectAgentFromSubagent(subagentName: string): string | null {
  for (const [primaryAgent, whitelist] of Object.entries(ROUTING_TABLES)) {
    if (whitelist.includes(subagentName)) {
      return primaryAgent
    }
  }
  return null
}

// ============================================================
// JSON Parsing & Validation
// ============================================================

/**
 * Extract agent identity from "IDENTITY VERIFIED: I am orchestrator..." text.
 * Returns the agent name if found, null otherwise.
 */
function extractIdentityFromMessage(message: any): string | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null

  // Look for "IDENTITY VERIFIED: I am orchestrator" or "IDENTITY VERIFIED: Я orchestrator"
  // Support both English ("I am") and Russian ("Я")
  const identityMatch = content.match(/IDENTITY VERIFIED:\s*(?:I am|Я)\s+(orchestrator|plankestrator)/i)
  if (identityMatch) {
    return identityMatch[1].toLowerCase()
  }

  return null
}

/**
 * Extract JSON from a message's content. Looks for ```json blocks
 * first, then falls back to inline JSON containing an "agent" field.
 */
function extractJSONFromMessage(message: any): any | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null

  // Try ```json code block
  const jsonMatch = content.match(/```json\s*([\s\S]*?)\s*```/)
  if (jsonMatch) {
    try {
      return JSON.parse(jsonMatch[1])
    } catch {
      return null
    }
  }

  // Try inline JSON with "agent" field
  const inlineMatch = content.match(/\{[\s\S]*?"agent"[\s\S]*?\}/)
  if (inlineMatch) {
    try {
      return JSON.parse(inlineMatch[0])
    } catch {
      return null
    }
  }

  return null
}

// ============================================================
// v7.1 (P0 event-shape fix) — payload normalization + text-buffer helpers.
// opencode 1.18.34 wraps every payload as properties.info; legacy shapes used
// properties.session / properties.message. These helpers keep BOTH.
// ============================================================

/** Resolve the SESSION object from an event payload (new: properties.info). */
function resolveSessionData(event: any): any {
  const props = event?.properties
  return props?.info ?? props?.session ?? props ?? event
}

/** Resolve the MESSAGE object from a message.updated payload (new: properties.info). */
function resolveMessage(event: any): any {
  const props = event?.properties
  return props?.info ?? props?.message ?? event?.message ?? null
}

/** Track a text part's id under its messageID (ordered, LRU-capped). */
function rememberMessagePart(messageID: string, partID: string): void {
  let parts = messageParts.get(messageID)
  if (!parts) {
    parts = []
    messageParts.set(messageID, parts)
  }
  if (!parts.includes(partID)) parts.push(partID)
  while (messageParts.size > TEXT_BUFFER_CAP) {
    const oldest = messageParts.keys().next().value
    if (oldest === undefined || oldest === messageID) break
    const oldParts = messageParts.get(oldest) ?? []
    for (const pid of oldParts) {
      partTexts.delete(pid)
      partDeltas.delete(pid)
      partTypes.delete(pid)
    }
    messageParts.delete(oldest)
  }
}

/** Assemble the full text of a message from its buffered TEXT parts.
 *  Inline content (legacy shape / harness) wins; otherwise the cumulative
 *  part.updated text supersedes the delta accumulation when it is at least as
 *  long (final part.updated carries the complete text). */
function assembleMessageContent(messageID: string, message: any): string {
  const inline = message?.content ?? message?.text
  if (typeof inline === "string" && inline) return inline
  const parts = messageParts.get(messageID)
  if (!parts || parts.length === 0) return ""
  let out = ""
  for (const pid of parts) {
    const full = partTexts.get(pid)
    const delta = partDeltas.get(pid)
    out += (full != null && full.length >= (delta?.length ?? 0)) ? full : (delta ?? full ?? "")
  }
  return out
}

// ============================================================
// v7 (Multi-Phase MVP) — phase helpers (module-level; hoisted —
// used by message.updated, validatePipeline and validateJSONOutput)
// ============================================================

/** v7: current phase object of a MULTI_PHASE JSON, or null. */
function resolveCurrentPhase(json: any): any | null {
  if (String(json?.type) !== "MULTI_PHASE" || !Array.isArray(json?.phases)) return null
  if (json?.current_phase == null) return null
  return json.phases.find((p: any) => p?.id === json?.current_phase) ?? null
}

/** v7: structural validation of phases[] (fail-closed). Returns error string or null. */
function validatePhasesStructure(phases: any, state: string | null): string | null {
  if (!Array.isArray(phases)) return "phases must be an array"
  if (phases.length < MULTI_PHASE_MIN || phases.length > MULTI_PHASE_MAX)
    return `phases.length ${phases.length} out of range [${MULTI_PHASE_MIN}..${MULTI_PHASE_MAX}] (MVP; >3 → ask the user to split the request)`
  const ids = new Set<string>()
  let supercomplexCount = 0
  for (let i = 0; i < phases.length; i++) {
    const p = phases[i]
    if (!p || typeof p.id !== "string" || !p.id) return `phases[${i}].id missing`
    if (ids.has(p.id)) return `duplicate phase id "${p.id}"`
    ids.add(p.id)
    if (!MULTI_PHASE_TYPES.includes(String(p.type))) return `phases[${i}].type invalid: ${p.type}`
    if (p.complexity != null && !["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX"].includes(String(p.complexity)))
      return `phases[${i}].complexity invalid: ${p.complexity}`
    if (p.plan_exists != null && typeof p.plan_exists !== "boolean")
      return `phases[${i}].plan_exists must be boolean|null`
    if (String(p.complexity) === "SUPERCOMPLEX") {
      supercomplexCount++
      // AWAITING time: plan_exists may still be null (in-phase DECOMPOSITION pending)
      if (state !== "AWAITING_CONFIRMATION" && p.plan_exists !== true)
        return `phases[${i}]: SUPERCOMPLEX requires plan_exists=true`
    }
    // MVP linear chain: depends_on = exactly [previous id]; root = phases[0] with []
    const deps = Array.isArray(p.depends_on) ? p.depends_on : null
    if (!deps) return `phases[${i}].depends_on must be an array`
    const expectedDeps = i === 0 ? [] : [phases[i - 1].id]
    if (JSON.stringify(deps) !== JSON.stringify(expectedDeps))
      return `phases[${i}].depends_on must be ${JSON.stringify(expectedDeps)} (MVP: linear chain)`
  }
  if (supercomplexCount > 1) return `at most ONE SUPERCOMPLEX phase allowed (got ${supercomplexCount})`
  return null
}

/** v7: true iff phases arrays are identical EXCEPT null→value refinement of the
 *  current phase's complexity/plan_exists (once; other fields frozen). */
function phasesStableOrRefined(prevPhases: any[], newPhases: any[], currentPhaseId: any): boolean {
  if (!Array.isArray(prevPhases) || prevPhases.length !== newPhases.length) return false
  for (let i = 0; i < prevPhases.length; i++) {
    const a = prevPhases[i] ?? {}, b = newPhases[i] ?? {}
    if (a.id !== b.id || a.type !== b.type || a.goal !== b.goal ||
        JSON.stringify(a.depends_on) !== JSON.stringify(b.depends_on)) return false
    const isCurrent = a.id === currentPhaseId
    const complexOk = a.complexity === b.complexity ||
      (isCurrent && (a.complexity === null || a.complexity === undefined) && b.complexity != null)
    const planOk = a.plan_exists === b.plan_exists ||
      (isCurrent && (a.plan_exists === null || a.plan_exists === undefined) && typeof b.plan_exists === "boolean")
    if (!complexOk || !planOk) return false
  }
  return true
}

// ============================================================
// Pipeline & Identity Validation
// ============================================================

/**
 * Validate pipeline matches PIPELINE TABLE for primary agents.
 */
function validatePipeline(agent: string, type: string | null, complexity: string | null,
  planExists: boolean | null, pipeline: string[], jsonContent?: any): { valid: boolean; error?: string } {
  const PIPELINES: Record<string, Record<string, string[]>> = {
    orchestrator: {
      "BUGFIX-null-null": ["bugfix-triage"],
      "DEVOPS-null-null": ["devops-agent", "devops-reviewer"],
      "DEV-SIMPLE-false": ["worker", "utility"],
      "DEV-SIMPLE-true": ["worker", "consistency-checker", "utility"],
      "DEV-COMPLEX-false": ["dev-planner", "dev-professor", "advisor", "dev-reviewer", "consistency-checker", "utility"],
      "DEV-SUPERCOMPLEX-true": ["dev-planner", "dev-professor", "advisor", "dev-reviewer", "consistency-checker", "utility"],
      "DOCS-SIMPLE-any": ["docs-writer", "utility"],
      "DOCS-DEEP-any": ["docs-planner", "docs-writer", "dev-reviewer", "consistency-checker", "utility"]
    },
    plankestrator: {
      "PLAN-SIMPLE": ["plan-writer-simple", "plan-reviewer-simple"],
      "PLAN-COMPLEX": ["plan-writer-complex", "plan-reviewer-complex"],
      "RESEARCH-SIMPLE": ["research-writer-simple", "research-reviewer"],
      "RESEARCH-COMPLEX": ["research-writer-complex", "research-reviewer"],
      "RESEARCH+PLAN-SIMPLE": ["research-writer-simple", "research-reviewer", "plan-writer-simple", "plan-reviewer-simple"],
      "RESEARCH+PLAN-COMPLEX": ["research-writer-complex", "research-reviewer", "plan-writer-complex", "plan-reviewer-complex"]
    }
  }

  // v6 (Phase 11.1в — applied EARLY, Stage A, correction F-2): legal variants for keys
  // with branching/loops. Without this whitelist the Phase 9.2 escalation would block
  // the BUGFIX continuation: continuation turns re-emit an EXPANDED array under the same
  // key "BUGFIX-null-null" (orchestrator.md BUGFIX continuation / PIPELINE GUIDE row 1).
  const PIPELINE_VARIANTS: Record<string, string[][]> = {
    "orchestrator:BUGFIX-null-null": [
      ["bugfix-triage"],  // Turn 1
      ["bugfix-triage", "worker", "utility"],  // TRIAGE_RESULT: SIMPLE
      ["bugfix-triage", "plan-bug", "execute-bug", "advisor", "dev-reviewer", "consistency-checker", "utility"]  // TRIAGE_RESULT: DEEP
    ],
    // v6 (Phase 11.1б + correction F-7): provisional classification turns (complexity=null)
    "orchestrator:DEV-null-false": [
      ["dev-planner"],        // Q3 DECOMPOSITION Turn A — complexity not determined yet
      ["codebase-analyzer"]   // scope-analysis helper (orchestrator.md TURN ALGORITHM item 2)
    ],
    "orchestrator:DEV-null-true": [
      ["codebase-analyzer"]   // the same helper when the task already references a plan
    ]
  }

  // v6 (Phase 11.1a): OUT OF SCOPE — type=null is legitimate ONLY with an empty pipeline
  // (type=null rule of both primaries; Part I Examples 10/12 orchestrator, 6 plankestrator).
  if (type === null || type === undefined) {
    return pipeline.length === 0
      ? { valid: true }
      : { valid: false, error: "type=null (OUT OF SCOPE) requires empty pipeline and next_agent=null" }
  }

  // Custom pipeline composition — exact concatenation of canonical rows
  // (explicitly requested by the user; lighter than MULTI_PHASE: no
  // confirmation round-trip, no phase envelopes).
  const srcRows = Array.isArray(jsonContent?.pipeline_source_rows) ? jsonContent.pipeline_source_rows : null
  if (srcRows && srcRows.length >= 2) {
    const chains = srcRows.map((k: string) => (PIPELINES[agent] ? PIPELINES[agent][k] : undefined))
    if (chains.some((c: string[] | undefined) => !c)) {
      return { valid: false, error: `pipeline_source_rows references unknown row(s) for ${agent}: ${srcRows.join(", ")}` }
    }
    const composed = chains.flat()
    if (JSON.stringify(pipeline) !== JSON.stringify(composed)) {
      return { valid: false, error: `pipeline does not match the concatenation of pipeline_source_rows [${srcRows.join(" + ")}]: expected [${composed.join(", ")}], got [${pipeline.join(", ")}]` }
    }
    return { valid: true }
  }

  // v7 (Multi-Phase MVP): explicit MULTI_PHASE branch — AWAITING/CANCELLED/terminal
  // shapes are handled HERE, BEFORE the terminal-turn exemption below, so an AWAITING
  // turn is distinguishable from a final turn (research §7.5 row 4 — the shape-based
  // exemption would silently swallow it; risk R8, V-15). Rule 3 is not reached either:
  // top-level complexity=null is LEGAL for MULTI_PHASE (classification lives in
  // phases[] — per-phase keys are checked below instead).
  if (agent === "orchestrator" && type === "MULTI_PHASE") {
    const mpState = jsonContent?.state != null ? String(jsonContent.state) : null
    const phases = jsonContent?.phases
    if (mpState !== null && !MULTI_PHASE_STATES.includes(mpState))
      return { valid: false, error: `Invalid state for MULTI_PHASE: ${mpState}` }
    if (mpState === "AWAITING_CONFIRMATION" || mpState === "CANCELLED") {
      if (pipeline.length !== 0 || (jsonContent?.next_agent !== null && jsonContent?.next_agent !== undefined))
        return { valid: false, error: `state=${mpState} requires pipeline=[] and next_agent=null` }
      if (jsonContent?.current_phase != null)
        return { valid: false, error: `state=${mpState} requires current_phase=null` }
      if (mpState === "AWAITING_CONFIRMATION") {
        const structErr = validatePhasesStructure(phases, mpState)
        if (structErr) return { valid: false, error: structErr }
      }
      return { valid: true }
    }
    // v7: TERMINAL TURN of a multi-phase session (final summary / fail-fast report):
    // state=null, pipeline=[], next_agent=null. Same shape exemption as the terminal
    // block below, replicated HERE because this branch intercepts ALL MULTI_PHASE
    // turns BEFORE it — without this early return the final turn would fall into the
    // per-phase key check and [] would never match the phase chain (false
    // pipelineMismatch on every multi-phase completion; test T15b).
    if (mpState === null && pipeline.length === 0 &&
        (jsonContent?.next_agent === null || jsonContent?.next_agent === undefined)) {
      return { valid: true }
    }
    // Executing turn: phases structure + per-phase key
    const structErr = validatePhasesStructure(phases, mpState)
    if (structErr) return { valid: false, error: structErr }
    const phase = resolveCurrentPhase(jsonContent)
    if (!phase)
      return { valid: false, error: `current_phase "${jsonContent?.current_phase}" not found in phases[].id` }
    // In-phase Auto-DOCS hook (canonical 2-agent chain only — mechanical, safe; MP-4)
    if (JSON.stringify(pipeline) === JSON.stringify(DOCS_HOOK_CHAIN) &&
        ["BUGFIX", "DEV"].includes(String(phase.type)))
      return { valid: true }
    // Per-phase key against the EXISTING table + variants (fail-closed preserved,
    // V-14). No new PIPELINE_VARIANTS entries (deviation D): a provisional DEV phase
    // MUST refine plan_exists null→false on the in-phase DECOMPOSITION dispatch turn
    // (orchestrator.md Q3 parity: Turn A shape plan_exists=false → key DEV-null-false
    // → existing variants [dev-planner]/[codebase-analyzer]); DEV-null-null stays
    // fail-closed and the error message guides the model to re-emit with refinement.
    const pKey = String(phase.type) === "DOCS"
      ? `${phase.type}-${phase.complexity}-any`
      : `${phase.type}-${phase.complexity}-${String(phase.plan_exists ?? null)}`
    const pExpected = PIPELINES.orchestrator?.[pKey]
    const pVariants = PIPELINE_VARIANTS[`orchestrator:${pKey}`]
    if (!pExpected && !pVariants)
      return { valid: false, error: `MULTI_PHASE: unknown phase combination "${pKey}" for phase ${phase.id} (fail-closed)` }
    const pMatches = pVariants
      ? pVariants.some(v => JSON.stringify(pipeline) === JSON.stringify(v))
      : JSON.stringify(pipeline) === JSON.stringify(pExpected)
    if (!pMatches)
      return { valid: false, error: `MULTI_PHASE: pipeline mismatch for phase ${phase.id} (${pKey}). Expected: ${
        pVariants ? pVariants.map(v => `[${v.join(", ")}]`).join(" | ") : `[${pExpected!.join(", ")}]`
      }, got: [${pipeline.join(", ")}]` }
    return { valid: true }
  }

  // v6 (advisor Note 1 fix): TERMINAL TURN exemption — the final turn carries
  // next_agent=null with an EMPTY pipeline while type/complexity retain their
  // classification values (plankestrator.md "Final turn — COMPLETE": state="COMPLETE",
  // next_agent=null, pipeline=[]). Comparing [] against the full expected chain
  // ("RESEARCH-COMPLEX" etc.) is a false positive that sets pipelineMismatch and
  // blocks the primary's NEXT tool call via gate 9.0в.
  if (pipeline.length === 0 &&
      (jsonContent?.next_agent === null || jsonContent?.next_agent === undefined ||
       jsonContent?.state === "COMPLETE")) {
    return { valid: true }
  }

  // v6 (Phase 11.2): cross-field validation (fail-closed)
  // Rule 1: SUPERCOMPLEX requires plan_exists=true (orchestrator.md CRITICAL RULE / Q2)
  if (type === "DEV" && complexity === "SUPERCOMPLEX" && planExists === false) {
    return { valid: false, error: "SUPERCOMPLEX requires plan_exists=true" }
  }
  // Rule 2 (correction F-6): plan_source only with plan_exists=true — scoped to DEV ONLY:
  // a DOCS request referencing a plan file legitimately keeps plan_exists=null and may
  // carry plan_source (orchestrator.md EDGE CASES "DOCS request referencing a plan file").
  if (type === "DEV" && jsonContent?.plan_source && !planExists) {
    return { valid: false, error: "plan_source requires plan_exists=true" }
  }
  // Rule 3 (orchestrator only): complexity=null only for BUGFIX/DEVOPS.
  // Exceptions (correction F-7): provisional classification turns — DECOMPOSITION Turn A
  // (["dev-planner"]) and the codebase-analyzer scope helper (TURN ALGORITHM item 2,
  // "same status as the DECOMPOSITION PROTOCOL exception"; plan_exists may be true when
  // the task already has a plan). OUT OF SCOPE is covered by the early return above.
  // The agent guard is mandatory: BUGFIX/DEVOPS are orchestrator types; plankestrator has
  // its own logic (ambiguous → COMPLEX; complexity=null only in OUT OF SCOPE).
  if (agent === "orchestrator" && complexity === null &&
      !["BUGFIX", "DEVOPS"].includes(String(type)) &&
      !(type === "DEV" && planExists === false &&
        pipeline.length === 1 && pipeline[0] === "dev-planner") &&
      !(type === "DEV" &&
        pipeline.length === 1 && pipeline[0] === "codebase-analyzer")) {
    return { valid: false, error: "complexity=null only for BUGFIX/DEVOPS (exceptions: DECOMPOSITION Turn A, codebase-analyzer scope helper)" }
  }

  // Build key based on agent type
  let key: string
  if (agent === "orchestrator") {
    key = `${type}-${complexity}-${planExists}`
    // Handle "any" for DOCS
    if (type === "DOCS") {
      key = `${type}-${complexity}-any`
    }
  } else if (agent === "plankestrator") {
    key = `${type}-${complexity}`
  } else {
    return { valid: true } // Unknown agent, allow
  }

  const expected = PIPELINES[agent]?.[key]
  const variants = PIPELINE_VARIANTS[`${agent}:${key}`]
  if (!expected && !variants) {
    return {
      valid: false,
      error: `Unknown type/complexity/plan_exists combination for ${agent}: "${key}" (fail-closed — Phase 11)`
    }
  }

  const matches = variants
    ? variants.some(v => JSON.stringify(pipeline) === JSON.stringify(v))
    : JSON.stringify(pipeline) === JSON.stringify(expected)
  if (!matches) {
    return {
      valid: false,
      error: `Pipeline mismatch for ${agent} ${type}/${complexity}/${planExists}. Expected: ${
        variants ? variants.map(v => `[${v.join(", ")}]`).join(" | ") : `[${expected!.join(", ")}]`
      }, got: [${pipeline.join(", ")}]`
    }
  }

  return { valid: true }
}

/**
 * Validate next_agent matches current pipeline step.
 */
function validateNextAgent(nextAgent: string | null, pipeline: string[], currentStep: number): { valid: boolean; error?: string } {
  if (nextAgent === null) {
    return { valid: true } // Pipeline complete
  }

  if (currentStep >= pipeline.length) {
    return { valid: false, error: `Pipeline exhausted but next_agent is ${nextAgent}` }
  }

  const expected = pipeline[currentStep]
  if (nextAgent !== expected) {
    return {
      valid: false,
      error: `next_agent mismatch at step ${currentStep}. Expected: ${expected}, got: ${nextAgent}`
    }
  }

  return { valid: true }
}

/**
 * Validate JSON output against the expected schema for the given agent.
 * Checks for required fields and valid values.
 */
function validateJSONOutput(json: any, agent: string): {valid: boolean, errors: string[], missingFields: string[]} {
  const errors: string[] = []
  const missingFields: string[] = []

  // Check required fields
  const requiredFields = REQUIRED_JSON_FIELDS[agent] || []
  for (const field of requiredFields) {
    if (!(field in json)) {
      missingFields.push(field)
    }
  }

  // v7 (Multi-Phase MVP): MULTI_PHASE conditional requirements (research §7.3-1:
  // state/phases/current_phase are REQUIRED iff type=MULTI_PHASE and ABSENT otherwise —
  // backward compatible; REQUIRED_JSON_FIELDS stays untouched — deviation C).
  if (agent === "orchestrator" && String(json.type) === "MULTI_PHASE") {
    if (!("phases" in json)) missingFields.push("phases")
    if (!("current_phase" in json)) missingFields.push("current_phase")
    if (!Array.isArray(json.phases)) {
      errors.push(`Invalid phases: expected array`)
    } else {
      const structErr = validatePhasesStructure(json.phases, json.state != null ? String(json.state) : null)
      if (structErr) errors.push(structErr)
    }
    const mpState = json.state != null ? String(json.state) : null
    if (mpState === "AWAITING_CONFIRMATION" || mpState === "CANCELLED") {
      if (json.current_phase != null) errors.push(`state=${mpState} requires current_phase=null`)
    } else {
      // executing AND final turns carry current_phase (final = last phase id —
      // orchestrator.md Stage 5; the pipeline=[] terminal shape is exempted in
      // validatePipeline, but current_phase stays required here)
      if (json.current_phase == null) errors.push(`MULTI_PHASE executing turn requires current_phase`)
    }
  }
  // v7: state is MULTI_PHASE-only for orchestrator (single-phase turns never carry it;
  // plankestrator has its own state enum — untouched)
  if (agent === "orchestrator" && json.state != null && String(json.type) !== "MULTI_PHASE") {
    errors.push(`state field is only valid with type=MULTI_PHASE (got type=${json.type})`)
  }

  // Check valid values
  const validValues = VALID_VALUES[agent] || {}
  for (const [field, values] of Object.entries(validValues)) {
    if (json[field] !== undefined && !values.includes(json[field])) {
      errors.push(`Invalid value for ${field}: ${json[field]}, expected: ${values.join("|")}`)
    }
  }

  // Validate next_agent is in routing table or null
  if (json.next_agent !== null && json.next_agent !== undefined) {
    const allowedAgents = ROUTING_TABLES[agent as keyof typeof ROUTING_TABLES] || []
    if (!allowedAgents.includes(json.next_agent)) {
      errors.push(`Invalid next_agent: ${json.next_agent} (not in whitelist)`)
    }
  }

  // Validate pipeline is array or null
  if (json.pipeline !== undefined && json.pipeline !== null && !Array.isArray(json.pipeline)) {
    errors.push(`Invalid pipeline: ${json.pipeline} (expected: array)`)
  }

  // Validate goal is string
  if (json.goal !== undefined && json.goal !== null && typeof json.goal !== "string") {
    errors.push(`Invalid goal: ${json.goal} (expected: string)`)
  }

  // Validate plan_exists is boolean or null (orchestrator only)
  if (agent === "orchestrator" && json.plan_exists !== undefined && json.plan_exists !== null) {
    if (typeof json.plan_exists !== "boolean") {
      errors.push(`Invalid plan_exists: ${json.plan_exists} (expected: boolean|null)`)
    }
  }

  // Validate plan_source is string or null (orchestrator only)
  if (agent === "orchestrator" && json.plan_source !== undefined && json.plan_source !== null) {
    if (typeof json.plan_source !== "string") {
      errors.push(`Invalid plan_source: ${json.plan_source} (expected: string|null)`)
    }
  }

  // Check identity match
  if (json.agent && json.agent !== agent) {
    errors.push(`IDENTITY MISMATCH: JSON claims agent=${json.agent}, but current agent is ${agent}`)
  }

  // Validate requires_docs_update for downstream implementation agents
  // (orchestrator auto-DOCS hook depends on this flag)
  const DOCS_UPDATE_AGENTS = ["execute-bug", "dev-professor", "worker", "docs-writer"]
  if (DOCS_UPDATE_AGENTS.includes(agent)) {
    if (json.requires_docs_update !== undefined && json.requires_docs_update !== null) {
      if (typeof json.requires_docs_update !== "boolean") {
        errors.push(`Invalid requires_docs_update: ${json.requires_docs_update} (expected: boolean|null)`)
      }
    }
    if (json.docs_update_reason !== undefined && json.docs_update_reason !== null) {
      const validReasons = [
        "public_api_changed",
        "plan_modified",
        "docs_modified",
        "code_comments_added",
        null
      ]
      if (!validReasons.includes(json.docs_update_reason)) {
        errors.push(`Invalid docs_update_reason: ${json.docs_update_reason}, expected: ${validReasons.filter(v => v !== null).join("|")}`)
      }
    }
  }

  return {
    valid: errors.length === 0 && missingFields.length === 0,
    errors,
    missingFields
  }
}

// ============================================================
// v5 (OMP P0-1) — Severity helpers
// ============================================================

/** Нормализация текста замечания для дедупликации (OMP emission-guard, п.1:
 *  lowercase, NFKC, схлопывание не-алфанум). */
function normalizeFinding(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/[^a-zа-яё0-9]+/gi, " ").trim()
}

/** Сбор текстов замечаний из JSON reviewer-агента:
 *  findings[] (dev-reviewer), notes[] (advisor) и details[] (consistency-checker). */
function collectFindings(json: any): Array<{ text: string, severity: string | null }> {
  const out: Array<{ text: string, severity: string | null }> = []
  for (const f of Array.isArray(json?.findings) ? json.findings : []) {
    const text = String(f?.description || f?.note || "")
    if (text) out.push({ text, severity: f?.severity != null ? String(f.severity) : null })
  }
  for (const n of Array.isArray(json?.notes) ? json.notes : []) {
    const text = String(n?.note || n?.description || "")
    if (text) out.push({ text, severity: n?.severity != null ? String(n.severity) : null })
  }
  for (const d of Array.isArray(json?.details) ? json.details : []) {
    const text = String(d?.description || "")
    if (text) out.push({ text, severity: d?.severity != null ? String(d.severity) : (json?.severity != null ? String(json.severity) : null) })
  }
  return out
}
