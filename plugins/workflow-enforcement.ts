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
    type: ["BUGFIX", "DEVOPS", "DEV", "DOCS", null],
    complexity: ["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX", null]
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
const pipelineState = new Map<string, { pipeline: string[]; currentStep: number; provisional: boolean; type: string | null }>()

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
        // v6 (Phase 13.2б): remember the top-level session ID for parallel-Task
        // attribution. childCheckData is in scope (defined above, before the guard).
        // If extraction fails (field names differ), topLevelSessionID stays null and
        // 13.2б degrades to the pre-existing warn (safe fallback).
        topLevelSessionID = String(childCheckData?.id || (event as any).sessionID
          || (event as any).session_id || (event as any).properties?.sessionID || "") || null

        // Try to detect agent from event data
        const sessionData = (event as any).properties?.session
          || (event as any).properties
          || event

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
      // message.updated — validate JSON output + detect agent
      // ----------------------------------------------------------
      if (event.type === "message.updated") {
        // v4: сообщения, созданные ПОКА выполняется Task-субагент, принадлежат
        // субагенту (writer легально пишет "## Findings" и свой JSON) —
        // enforcement атрибутирован родителю, пропускаем.
        if (activeTaskDepth > 0) {
          // v5 (OMP P0-1): сообщения субагентов не проходят primary-валидацию,
          // НО JSON reviewer-агентов проверяется на severity (warn-only: плагин
          // не может блокировать вывод субагента; fail-closed потребление —
          // в промпте orchestrator'а: missing severity = concern).
          const subMessage = (event as any).properties?.message || (event as any).message
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

        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return

        // v6 (Phase 13.3): turn boundary = a NEW primary message. Dedup by messageID:
        // message.updated fires per streaming chunk — the counter resets ONLY when the
        // message changes (an unconditional reset would zero the counter between two Task
        // calls of the SAME message, making the 13.2 gate inert — source-plan correction).
        // Subagent messages never reach here (the depth>0 branch returns earlier).
        const turnMsgId = String((message as any).id || (message as any).info?.id || "")
        if (currentAgent && turnMsgId && lastTurnMessageID.get(currentAgent) !== turnMsgId) {
          lastTurnMessageID.set(currentAgent, turnMsgId)
          taskCallsPerTurn.set(currentAgent, 0)
        }

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
                v6FlagSetThisEvent = true
                violationDetail = `PIPELINE VALIDATION FAILED — ${pipelineValidation.error}`
              }
            }

            // Primary agents: pipeline must be non-empty unless state="COMPLETE"
            if ((currentAgent === "orchestrator" || currentAgent === "plankestrator") &&
                jsonContent.state !== "COMPLETE" &&
                (!pipeline || pipeline.length === 0)) {
              pipelineMismatch = true
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
                const isSupercomplexExempt = !SUPERCOMPLEX_STRICT &&
                  jsonContent.complexity === "SUPERCOMPLEX"
                if (!(isLoopback || isReworkSkip || isDocsHook || isSupercomplexExempt)) {
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
                      whitelisted: isLoopback || isReworkSkip || isDocsHook || isSupercomplexExempt }
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
              if (newPipeline && newPipeline.length > 0 && !nextAgentIsAux) {
                const nextIdx = jsonContent.next_agent
                  ? newPipeline.indexOf(String(jsonContent.next_agent)) : -1
                // F-4: classification turns with complexity=null (DECOMPOSITION Turn A,
                // codebase-analyzer helper, BUGFIX/DEVOPS Turn 1) lock a PROVISIONAL
                // pipeline — the next turn may replace it freely.
                const provisional = jsonContent.complexity === null || jsonContent.complexity === undefined
                const newType = jsonContent.type !== undefined && jsonContent.type !== null
                  ? String(jsonContent.type) : null
                if (!prev) {
                  // Turn 1 — lock the pipeline (Phase 17.1: first valid JSON wins;
                  // the dedup guard above protects against streaming overwrites).
                  pipelineState.set(currentAgent, {
                    pipeline: newPipeline,
                    currentStep: nextIdx >= 0 ? nextIdx : 0,
                    provisional,
                    type: newType
                  })
                } else if (JSON.stringify(newPipeline) !== JSON.stringify(prev.pipeline)) {
                  // Phase 17.2 — pipeline changed after being locked
                  const isException =
                    prev.provisional ||                                     // F-4: provisional classification pipeline
                    jsonContent.type === "BUGFIX" ||                        // BUGFIX continuation (one-time expansion)
                    jsonContent.plan_source === "DECOMPOSITION" ||          // DECOMPOSITION Turn B (Q3)
                    jsonContent.severity === "nit" ||                       // nit-skip re-emission
                    (prev.type !== "DOCS" && newType === "DOCS") ||         // F-12: Auto-DOCS hook
                    (!SUPERCOMPLEX_STRICT && jsonContent.complexity === "SUPERCOMPLEX") // F-11 / R15
                  if (isException) {
                    // v6 (advisor Note 2): pipeline replacement = a new chain/stage
                    // context (SUPERCOMPLEX per-plan-step re-emission, BUGFIX
                    // continuation, DECOMPOSITION Turn B, Auto-DOCS hook) → the
                    // previous rework loop is finished; reset its counters.
                    if ((reworkCount.get(currentAgent) || 0) > 0 || (blockerEscalations.get(currentAgent) || 0) > 0) {
                      await client.app.log({ body: { service: "workflow-enforcement", level: "info",
                        message: `REWORK/BLOCKER COUNTERS RESET — pipeline replaced, new loop context`,
                        extra: { agent: currentAgent } } })
                    }
                    reworkCount.delete(currentAgent)
                    blockerEscalations.delete(currentAgent)
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
                  } else {
                    pipelineImmutable = true
                    v6FlagSetThisEvent = true
                    violationDetail = `PIPELINE IMMUTABLE: pipeline changed after Turn 1 — [${prev.pipeline.join(", ")}] → [${newPipeline.join(", ")}] (exceptions: provisional classification, BUGFIX continuation, DECOMPOSITION, nit-skip, Auto-DOCS hook)`
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
                }
              }
            }

            // v6 (Phase 16): strict ack format audit (WARN-ONLY — never blocks; a
            // measurable format-drift signal before any future escalation). Only for
            // delegation turns (next_agent truthy); OUT OF SCOPE and final turns
            // (next_agent=null) require no ack. Correction F-5 — SIX legal ack variants
            // verified against the CURRENT prompts (post-Part I):
            //   1. "→ DELEGATED to <agent> for: <goal>"                 (both TURN ALGORITHMs)
            //   2. "→ STEP <i>/<N> (<id>): DELEGATED to <agent>"        (orchestrator SUPERCOMPLEX Stage 2)
            //   3. "→ DELEGATED to advisor (step <N>, notes so far: <c>)" (orchestrator ADVISOR STEP RULES)
            //   4. "→ rework SKIPPED (dev-reviewer severity=nit)"       (orchestrator SEVERITY RULES)
            //   5. "→ SUPERCOMPLEX steps (<N>): [...] (source: ...)"    (orchestrator SUPERCOMPLEX Stage 1 echo)
            //   6. "→ DECOMPOSITION requested from dev-planner for: <goal>" (orchestrator Q3)
            // `[\w-]+` (not `\w+`) — agent names contain hyphens (plan-writer-simple).
            // Post-ack prose checking ("no analysis after the ack") is OUT of scope (R16).
            if (jsonContent.next_agent && msgId && !processedMessageIDs.has(msgId + ":ack")) {
              processedMessageIDs.add(msgId + ":ack")
              const ackContent = String(message.content || message.text || "")
              const ackPattern = /^→ (?:(?:STEP \d+\/\d+\s*(?:\([^)]*\))?\s*:\s*)?DELEGATED to [\w-]+(?:\s*\(step [^)]*\)| for: .+)?|DECOMPOSITION requested from [\w-]+ for: .+|rework SKIPPED \(.+\)|SUPERCOMPLEX steps \(\d+\):.*\(source: .+\))\s*$/m
              if (!ackPattern.test(ackContent)) {
                await client.app.log({ body: { service: "workflow-enforcement", level: "warn",
                  message: `ACK FORMAT INVALID — ${currentAgent}: expected one of the 6 legal ack forms (see the Phase 16 comment)`,
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

      // NEW: Block read/grep/glob for primary agents after first Task call
      if ((input.tool === "read" || input.tool === "grep" || input.tool === "glob") &&
          (currentAgent === "orchestrator" || currentAgent === "plankestrator") &&
          primaryAgentFirstTaskCall.get(currentAgent)) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "error",
            message: `PRIMARY AGENT FORBIDDEN TOOL — ${currentAgent} attempted ${input.tool} after first Task call`,
            extra: { agent: currentAgent, tool: input.tool }
          }
        })
        throw new Error(`
⛔ PRIMARY AGENT FORBIDDEN: ${input.tool} blocked after first Task call.
You can only use read/grep/glob for classification in Turn 1. Delegate inspection to the appropriate subagent via Task.
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

      // Check: is this the first task tool call? (race condition mitigation)
      // IMPORTANT: Check BEFORE pushing to workflowSteps — moved here so it's
      // available for both the reverse routing warning and the enforcement check.
      const isFirstTaskCall = input.tool === "task"
        && workflowSteps.filter(s => s.tool === "task").length === 0

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
      //   - isFirstTaskCall grace period above (first task call bypasses JSON)
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

      // Only enforce routing on "task" tool calls (agent delegation)
      if (input.tool !== "task") return

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
        throw new Error(`
⛔ JSON OUTPUT REQUIRED — PLUGIN ENFORCEMENT

You MUST output valid JSON BEFORE calling the Task tool.

Required output order:
1. FIRST: "IDENTITY VERIFIED: I am ${currentAgent}..."
2. SECOND: JSON code block with ALL required fields
3. THIRD: THEN call Task tool

Exception: Identity probe agents may be called before JSON output.

This is enforced by the workflow-enforcement plugin.
        `)
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

  // Look for "IDENTITY VERIFIED: I am orchestrator" or "IDENTITY VERIFIED: I am plankestrator"
  const identityMatch = content.match(/IDENTITY VERIFIED:\s*I am\s+(orchestrator|plankestrator)/i)
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
