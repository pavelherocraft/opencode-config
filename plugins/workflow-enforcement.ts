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
    "devops",
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
    "explore"
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
    complexity: ["SIMPLE", "COMPLEX", "DEEP", null]
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
let hasOutputtedJSON: Map<string, boolean> = new Map()
let workflowSteps: Array<{timestamp: number, tool: string, agent: string, target?: string}> = []
let currentMode: "plan" | "build" = "build"

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
          hasOutputtedJSON.set(detected, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Session created — agent detected: ${detected}`,
              extra: { sessionId: (event as any).session_id || (event as any).sessionID }
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
        if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent && !identityText) {
          const previousAgent = currentAgent
          currentAgent = String(jsonContent.agent)
          hasOutputtedJSON.set(currentAgent, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "IDENTITY DRIFT DETECTED",
              extra: {
                previousAgent,
                newAgent: currentAgent
              }
            }
          })
        }

        // Validate JSON if we know which agent is running
        if (jsonContent && currentAgent) {
          const validation = validateJSONOutput(jsonContent, currentAgent)

          if (!validation.valid) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
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
      }
    },

    // ==========================================================
    // "tool.execute.before" — routing table enforcement
    // ==========================================================
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

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

      // Check: is this the first task tool call? (race condition mitigation)
      // IMPORTANT: Check BEFORE pushing to workflowSteps — moved here so it's
      // available for both the reverse routing warning and the enforcement check.
      const isFirstTaskCall = input.tool === "task" 
        && workflowSteps.filter(s => s.tool === "task").length === 0

      // FIX: Reverse routing lookup — if we don't know the current
      // agent yet but a task call is being made, look up which
      // primary agent is allowed to call this subagent.
      if (!currentAgent && input.tool === "task") {
        const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type
        if (targetAgent) {
          const detected = detectAgentFromSubagent(targetAgent)
          if (detected) {
            currentAgent = detected
            // FIX: Set to TRUE — agent already outputted JSON at beginning of response
            // before calling Task tool. This allows pipeline calls to proceed without
            // requiring JSON before each Task call in the pipeline.
            hasOutputtedJSON.set(detected, true)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected via reverse routing lookup: ${detected} (called ${targetAgent})`
              }
            })

            // Warn that JSON output will be required for subsequent task calls
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: `JSON output will be REQUIRED for all subsequent Task tool calls by ${detected}. First call is allowed without JSON (grace period).`
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
      
      // Check: agent must output JSON before calling non-identity-probe agents
      const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
      if (!agentJSONStatus && targetAgent && !IDENTITY_PROBE_AGENTS.includes(targetAgent) && !isFirstTaskCall) {
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

      // Check: target agent must be in the current agent's routing table
      const allowedAgents = ROUTING_TABLES[currentAgent as keyof typeof ROUTING_TABLES] || []
      if (targetAgent && !allowedAgents.includes(targetAgent)) {
        // FALLBACK: Check if targetAgent is in the OTHER agent's whitelist
        // (race condition mitigation — message.updated may not have fired yet)
        const otherAgent = currentAgent === "orchestrator" ? "plankestrator" : "orchestrator"
        const otherAllowedAgents = ROUTING_TABLES[otherAgent as keyof typeof ROUTING_TABLES] || []
        
        if (otherAllowedAgents.includes(targetAgent)) {
          // Switch to the correct agent based on routing
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
 * Checks session title and agent field for orchestrator/plankestrator.
 */
function detectAgentFromSessionData(sessionData: any): string | null {
  if (!sessionData) return null

  // Method 1: session title
  if (sessionData.title) {
    const title = String(sessionData.title).toLowerCase()
    if (title.includes("orchestrator")) return "orchestrator"
    if (title.includes("plankestrator")) return "plankestrator"
  }

  // Method 2: session.agent field
  if (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator") {
    return sessionData.agent
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

  return {
    valid: errors.length === 0 && missingFields.length === 0,
    errors,
    missingFields
  }
}
