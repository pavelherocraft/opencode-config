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
    "generate-image",
    "generate-image-gpt",
    "git-commit"
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
        if (activeTaskDepth > 0) return

        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return

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
            // Hard-error: log and let the message through but flag the violation.
            // We do NOT update currentAgent; we keep the locked identity.
            // Downstream Task calls will be validated against the locked routing table.
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
          } else {
            hasOutputtedJSON.set(currentAgent, true)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: "Valid JSON output detected — Task tool now allowed",
                extra: { agent: currentAgent }
              }
            })
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
            // Note: we DO NOT throw here — we log the error and let downstream
            // checks (identity drift, routing table) catch the actual violation.
            // Throwing on text-level vocabulary would block legitimate cross-references
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
