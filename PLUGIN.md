# Workflow Enforcement Plugin

## 1. Overview

The Workflow Enforcement Plugin is a critical component of the OpenCode dual-primary-agent architecture. It enforces routing table compliance, prevents identity drift, and validates JSON output format.

### Purpose

- **Routing Table Enforcement**: Ensures agents can only call other agents within their whitelisted set
- **Identity Drift Detection**: Alerts when an agent's identity changes unexpectedly mid-session
- **JSON Output Validation**: Validates that agent outputs contain required fields with correct values
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
  "plugins": ["./plugins/workflow-enforcement.ts"],
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
| `event` | System events fire | Handles `session.created`, `session.idle`, `message.updated` — agent detection, identity tracking, JSON validation |
| `tool.execute.before` | Before any tool call | Routing table enforcement + reverse routing lookup for agent detection |
| `tool.execute.after` | After tool completes | Logs tool completion |

**Important**: `session.created`, `session.idle`, `message.updated` are NOT top-level hooks — they are **event types** handled inside the `event` hook. The old plugin used them as top-level hooks, which caused them to be silently ignored.

### Hook Details

#### `event` (replaces old `session.created`, `session.updated`, `session.idle`, `message.updated`)

**Trigger**: Any system event fires (session lifecycle, message updates, etc.).

**Purpose**: Agent detection, identity tracking, JSON validation, and workflow logging.

**Behavior**: Checks `event.type` to handle:
1. `session.created` — Detect initial agent identity from session data; reset workflow tracking. **v4:** CHILD sessions (Task subagents, detected via `parentID` in the payload) return early — they do NOT reset the parent's identity-lock/workflow state (parentID guard; logs `CHILD session created (parentID=...) — primary-agent state PRESERVED`)
2. `session.idle` — Log workflow summary when agent finishes
3. `message.updated` — Parse JSON from messages to detect agent (if not yet known) and validate output. **v4:** skipped entirely while a Task subagent runs (`activeTaskDepth > 0` — subagent messages belong to the subagent, e.g. research-writer legitimately writes `## Findings`); additionally detects self-work content markers (`SELF_WORK_MARKERS`) in the locked plankestrator's own assistant messages (role-guard: user messages are never checked) and escalates by setting `selfWorkDetected = true` → the next `read`/`grep`/`glob` throws (see INSPECTION GATE)

**Agent Detection Priority**:
1. Session data (title, agent field) on `session.created`
2. JSON output in messages on `message.updated`
3. Reverse routing lookup in `tool.execute.before` (fallback)

#### `tool.execute.before`

**Trigger**: Before any tool is executed.

**Purpose**: Enforce routing table compliance + fallback agent detection.

**Behavior**:
1. **v4 depth-guard (first)**: If `activeTaskDepth > 0` (a Task subagent is running), the call belongs to the SUBAGENT, not the locked primary agent → skip ALL enforcement. Nested `task` calls still increment the counter and log `TASK CALL WHILE SUBAGENT ACTIVE` (warn). This guard is what keeps Gate A from blocking subagent `edit`/`write`/`bash` calls — without it every pipeline breaks
2. **Reverse routing lookup**: If `currentAgent` is unknown and a `task` call is made, look up which primary agent can call this subagent
3. **v4 JSON-before-Task gate (tightened)**: LOCKED primary agents get NO `isFirstTaskCall` grace — valid JSON is required before any non-auxiliary Task call. Auxiliary targets (`AUXILIARY_TASK_TARGETS` = identity probes + `view-image`) are exempt and legally callable before the classification JSON
4. **v4 INSPECTION GATE (plankestrator only)**: `read`/`grep`/`glob` throw if (a) the pipeline already started (any prior task call to a non-auxiliary target), (b) `selfWorkDetected` is set, or (c) the inspection budget `INSPECTION_BUDGET = 3` is exhausted. Runs BEFORE `workflowSteps.push()` so the current call is not counted against itself
5. Check if tool is `task` (agent delegation)
6. Extract target agent name from tool parameters
7. Look up current agent's whitelist
8. If target not in whitelist → throw error, block execution
9. If target in whitelist → allow execution, increment `activeTaskDepth` (subagent starts), log valid routing

#### `tool.execute.after`

**Trigger**: After any tool completes execution.

**Purpose**: Log workflow step completion.

**Behavior**:
1. **v4**: If the completed tool is `task`, decrement `activeTaskDepth` (clamped at 0) — the subagent finished (success or error), enforcement returns to the parent session
2. Log tool name and result status
3. Track workflow progress
4. Enable debugging of pipeline execution

---

## 4. Routing Tables

### orchestrator Whitelist (24 agents)

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
| docs-planner | Documentation planning (DOCS DEEP) |
| generate-image | Image generation (Gemini) |
| generate-image-gpt | Image generation (GPT/DALL-E) |
| git-commit | Gated conventional git commits |

### plankestrator Whitelist (10 agents)

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
| view-image | Image analysis |

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
    'view-image',
    'docs-planner',
    'generate-image',
    'generate-image-gpt',
    'git-commit'
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
    'devops-readonly',
    'view-image'
  ]
};
```

### Tool Allowance Rules for Primary Agents

Primary agents (`orchestrator`, `plankestrator`) are pure routers. The plugin enforces a **single tool gate** at `tool.execute.before` (lines ~457–507 of `workflow-enforcement.ts`):

| Tool | Allowed for Primary Agents? |
|------|-----------------------------|
| `task` | ✅ Yes (primary purpose — delegate to specialists) |
| `read` | ✅ Yes (inspection convenience for quick lookups) |
| `glob` | ✅ Yes (inspection convenience for quick lookups) |
| `grep` | ✅ Yes (inspection convenience for quick lookups) |
| `todowrite` | ❌ No — primary agents don't manage todos |
| `question` | ❌ No — primary agents don't ask the user |
| `bash`, `edit`, `write`, `patch`, `webfetch` | ❌ No — hard block with error |
| Any MCP action tool (`unity-mcp_*`, `serena_*`, `zai_*` write-side) | ❌ No — hard block with error |

**Why read/glob/grep are allowed:**
- Primary agents need minimal context to make good routing decisions (e.g. peek at `AGENTS.md` or `ARCHITECTURE.md` to inform classification).
- Heavy investigation is still delegated: `mcp-read` for file reading, `mcp-search` for codebase search, `devops-readonly` for read-only ops queries.

**Historical note:** Earlier plugin revisions had a second contradictory gate (the so-called "Gate B") that blocked `read` / `glob` / `grep` despite this gate allowing them. That gate was removed because it caused the model to fall back to producing plan/research content in its own message body when read was blocked. See `plugins/workflow-enforcement.ts` comments around line 567 for the rationale.

---

## 5. Error Messages

### Routing Violation

When an agent attempts to call an agent not in its whitelist:

```
🚫 WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT

Current Agent: orchestrator
Attempted Call: plan-writer-simple
Allowed Agents: orchestrator-identity-probe, dev-reviewer, dev-professor, 
                mcp-github, worker, bugfix, rework, mcp-read, utility, 
                bugfix-triage, plan-bug, devops-agent, devops-reviewer,
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

### Inspection After Pipeline Start (v4)

When the identity-locked plankestrator calls `read`/`grep`/`glob` after the first pipeline Task call:

```
⛔ INSPECTION AFTER PIPELINE START — DELEGATE INSTEAD

You are running as: plankestrator (identity-locked).
The pipeline has already started — ALL inspection (read/grep/glob) is now FORBIDDEN.
This is the "Turns 2..N" rule (same rule orchestrator follows).

Fix: advance the pipeline. Identity line → JSON block → Task call with the NEXT
agent from your routing table:
   - plankestrator-identity-probe
   - plan-writer-simple
   ...

Need file/code context? Delegate to devops-readonly via Task — never read yourself.
```

**Condition**: `identityLocked && lockedAgentName === "plankestrator"`, tool is `read`/`grep`/`glob`, and `workflowSteps` contains a task call whose target is NOT an auxiliary agent (auxiliary = identity probes + `view-image` — they do not count as pipeline start).

**Model fix**: advance the pipeline (identity line → JSON → Task call with the next agent); delegate context needs to `devops-readonly`.

### Inspection Budget Exhausted (v4)

When plankestrator exceeds `INSPECTION_BUDGET = 3` inspection calls (counted across the whole session, Turn 1 included):

```
⛔ INSPECTION BUDGET EXHAUSTED — CLASSIFY AND DELEGATE NOW

You are running as: plankestrator (identity-locked).
You have used all 3 allowed inspection calls (read/grep/glob).
Further inspection is self-work, not classification.

Fix: STOP inspecting. Type and complexity are determined from the REQUEST TEXT
(number of questions / topics / objects to compare), NOT from files.
Identity line → JSON block → Task call with next_agent from your routing table.
```

**Condition**: `inspectionsUsed >= INSPECTION_BUDGET` and the pipeline has not started yet (post-pipeline inspection is caught by the earlier, stricter check above). The prompt tells the model max 2 calls — the plugin's 3 is the hard backstop (prompt stricter than the gate by design).

**Model fix**: classify from the request text and delegate immediately.

### Self-Work Content Detected (v4)

When plankestrator's OWN previous assistant message contained plan/research content markers (`## Findings`, `## Analysis`, `## Research`, `Executive Summary`, `## Recommendations`, `## Overview`, `### Root Cause`, `## Выводы`, `## Результаты исследования`) and the model tries to inspect further:

```
⛔ SELF-WORK CONTENT DETECTED IN YOUR PREVIOUS MESSAGE

You are running as: plankestrator (identity-locked).
Your last message contained plan/research content markers (e.g. "## Findings",
"## Analysis", "Executive Summary"). Producing plan/research CONTENT is self-work —
it belongs to plan-writer-* / research-writer-* agents, NOT to you.

Fix: do NOT continue investigating. Identity line → JSON block → ONE Task call
with next_agent from your routing table → ack line. Your message text must contain
NOTHING else.
```

**Condition**: `selfWorkDetected` was set by the SELF-WORK CONTENT CHECK in `message.updated` (assistant messages only — user messages containing such headings are never flagged), and a subsequent `read`/`grep`/`glob` call arrives. Task calls are NOT blocked — delegation is the desired correction.

**Model fix**: stop investigating, delegate.

---

## 6. JSON Validation

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

### JSON Enforcement Gate (v4 changes)

Two tightenings apply to the JSON-before-Task gate in `tool.execute.before`:

1. **`INVALID JSON OUTPUT` log level: warn → error (v4).** Invalid JSON from a primary agent is now logged as `level: "error"` instead of `warn`. The log alone never blocked anything — the actual enforcement is the throw-gate below.

2. **No `isFirstTaskCall` grace for LOCKED agents (v4).** Previously the first task call of a session bypassed the JSON requirement (race mitigation: `session.created` might not have detected the agent yet). Now:
   - `identityLocked === true` → grace is OFF (`jsonGracePeriod = isFirstTaskCall && !identityLocked`). No race exists for locked sessions: the lock is established before the model's first turn.
   - `identityLocked === false` → grace remains (genuine race mitigation for unlocked sessions).
   - **Exception — auxiliary targets** (`AUXILIARY_TASK_TARGETS` = `IDENTITY_PROBE_AGENTS` + `view-image`): these may legally be called as their own turn BEFORE the classification JSON (plankestrator.md Turn 1 step 3 — view-image for pre-classification image inspection). They never trigger the JSON gate.

Known accepted edge: `message.updated` (JSON validation) can theoretically be processed AFTER `tool.execute.before` of the first pipeline call → one false throw. Self-healing: the model re-sends JSON + Task on the next turn, `hasOutputtedJSON` is then `true`. Expected to be rare; monitor occurrence (see Known Issues).

---

## 7. Agent Detection

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

## 8. Identity Drift Detection

### What Is Identity Drift?

Identity drift occurs when an agent's identity changes unexpectedly during a session. This can happen due to:

- User manually switching agents
- Agent incorrectly identifying itself
- Session state corruption
- Model confusion in output

### Identity Lock Mechanism (v3)

The plugin locks identity at session start. Once locked, drift is a **hard error**, not a soft warning:

```typescript
// On session.created
if (event.type === "session.created") {
  const detected = detectAgentFromSessionData(sessionData)
  if (detected === "orchestrator" || detected === "plankestrator") {
    currentAgent = detected
    identityLocked = true
    lockedAgentName = detected
  }
}

// On message.updated — drift handling differs based on lock state
if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent) {
  if (identityLocked) {
    // HARD ERROR: do NOT update currentAgent; downstream Task calls are still
    // validated against the LOCKED routing table. This is the v3 fix for
    // orchestrator↔plankestrator confusion.
    await client.app.log({ level: "error", message: "IDENTITY DRIFT REJECTED — agent attempted to claim a different identity than session lock" })
  } else {
    // Soft correction (legacy): only when lock is not yet established
    await client.app.log({ level: "warn", message: "IDENTITY DRIFT DETECTED (unlocked — correcting)" })
    currentAgent = String(jsonContent.agent)
  }
}
```

**Note**: The v1 plugin used a `session.updated` hook for drift detection, but `session.updated` is NOT a valid opencode plugin hook. The v2/v3 plugin detects drift from JSON output in messages instead.

### Forbidden Vocabulary Check (v3)

The plugin greps locked-agent message text for terminology that belongs to the OTHER primary agent. This catches the orchestrator↔plankestrator confusion mode where the model produces text from the wrong agent's playbook:

```typescript
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
```

Violations are logged as `error` but do NOT throw (legitimate cross-references like OUT OF SCOPE messages mention forbidden tokens by design).

### Drift Log Examples

#### Hard-rejected drift (identity locked):

```
[2026-04-28T10:30:45.123Z] [ERROR] IDENTITY DRIFT REJECTED — agent attempted to claim a different identity than session lock
  Locked Agent: orchestrator
  Claimed Agent: plankestrator
  Session ID: session-abc123
```

#### Soft correction (unlocked — legacy):

```
[2026-04-28T10:30:45.123Z] [WARN] IDENTITY DRIFT DETECTED (unlocked — correcting)
  Previous Agent: orchestrator
  New Agent: plankestrator
```

#### Forbidden vocabulary violation:

```
[2026-04-28T10:30:45.123Z] [ERROR] FORBIDDEN VOCABULARY DETECTED — orchestrator message contains plankestrator terminology
  Locked Agent: orchestrator
  Other Agent: plankestrator
  Violations: ["## PLAN", "plan-writer-complex"]
```

### Handling Drift

When identity is **locked**, drift is rejected: `currentAgent` is NOT updated, and downstream Task calls are validated against the locked routing table. The agent's message still passes through, but the violation is logged for audit.

When identity is **unlocked** (no `session.created` agent detected yet), drift triggers a soft correction and `currentAgent` is updated.

---

## 9. Debugging

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

## 10. Known Issues

### 1. Agent Detection May Still Fail

**Issue**: If session title doesn't contain "orchestrator" or "plankestrator", session.agent is not set, and the agent doesn't output JSON before making a task call, the reverse routing lookup may fail if the subagent name is ambiguous (exists in both routing tables). Confirmed case (post Variant B): `view-image` now exists in BOTH routing tables; for an UNLOCKED session the reverse lookup returns `orchestrator` (iterated first). Effect is limited to the info log "Reverse routing hint (not enforced)" — NO state mutation (see `detectAgentFromSubagent`).

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

### 6. Parallel Second Task Call Skips Routing Check (v4)

**Issue**: While a Task subagent runs (`activeTaskDepth > 0`), the depth-guard returns early for ALL tool calls — including a second `task` call fired in parallel by the parent in the same turn. Such a call bypasses routing-table validation: the plugin increments the counter and logs a warn (`TASK CALL WHILE SUBAGENT ACTIVE`) but does not block. Nested delegations from subagents (legitimate) take the same path.

**Symptoms**:
- `TASK CALL WHILE SUBAGENT ACTIVE` warn in logs with `depth ≥ 2`
- A parallel Task call proceeds without whitelist validation

**Workaround**: Both primary agents' prompts forbid more than ONE Task call per turn. Full per-turn enforcement requires message-turn boundaries not exposed by current hooks (see `PLANKESTRATOR_FIX_PLAN.md` → «Не реализуем сейчас»).

### 7. activeTaskDepth Could Stick Above Zero (v4, theoretical)

**Issue**: If `tool.execute.after` does not fire for a `task` call under certain error conditions, `activeTaskDepth` never returns to 0 and enforcement stays silently suspended for the rest of the process.

**Symptoms**: No gate logs (`Valid routing`, violations) despite obvious violations; `rg "activeTaskDepth|TASK CALL WHILE SUBAGENT" <latest log>` shows the imbalance.

**Workaround**: `activeTaskDepth = 0` is force-reset on every top-level `session.created` (op 1.10) — starting a new session clears the stick. Optional hardening if this proves real: timestamp-based auto-reset after 30 minutes.

---

## 11. Configuration Reference

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

### v4 State & Constants (self-work prevention)

```typescript
// Максимум read+grep+glob за сессию, ВСЕ — до первого pipeline Task-вызова.
// Промпт требует max 2 — плагин оставляет 1 вызов запаса (промпт строже закона).
const INSPECTION_BUDGET = 3

// Маркеры self-work контента в сообщении locked plankestrator (заголовочные
// токены — снижают false-positive; русские — модель отвечает по-русски).
const SELF_WORK_MARKERS: Record<string, string[]> = {
  plankestrator: [
    "## Findings", "## Research", "Executive Summary", "## Analysis",
    "### Root Cause", "## Recommendations", "## Overview",
    "## Выводы", "## Результаты исследования"
  ]
}

// Маркер self-work-контента в последнем assistant-сообщении родителя:
// выставляется SELF-WORK CONTENT CHECK в message.updated, сбрасывается
// только на session.created верхнего уровня.
let selfWorkDetected: boolean = false

// >0 пока выполняется Task-субагент — enforcement приостановлен
// (атрибуция вызовов субагента родителю запрещена).
// Инкременты: валидный routing, built-in bypass, вложенный task при depth>0.
// Декремент: tool.execute.after для task. Сброс: session.created верхнего уровня.
let activeTaskDepth = 0
```

Reset happens on TOP-LEVEL `session.created` only; child (subagent) sessions with a `parentID` preserve parent state (parentID guard).

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
    'view-image',
    'docs-planner',
    'generate-image',
    'generate-image-gpt',
    'git-commit'
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
    'devops-readonly',
    'view-image'
  ]
};
```

---

## 12. Summary

| Feature | Description |
|---------|-------------|
| **Routing Enforcement** | Blocks Task calls to agents outside whitelist |
| **Identity Detection** | Detects current agent from session title, field, or JSON |
| **Drift Detection** | Alerts when agent identity changes mid-session |
| **JSON Validation** | Validates required fields and values in agent output |
| **Logging** | Comprehensive logging for debugging and auditing |

### Quick Reference

| Check | Log Pattern |
|-------|-------------|
| Plugin initialized | `Workflow enforcement plugin initialized` |
| Valid routing | `Valid routing: X → Y` |
| Routing violation | `WORKFLOW VIOLATION` |
| Identity drift | `IDENTITY DRIFT DETECTED` |
| Invalid JSON | `INVALID JSON OUTPUT` |

### File Locations

| File | Location |
|------|----------|
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Config | `~/.config/opencode/opencode.json` |
| Logs | `~/.local/share/opencode/log/*.log` |
| Agents | `~/.config/opencode/agents/*.md` |