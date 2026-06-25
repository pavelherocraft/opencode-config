# Workflow Enforcement Plugin

## 1. Overview

The Workflow Enforcement Plugin is a critical component of the OpenCode dual-primary-agent architecture. It enforces routing table compliance, prevents identity drift, validates JSON output format, and **enforces pipeline execution order**.

### Purpose

- **Routing Table Enforcement**: Ensures agents can only call other agents within their whitelisted set
- **Identity Drift Detection**: Alerts when an agent's identity changes unexpectedly mid-session
- **JSON Output Validation**: Validates that agent outputs contain required fields with correct values
- **Pipeline Enforcement**: Blocks calls that skip pipeline steps or call agents out of order
- **Workflow Step Logging**: Logs all workflow steps for debugging and auditing

### Why It Exists

The dual-primary-agent architecture (orchestrator + plankestrator) requires strict separation of concerns:

- **orchestrator** handles execution tasks: BUGFIX, DEVOPS, DEV, DOCS
- **plankestrator** handles planning tasks: PLAN, RESEARCH, RESEARCH+PLAN

Without enforcement, agents could:
- Call agents outside their workflow (breaking the pipeline)
- Drift between identities (claiming to be the wrong agent)
- Output invalid JSON (breaking downstream processing)

---

## 2. Plugin Structure

### Location

```
~/.config/opencode/plugins/workflow-enforcement.ts
```

### Export

```typescript
export const WorkflowEnforcement: Plugin
```

### Configuration

The plugin is configured in `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./plugins/workflow-enforcement.ts"],
  "mcp": { ... },
  "agents": { ... }
}
```

### Dependencies

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "^1.0.0"
  }
}
```

---

## 3. Lifecycle Hooks

The plugin implements 3 top-level hooks (plus internal event handling):

| Hook | When | What It Does |
|------|------|--------------|
| `event` | System events fire | Handles `session.created`, `session.idle`, `message.updated` — agent detection, identity tracking, JSON validation, **pipeline activation** |
| `tool.execute.before` | Before any tool call | Routing table enforcement, reverse routing lookup, **pipeline order enforcement** |
| `tool.execute.after` | After tool completes | Logs tool completion, **advances pipeline step** |

**Important**: `session.created`, `session.idle`, `message.updated` are NOT top-level hooks — they are **event types** handled inside the `event` hook. The old plugin used them as top-level hooks, which caused them to be silently ignored.

### Hook Details

#### `event` (replaces old `session.created`, `session.updated`, `session.idle`, `message.updated`)

**Trigger**: Any system event fires (session lifecycle, message updates, etc.).

**Purpose**: Agent detection, identity tracking, JSON validation, and workflow logging.

**Behavior**: Checks `event.type` to handle:
1. `session.created` — Detect initial agent identity from session data; reset workflow tracking **and pipeline state**
2. `session.idle` — Log workflow summary when agent finishes; **warn if pipeline incomplete**
3. `message.updated` — Parse JSON from messages to detect agent (if not yet known), validate output, **and activate pipeline from JSON**

**Agent Detection Priority**:
1. Session data (title, agent field) on `session.created`
2. JSON output in messages on `message.updated`
3. Reverse routing lookup in `tool.execute.before` (fallback)

#### `tool.execute.before`

**Trigger**: Before any tool is executed.

**Purpose**: Enforce routing table compliance + fallback agent detection.

**Behavior**:
1. **Pipeline enforcement**: If a pipeline is active, verify that the target agent matches the expected step
2. **Reverse routing lookup**: If `currentAgent` is unknown and a `task` call is made, look up which primary agent can call this subagent
3. Check if tool is `task` (agent delegation)
4. Extract target agent name from tool parameters
5. Look up current agent's whitelist
6. If target not in whitelist → throw error, block execution
7. If target in whitelist → allow execution, log valid routing

#### `tool.execute.after`

**Trigger**: After any tool completes execution.

**Purpose**: Log workflow step completion.

**Behavior**:
1. Log tool name and result status
2. Track workflow progress
3. Enable debugging of pipeline execution
4. **Advance pipeline step** if the completed task matches the expected pipeline step

---

## 4. Routing Tables

### orchestrator Whitelist (21 agents)

orchestrator can only call these agents:

| Agent Name | Role |
|------------|------|
| orchestrator-identity-probe | Identity verification |
| dev-reviewer | Code review |
| dev-professor | Development guidance |
| mcp-github | GitHub operations |
| worker | Simple development tasks |
| bugfix | Bug fixing |
| rework | Rework on feedback |
| mcp-read | File reading |
| utility | Syntax checking, formatting |
| devops | DevOps tasks |
| bugfix-triage | Initial bug analysis |
| plan-bug | Bug fix planning |
| devops-agent | DevOps operations |
| devops-reviewer | DevOps review |
| dev-planner | Development planning |
| mcp-search | Web search |
| docs-writer | Documentation writing |
| summarizer | Content summarization |
| execute-bug | Bug fix implementation |
| consistency-checker | Architecture consistency validation |
| view-image | Image analysis |

### plankestrator Whitelist (9 agents)

plankestrator can only call these agents:

| Agent Name | Role |
|------------|------|
| plankestrator-identity-probe | Identity verification |
| plan-writer-simple | Simple planning |
| plan-writer-complex | Complex planning |
| plan-reviewer-simple | Simple plan review |
| plan-reviewer-complex | Complex plan review |
| research-writer-simple | Simple research |
| research-writer-complex | Complex research |
| research-reviewer | Research review |
| devops-readonly | DevOps read-only |

### Routing Table Implementation

```typescript
const ROUTING_TABLES = {
  orchestrator: [
    'orchestrator-identity-probe',
    'dev-reviewer',
    'dev-professor',
    'mcp-github',
    'worker',
    'bugfix',
    'rework',
    'mcp-read',
    'utility',
    'devops',
    'bugfix-triage',
    'plan-bug',
    'devops-agent',
    'devops-reviewer',
    'dev-planner',
    'mcp-search',
    'docs-writer',
    'summarizer',
    'execute-bug',
    'consistency-checker',
    'view-image'
  ],
  plankestrator: [
    'plankestrator-identity-probe',
    'plan-writer-simple',
    'plan-writer-complex',
    'plan-reviewer-simple',
    'plan-reviewer-complex',
    'research-writer-simple',
    'research-writer-complex',
    'research-reviewer',
    'devops-readonly'
  ]
};
```

---

## 5. Pipeline Enforcement

### Overview

Pipeline enforcement ensures that agents are called in the correct order as defined in the orchestrator's JSON output. When orchestrator outputs a `pipeline` array (e.g., `["worker", "consistency-checker", "utility"]`), the plugin:

1. **Activates** the pipeline from JSON output
2. **Tracks** which step is expected next
3. **Blocks** calls that skip steps or call out of order
4. **Advances** the step counter after successful completion
5. **Warns** if session ends with incomplete pipeline

### Pipeline Definitions

The plugin defines expected agent sequences for each workflow type:

| Pipeline Key | Sequence |
|---|---|
| `BUGFIX_SIMPLE` | `bugfix-triage → worker → utility` |
| `BUGFIX_DEEP` | `bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility` |
| `DEV_SIMPLE_NO_PLAN` | `worker → utility` |
| `DEV_SIMPLE_WITH_PLAN` | `worker → consistency-checker → utility` |
| `DEV_COMPLEX` | `dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility` |
| `DEVOPS` | `devops-agent → devops-reviewer` |
| `DOCS` | `docs-writer → utility` |
| `PLAN_SIMPLE` | `plan-writer-simple → plan-reviewer-simple` |
| `PLAN_COMPLEX` | `plan-writer-complex → plan-reviewer-complex` |
| `PLAN_BUG` | `plan-bug` |
| `RESEARCH_SIMPLE` | `research-writer-simple → research-reviewer` |
| `RESEARCH_COMPLEX` | `research-writer-complex → research-reviewer` |

**Note**: The actual pipeline is determined by the `pipeline` field in orchestrator's JSON output, not by these definitions. The definitions serve as a reference.

### Pipeline Activation

Pipeline is activated when orchestrator outputs valid JSON with a `pipeline` array:

```json
{
  "agent": "orchestrator",
  "type": "DEV",
  "complexity": "SIMPLE",
  "plan_exists": true,
  "pipeline": ["worker", "consistency-checker", "utility"]
}
```

The plugin logs:
```
[INFO] Pipeline activated from JSON: [worker → consistency-checker → utility]
```

### Enforcement Rules

#### 1. Skipped Steps — BLOCKED

If orchestrator tries to call an agent that appears **later** in the pipeline:

```
⛔ PIPELINE VIOLATION — SKIPPED STEPS

Current Pipeline: [worker → consistency-checker → utility]
Expected Next Step: consistency-checker (step 2/3)
Attempted Call: utility (step 3/3)
Skipped Agents: consistency-checker

You cannot skip pipeline steps. You must call agents in order.
Call consistency-checker first before proceeding to utility.
```

#### 2. Duplicate Call — BLOCKED

If orchestrator tries to call an agent that was **already completed**:

```
⛔ PIPELINE VIOLATION — DUPLICATE CALL

Current Pipeline: [worker → consistency-checker → utility]
Expected Next Step: utility (step 3/3)
Attempted Call: consistency-checker (already completed at step 2)

This agent has already been called. Do not call it again.
```

#### 3. Agent Not in Pipeline — WARNING (allowed)

If orchestrator calls an agent not in the active pipeline (e.g., identity probe):

```
[WARN] Pipeline warning: orchestrator-identity-probe not in active pipeline [worker, consistency-checker, utility], allowing (may be identity probe or ad-hoc call)
```

#### 4. Out of Order — WARNING (allowed)

If orchestrator calls a pipeline agent but not at the expected position:

```
[WARN] Pipeline order warning: expected consistency-checker, got utility
```

### Pipeline Advancement

After a successful task call that matches the expected step, the plugin advances:

```
[INFO] Pipeline advanced: step 2/3 → utility
  completed: consistency-checker
  next: utility
```

When the last step completes:

```
[INFO] Pipeline COMPLETED: [worker → consistency-checker → utility]
```

### Incomplete Pipeline Warning

If the session ends before all pipeline steps are completed:

```
[WARN] PIPELINE INCOMPLETE — session ended with 1 steps remaining
  pipeline: [worker, consistency-checker, utility]
  completed: [worker, consistency-checker]
  remaining: [utility]
```

### Pipeline State Variables

```typescript
let activePipeline: string[] | null = null    // Current pipeline array
let pipelineStepIndex: number = 0             // Index of next expected step
let pipelineName: string | null = null        // Human-readable pipeline key
```

All pipeline state is reset on `session.created`.

---

## 6. Error Messages

### Routing Violation

When an agent attempts to call an agent not in its whitelist:

```
🚫 WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT

Current Agent: orchestrator
Attempted Call: plan-writer-simple
Allowed Agents: orchestrator-identity-probe, dev-reviewer, dev-professor, 
                mcp-github, worker, bugfix, rework, mcp-read, utility, 
                devops, bugfix-triage, plan-bug, devops-agent, devops-reviewer, 
                dev-planner, mcp-search, docs-writer, summarizer, execute-bug,
                consistency-checker, view-image

This violates the routing table configuration.
Please follow the correct workflow for your agent type.

Orchestrator handles: BUGFIX, DEVOPS, DEV, DOCS
Plankestrator handles: PLAN, RESEARCH, RESEARCH+PLAN
```

### Identity Drift Detection

When agent identity changes mid-session:

```
⚠️ IDENTITY DRIFT DETECTED

Previous Agent: orchestrator
New Agent: plankestrator
Session ID: session-abc123

This may indicate:
- User manually switched agents
- Agent incorrectly identified itself
- Session state corruption

Current agent updated to: plankestrator
```

### Invalid JSON Output

When JSON output is missing required fields or has invalid values:

```
❌ INVALID JSON OUTPUT

Agent: orchestrator
Missing Fields: plan_exists, plan_source
Errors:
  - Missing required field: plan_exists
  - Missing required field: plan_source
  - Invalid value for type: PLAN (expected: BUGFIX|DEVOPS|DEV|DOCS|null)

Expected format:
{
  "agent": "orchestrator",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|SUPERCOMPLEX|null",
  "plan_exists": true|false|null,
  "plan_source": "description or null",
  "goal": "one sentence description",
  "next_agent": "agent-name or null",
  "pipeline": ["agent1", "agent2"] or []
}
```

---

## 7. JSON Validation

### Required Fields per Agent

#### orchestrator

```json
{
  "agent": "orchestrator",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|SUPERCOMPLEX|null",
  "plan_exists": true|false|null,
  "plan_source": "description of plan source if exists, null if not",
  "goal": "one sentence description",
  "next_agent": "exact agent name from routing table or null",
  "pipeline": ["agent1", "agent2", "utility"] or []
}
```

#### plankestrator

```json
{
  "agent": "plankestrator",
  "state": "CLASSIFY|EXECUTE|REVIEW|COMPLETE",
  "type": "PLAN|RESEARCH|RESEARCH+PLAN|null",
  "complexity": "SIMPLE|COMPLEX|null",
  "goal": "one sentence description",
  "next_agent": "agent-name or null",
  "pipeline": ["step1", "step2"] or []
}
```

### Valid Values

#### orchestrator

| Field | Valid Values |
|-------|--------------|
| `agent` | `["orchestrator"]` |
| `type` | `["BUGFIX", "DEVOPS", "DEV", "DOCS", null]` |
| `complexity` | `["SIMPLE", "COMPLEX", "DEEP", "SUPERCOMPLEX", null]` |
| `plan_exists` | `[true, false, null]` |
| `plan_source` | `[string, null]` |
| `goal` | `[string]` |
| `next_agent` | `[agent name from whitelist, null]` |
| `pipeline` | `[array of agent names, []]` |

#### plankestrator

| Field | Valid Values |
|-------|--------------|
| `agent` | `["plankestrator"]` |
| `state` | `["CLASSIFY", "EXECUTE", "REVIEW", "COMPLETE"]` |
| `type` | `["PLAN", "RESEARCH", "RESEARCH+PLAN", null]` |
| `complexity` | `["SIMPLE", "COMPLEX", null]` |
| `goal` | `[string]` |
| `next_agent` | `[agent name from whitelist, null]` |
| `pipeline` | `[array of agent names, []]` |

### Validation Logic

```typescript
function validateJSONOutput(json: any, agent: string): ValidationResult {
  const errors: string[] = [];
  const missingFields: string[] = [];

  // Required fields
  const requiredFields = REQUIRED_JSON_FIELDS[agent] || [];
  for (const field of requiredFields) {
    if (!(field in json)) {
      missingFields.push(field);
    }
  }

  // Valid enum values
  const validValues = VALID_VALUES[agent] || {};
  for (const [field, values] of Object.entries(validValues)) {
    if (json[field] !== undefined && !values.includes(json[field])) {
      errors.push(`Invalid value for ${field}: ${json[field]}, expected: ${values.join("|")}`);
    }
  }

  // next_agent must be in whitelist or null
  if (json.next_agent !== null && json.next_agent !== undefined) {
    const allowedAgents = ROUTING_TABLES[agent] || [];
    if (!allowedAgents.includes(json.next_agent)) {
      errors.push(`Invalid next_agent: ${json.next_agent} (not in whitelist)`);
    }
  }

  // pipeline must be array or null
  if (json.pipeline !== undefined && json.pipeline !== null && !Array.isArray(json.pipeline)) {
    errors.push(`Invalid pipeline: ${json.pipeline} (expected: array)`);
  }

  // goal must be string
  if (json.goal !== undefined && json.goal !== null && typeof json.goal !== "string") {
    errors.push(`Invalid goal: ${json.goal} (expected: string)`);
  }

  // plan_exists must be boolean or null (orchestrator only)
  if (agent === "orchestrator" && json.plan_exists !== undefined && json.plan_exists !== null) {
    if (typeof json.plan_exists !== "boolean") {
      errors.push(`Invalid plan_exists: ${json.plan_exists} (expected: boolean|null)`);
    }
  }

  // plan_source must be string or null (orchestrator only)
  if (agent === "orchestrator" && json.plan_source !== undefined && json.plan_source !== null) {
    if (typeof json.plan_source !== "string") {
      errors.push(`Invalid plan_source: ${json.plan_source} (expected: string|null)`);
    }
  }

  // Identity match
  if (json.agent && json.agent !== agent) {
    errors.push(`IDENTITY MISMATCH: JSON claims agent=${json.agent}, but current agent is ${agent}`);
  }

  return { valid: errors.length === 0 && missingFields.length === 0, errors, missingFields };
}
```

---

## 8. Agent Detection

The plugin detects which agent is running using multiple methods, triggered at different points in the lifecycle:

### Detection Methods (Priority Order)

1. **Session Event Data** (on `session.created` event)
   - Checks session title for "orchestrator" or "plankestrator"
   - Checks session.agent field
   - Handled by `detectAgentFromSessionData()`

2. **JSON in Message Output** (on `message.updated` event)
   - Parses assistant messages for `"agent": "..."` field
   - Only runs if agent wasn't detected from session data
   - Handled inside the `event` hook

3. **Reverse Routing Lookup** (in `tool.execute.before` hook)
   - When a `task` call is made, looks up which primary agent can call this subagent
   - Last-resort fallback if neither session data nor JSON detected the agent
   - Handled by `detectAgentFromSubagent()`

### Detection Implementation

```typescript
// Method 1: From session event data (fires on session.created)
function detectAgentFromSessionData(sessionData: any): string | null {
  if (sessionData.title) {
    const title = String(sessionData.title).toLowerCase()
    if (title.includes("orchestrator")) return "orchestrator"
    if (title.includes("plankestrator")) return "plankestrator"
  }
  if (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator") {
    return sessionData.agent
  }
  return null
}

// Method 3: Reverse routing lookup (fires in tool.execute.before)
function detectAgentFromSubagent(subagentName: string): string | null {
  for (const [primaryAgent, whitelist] of Object.entries(ROUTING_TABLES)) {
    if (whitelist.includes(subagentName)) {
      return primaryAgent
    }
  }
  return null
}
```

### Detection Flow

```
Session Created Event
        │
        ▼
┌─────────────────────┐
│ Check Session Data  │
│ (title, agent field)│
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │ Found?    │
    └─────┬─────┘
     Yes  │  No
    ┌─────┴─────┐
    │           ▼
    │   Wait for message.updated event
    │           │
    │           ▼
    │   ┌─────────────────────┐
    │   │ Parse message for   │
    │   │ "agent" JSON field  │
    │   └─────────┬───────────┘
    │             │
    │       ┌─────┴─────┐
    │       │ Found?    │
    │       └─────┬─────┘
    │        Yes  │  No
    │       ┌─────┴─────┐
    │       │           ▼
    │       │   Wait for task tool call
    │       │           │
    │       │           ▼
    │       │   ┌─────────────────────┐
    │       │   │ Reverse Routing     │
    │       │   │ Lookup              │
    │       │   └─────────┬───────────┘
    │       │             │
    │       │       ┌─────┴─────┐
    │       │       │ Found?    │
    │       │       └─────┬─────┘
    │       │        Yes  │  No
    │       │       ┌─────┴─────┐
    │       │       │           ▼
    │       │       │   ┌─────────────┐
    │       │       │   │ Return null │
    │       │       │   └─────────────┘
    ▼       ▼       ▼
┌─────────────────────────┐
│ Update currentAgent     │
│ Log detection result    │
└─────────────────────────┘
```

---

## 9. Identity Drift Detection

### What Is Identity Drift?

Identity drift occurs when an agent's identity changes unexpectedly during a session. This can happen due to:

- User manually switching agents
- Agent incorrectly identifying itself
- Session state corruption
- Model confusion in output

### Detection Mechanism

The plugin tracks `currentAgent` state and can detect drift if a new JSON output declares a different agent:

```typescript
// On message.updated event inside the "event" hook
if (event.type === "message.updated") {
  const jsonContent = extractJSONFromMessage(message)
  if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent) {
    // Identity drift detected!
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
}
```

**Note**: The v1 plugin used a `session.updated` hook for drift detection, but `session.updated` is NOT a valid opencode plugin hook. The v2 plugin detects drift from JSON output in messages instead.

### Drift Log Example

```
[2026-04-28T10:30:45.123Z] ⚠️ IDENTITY DRIFT DETECTED
  Previous Agent: orchestrator
  New Agent: plankestrator
  Session ID: session-abc123
  Timestamp: 2026-04-28T10:30:45.123Z
  Possible cause: User manually switched agents
```

### Handling Drift

The plugin does NOT block execution on drift detection. It:

1. Logs a warning
2. Updates `currentAgent` to new value
3. Continues with new routing table

This allows legitimate agent switches while still tracking them for debugging.

---

## 10. Debugging

### How to Check If Plugin Is Working

#### 1. Check Initialization Log

Look for this log message on session start:

```
[INFO] Workflow enforcement plugin initialized
[INFO] Current agent detected: orchestrator
```

#### 2. Check Valid Routing Logs

When an agent makes a valid call:

```
[DEBUG] Valid routing: orchestrator → worker
[DEBUG] Routing table check passed
```

#### 3. Check Violation Logs

When routing is blocked:

```
[ERROR] 🚫 WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT
[ERROR] Current Agent: orchestrator
[ERROR] Attempted Call: plan-writer-simple
[ERROR] Allowed Agents: [...]
```

#### 4. Check Identity Drift Logs

When identity changes:

```
[WARN] ⚠️ IDENTITY DRIFT DETECTED
[WARN] Previous Agent: orchestrator
[WARN] New Agent: plankestrator
```

#### 5. Check JSON Validation Logs

When JSON is invalid:

```
[ERROR] ❌ INVALID JSON OUTPUT
[ERROR] Agent: orchestrator
[ERROR] Missing Fields: plan_exists, plan_source
```

### Log Location

```
~/.local/share/opencode/log/*.log
```

### Log Format

```
[YYYY-MM-DDTHH:mm:ss.SSSZ] [LEVEL] Message
[LEVEL] = [DEBUG] | [INFO] | [WARN] | [ERROR]
```

### Debugging Commands

```bash
# View recent logs
tail -100 ~/.local/share/opencode/log/opencode.log

# Search for violations
grep "WORKFLOW VIOLATION" ~/.local/share/opencode/log/*.log

# Search for drift
grep "IDENTITY DRIFT" ~/.local/share/opencode/log/*.log

# Search for JSON errors
grep "INVALID JSON" ~/.local/share/opencode/log/*.log

# View all plugin activity
grep "Workflow enforcement" ~/.local/share/opencode/log/*.log
```

### Plugin API Logging

The plugin uses `client.app.log()` for logging:

```typescript
// In plugin code
await client.app.log({
  body: {
    service: "workflow-enforcement",
    level: "info",
    message: "Workflow enforcement plugin initialized"
  }
});
await client.app.log({
  body: {
    service: "workflow-enforcement",
    level: "info",
    message: `Valid routing: ${currentAgent} → ${targetAgent}`
  }
});
await client.app.log({
  body: {
    service: "workflow-enforcement",
    level: "warn",
    message: `WORKFLOW VIOLATION: ${currentAgent} cannot call ${targetAgent}`
  }
});
```

---

## 11. Known Issues

### 1. Agent Detection May Still Fail

**Issue**: If session title doesn't contain "orchestrator" or "plankestrator", session.agent is not set, and the agent doesn't output JSON before making a task call, the reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables).

**Symptoms**:
- `currentAgent` remains `null`
- Routing checks are skipped with a warning
- JSON validation may not run

**Workaround**: The plugin has three detection methods (session data → JSON output → reverse routing) so detection will succeed in most cases.

### 2. OpenCode Permissions May Block Before Plugin Hook

**Issue**: OpenCode's built-in permission system may block a Task call before the `tool.execute.before` hook runs.

**Symptoms**:
- No "WORKFLOW VIOLATION" log
- Call blocked with permission error
- Plugin never sees the call

**Workaround**: Check OpenCode's permission logs separately.

### 3. Plugin Logs via client.app.log()

**Issue**: Plugin logs go to session logs, not a dedicated plugin log file.

**Symptoms**:
- Logs mixed with other session activity
- Harder to filter plugin-specific logs

**Workaround**: Use grep with specific patterns:
```bash
grep -E "(WORKFLOW VIOLATION|IDENTITY DRIFT|INVALID JSON|Workflow enforcement)" ~/.local/share/opencode/log/*.log
```

### 4. JSON Parsing May Fail on Malformed Output

**Issue**: If agent outputs malformed JSON, validation may fail silently.

**Symptoms**:
- No validation error logged
- Missing fields not detected

**Workaround**: Ensure agents output valid JSON format.

### 5. Race Conditions on Rapid Agent Switches

**Issue**: If user rapidly switches agents, drift detection may log multiple warnings.

**Symptoms**:
- Multiple "IDENTITY DRIFT DETECTED" logs
- Confusing audit trail

**Workaround**: This is expected behavior for manual switches; review session timeline.

---

## 12. Configuration Reference

### Full Plugin Configuration

```typescript
// ~/.config/opencode/plugins/workflow-enforcement.ts

import type { Plugin } from "@opencode-ai/plugin"

export const WorkflowEnforcement: Plugin = async ({ client, $ }) => {
  return {
    // Single "event" hook handles all event types
    event: async ({ event }) => {
      if (event.type === "session.created") {
        // Detect initial agent from session data
      }
      if (event.type === "session.idle") {
        // Log workflow summary
      }
      if (event.type === "message.updated") {
        // Validate JSON output + detect agent
      }
    },
    "tool.execute.before": async (input, output) => {
      // Routing table enforcement + reverse routing lookup
    },
    "tool.execute.after": async (input, output) => {
      // Log completion
    }
  }
}
```

### Routing Table Configuration

```typescript
const ROUTING_TABLES = {
  orchestrator: [
    'orchestrator-identity-probe',
    'dev-reviewer',
    'dev-professor',
    'mcp-github',
    'worker',
    'bugfix',
    'rework',
    'mcp-read',
    'utility',
    'devops',
    'bugfix-triage',
    'plan-bug',
    'devops-agent',
    'devops-reviewer',
    'dev-planner',
    'mcp-search',
    'docs-writer',
    'summarizer',
    'execute-bug',
    'consistency-checker',
    'view-image'
  ],
  plankestrator: [
    'plankestrator-identity-probe',
    'plan-writer-simple',
    'plan-writer-complex',
    'plan-reviewer-simple',
    'plan-reviewer-complex',
    'research-writer-simple',
    'research-writer-complex',
    'research-reviewer',
    'devops-readonly'
  ]
};
```

---

## 13. Summary

| Feature | Description |
|---------|-------------|
| **Routing Enforcement** | Blocks Task calls to agents outside whitelist |
| **Identity Detection** | Detects current agent from session title, field, or JSON |
| **Drift Detection** | Alerts when agent identity changes mid-session |
| **JSON Validation** | Validates required fields and values in agent output |
| **Pipeline Enforcement** | Blocks calls that skip steps or call out of order |
| **Logging** | Comprehensive logging for debugging and auditing |

### Quick Reference

| Check | Log Pattern |
|-------|-------------|
| Plugin initialized | `Workflow enforcement plugin initialized` |
| Valid routing | `Valid routing: X → Y` |
| Routing violation | `WORKFLOW VIOLATION` |
| Identity drift | `IDENTITY DRIFT DETECTED` |
| Invalid JSON | `INVALID JSON OUTPUT` |
| Pipeline activated | `Pipeline activated from JSON` |
| Pipeline advanced | `Pipeline advanced: step X/Y` |
| Pipeline completed | `Pipeline COMPLETED` |
| Pipeline incomplete | `PIPELINE INCOMPLETE` |
| Pipeline violation | `PIPELINE VIOLATION` |

### File Locations

| File | Location |
|------|----------|
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Config | `~/.config/opencode/opencode.json` |
| Logs | `~/.local/share/opencode/log/*.log` |
| Agents | `~/.config/opencode/agents/*.md` |