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
    "docs-planner"
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
    "devops-readonly"
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
// Plugin State
// ============================================================
let currentAgent: string | null = null
let identityLocked: boolean = false
let lockedAgentName: string | null = null
let hasOutputtedJSON: Map<string, boolean> = new Map()
let workflowSteps: Array<{timestamp: number, tool: string, agent: string, target?: string}> = []
let currentMode: "plan" | "build" = "build"

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
    event: async ({ event }) => {
      if (event.type === "session.created") {
        currentAgent = null
        identityLocked = false
        lockedAgentName = null
        hasOutputtedJSON = new Map()

        const sessionData = (event as any).properties?.session
          || (event as any).properties
          || event

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
              message: `Session created — agent LOCKED: ${detected}`,
              extra: { sessionId: (event as any).session_id || (event as any).sessionID, locked: true }
            }
          })

          if (detected === "orchestrator" || detected === "plankestrator") {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "MANDATORY: You MUST output JSON before any Task tool call."
              }
            })
          }
        } else {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: "Session created — agent not yet detected"
            }
          })
        }

        workflowSteps = []
      }

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

      // session.updated — fires when session metadata (title, agent, mode) changes.
      // Performs identity drift detection against the locked identity.
      if (event.type === "session.updated") {
        const sessionData = (event as any).properties?.session
          || (event as any).properties
          || (event as any).session
          || event

        const detected = detectAgentFromSessionData(sessionData)

        if (detected && identityLocked && lockedAgentName && detected !== lockedAgentName) {
          // Identity drift attempt — session metadata tried to switch primary agent
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "error",
              message: "SESSION IDENTITY DRIFT REJECTED",
              extra: {
                lockedAgent: lockedAgentName,
                claimedAgent: detected,
                sessionId: (event as any).session_id || (event as any).sessionID
              }
            }
          })
          // currentAgent is NOT updated — locked identity is authoritative
        } else if (detected && !identityLocked) {
          // Session metadata confirms or sets identity before lock (defensive)
          if (detected === "orchestrator" || detected === "plankestrator") {
            currentAgent = detected
            identityLocked = true
            lockedAgentName = detected
            hasOutputtedJSON.set(detected, false)
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Session updated — agent LOCKED via metadata: ${detected}`,
                extra: { locked: true }
              }
            })
          }
        }
      }

      if (event.type === "message.updated") {
        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return

        const jsonContent = extractJSONFromMessage(message)
        const identityText = extractIdentityFromMessage(message)

        if (identityText && !currentAgent) {
          if (identityText === "orchestrator" || identityText === "plankestrator") {
            currentAgent = identityText
            hasOutputtedJSON.set(identityText, false)
          }
        }

        if (jsonContent?.agent && !currentAgent) {
          const agentName = String(jsonContent.agent)
          if (agentName === "orchestrator" || agentName === "plankestrator") {
            currentAgent = agentName
            hasOutputtedJSON.set(agentName, false)
          }
        }

        if (identityText && currentAgent && identityText !== currentAgent) {
          const previousAgent = currentAgent
          currentAgent = identityText
          hasOutputtedJSON.set(identityText, false)
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "Agent corrected from IDENTITY VERIFIED text",
              extra: { previousAgent, newAgent: currentAgent }
            }
          })
        }

        if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent && !identityText) {
          if (identityLocked) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: "IDENTITY DRIFT REJECTED",
                extra: {
                  lockedAgent: lockedAgentName,
                  claimedAgent: String(jsonContent.agent)
                }
              }
            })
          } else {
            const previousAgent = currentAgent
            currentAgent = String(jsonContent.agent)
            hasOutputtedJSON.set(currentAgent, false)
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "IDENTITY DRIFT DETECTED (unlocked — correcting)",
                extra: { previousAgent, newAgent: currentAgent }
              }
            })
          }
        }

        if (jsonContent && currentAgent) {
          const validation = validateJSONOutput(jsonContent, currentAgent)
          if (!validation.valid) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "INVALID JSON OUTPUT",
                extra: { agent: currentAgent, errors: validation.errors, missingFields: validation.missingFields }
              }
            })
          } else {
            hasOutputtedJSON.set(currentAgent, true)
          }
        }

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
                extra: { lockedAgent: lockedAgentName, otherAgent, violations }
              }
            })
          }
        }
      }
    },

    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      if (currentMode === "plan") {
        const targetForLog = input.tool === "task"
          ? ((output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type)
          : undefined
        workflowSteps.push({ timestamp, tool: input.tool, agent: "plan-mode-bypass", target: targetForLog })
        return
      }

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
            extra: { lockedAgent: lockedAgentName, attemptedTool: input.tool }
          }
        })
        throw new Error(`PRIMARY AGENT FORBIDDEN ACTION TOOL: ${lockedAgentName} cannot use ${input.tool}`)
      }

      const targetForLog = input.tool === "task"
        ? ((output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type)
        : undefined

      workflowSteps.push({ timestamp, tool: input.tool, agent: currentAgent || "unknown", target: targetForLog })

      if (currentAgent && (currentAgent === "orchestrator" || currentAgent === "plankestrator")) {
        const tool = input.tool
        if (tool !== "task") {
          const ALLOWED_NON_TASK_TOOLS = new Set(["todowrite", "question"])
          if (!ALLOWED_NON_TASK_TOOLS.has(tool)) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "error",
                message: `HARD BLOCK: ${currentAgent} attempted to use "${tool}" directly`,
                extra: { agent: currentAgent, tool, blocked: true }
              }
            })
            throw new Error(`HARD TOOL RESTRICTION: ${currentAgent} MUST delegate via Task tool only`)
          }
        }
      }

      if (input.tool !== "task") return

      const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type

      if (!currentAgent) {
        await client.app.log({
          body: { service: "workflow-enforcement", level: "warn", message: "Current agent not detected" }
        })
        return
      }

      const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
      const isFirstTaskCall = workflowSteps.filter(s => s.tool === "task").length <= 1
      if (!agentJSONStatus && targetAgent && !IDENTITY_PROBE_AGENTS.includes(targetAgent) && !isFirstTaskCall) {
        throw new Error(`JSON OUTPUT REQUIRED — output JSON before calling Task tool`)
      }

      const BUILTIN_OPENCODE_AGENTS = ["explore", "general"]
      if (targetAgent && BUILTIN_OPENCODE_AGENTS.includes(targetAgent)) return

      const allowedAgents = ROUTING_TABLES[currentAgent as keyof typeof ROUTING_TABLES] || []
      if (targetAgent && !allowedAgents.includes(targetAgent)) {
        const otherAgent = currentAgent === "orchestrator" ? "plankestrator" : "orchestrator"
        const otherAllowedAgents = ROUTING_TABLES[otherAgent as keyof typeof ROUTING_TABLES] || []

        if (otherAllowedAgents.includes(targetAgent)) {
          const previousAgent = currentAgent
          currentAgent = otherAgent
          hasOutputtedJSON.set(otherAgent, true)
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: `Agent corrected via routing fallback: was ${previousAgent}, now ${otherAgent}`
            }
          })
        } else {
          throw new Error(`WORKFLOW VIOLATION: ${currentAgent} cannot call ${targetAgent}`)
        }
      }

      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Valid routing: ${currentAgent} → ${targetAgent}`,
          extra: { allowed: true }
        }
      })
    },

    "tool.execute.after": async (input, output) => {
      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Tool completed: ${input.tool}`,
          extra: { agent: currentAgent, success: !(output as any)?.error }
        }
      })
    }
  }
}

// ============================================================
// Helper Functions
// ============================================================

function detectAgentFromSessionData(sessionData: any): string | null {
  if (!sessionData) return null

  if (typeof sessionData.agent === "string") {
    if (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator") {
      return sessionData.agent
    }
    return null
  }

  const altAgent = sessionData.parent_agent || sessionData.primary_agent || sessionData.agentName
  if (altAgent === "orchestrator" || altAgent === "plankestrator") return altAgent

  const props = (sessionData as any).properties
  if (props) {
    if (props.agent === "orchestrator" || props.agent === "plankestrator") return props.agent
  }

  if (sessionData.title) {
    const title = String(sessionData.title).toLowerCase()
    if (title.includes("orchestrator")) return "orchestrator"
    if (title.includes("plankestrator")) return "plankestrator"
  }

  if (sessionData.description) {
    const desc = String(sessionData.description).toLowerCase()
    if (desc.includes("orchestrator") && !desc.includes("plankestrator")) return "orchestrator"
    if (desc.includes("plankestrator") && !desc.includes("orchestrator")) return "plankestrator"
  }

  return null
}

function detectPlanMode(sessionData: any): "plan" | "build" {
  if (!sessionData) return "build"

  if (typeof sessionData.agent === "string") {
    const a = sessionData.agent.toLowerCase()
    if (a === "plan" || a === "plan-mode" || a === "planning") return "plan"
    if (a === "build" || a === "build-mode" || a === "normal" || a === "edit") return "build"
  }

  if (sessionData.planMode === true || sessionData.plan_mode === true) return "plan"

  if (typeof sessionData.mode === "string") {
    const m = sessionData.mode.toLowerCase()
    if (m === "plan" || m === "planning") return "plan"
    if (m === "build" || m === "normal" || m === "edit") return "build"
  }

  const perm = sessionData.permission
  if (perm === "read" || perm === "readonly" || perm === "plan") return "plan"

  return "build"
}

function detectAgentFromSubagent(subagentName: string): string | null {
  for (const [primaryAgent, whitelist] of Object.entries(ROUTING_TABLES)) {
    if (whitelist.includes(subagentName)) return primaryAgent
  }
  return null
}

function extractIdentityFromMessage(message: any): string | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null
  const identityMatch = content.match(/IDENTITY VERIFIED:\s*I am\s+(orchestrator|plankestrator)/i)
  if (identityMatch) return identityMatch[1].toLowerCase()
  return null
}

function extractJSONFromMessage(message: any): any | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null

  const jsonMatch = content.match(/```json\s*([\s\S]*?)\s*```/)
  if (jsonMatch) {
    try { return JSON.parse(jsonMatch[1]) } catch { return null }
  }

  const inlineMatch = content.match(/\{[\s\S]*?"agent"[\s\S]*?\}/)
  if (inlineMatch) {
    try { return JSON.parse(inlineMatch[0]) } catch { return null }
  }

  return null
}

function validateJSONOutput(json: any, agent: string): {valid: boolean, errors: string[], missingFields: string[]} {
  const errors: string[] = []
  const missingFields: string[] = []

  const requiredFields = REQUIRED_JSON_FIELDS[agent] || []
  for (const field of requiredFields) {
    if (!(field in json)) missingFields.push(field)
  }

  const validValues = VALID_VALUES[agent] || {}
  for (const [field, values] of Object.entries(validValues)) {
    if (json[field] !== undefined && !values.includes(json[field])) {
      errors.push(`Invalid value for ${field}: ${json[field]}`)
    }
  }

  if (json.next_agent !== null && json.next_agent !== undefined) {
    const allowedAgents = ROUTING_TABLES[agent as keyof typeof ROUTING_TABLES] || []
    if (!allowedAgents.includes(json.next_agent)) {
      errors.push(`Invalid next_agent: ${json.next_agent} (not in whitelist)`)
    }
  }

  if (json.pipeline !== undefined && json.pipeline !== null && !Array.isArray(json.pipeline)) {
    errors.push(`Invalid pipeline: expected array`)
  }

  if (json.agent && json.agent !== agent) {
    errors.push(`IDENTITY MISMATCH: JSON claims ${json.agent}, but current is ${agent}`)
  }

  return { valid: errors.length === 0 && missingFields.length === 0, errors, missingFields }
}
