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

The plugin implements 6 lifecycle hooks:

| Hook | When | What It Does |
|------|------|--------------|
| `tool.execute.before` | Before any tool call | Routing table enforcement — blocks invalid agent calls |
| `tool.execute.after` | After tool completes | Logs tool completion |
| `session.created` | New session starts | Detects which agent is running |
| `session.updated` | Session changes | Detects identity drift |
| `session.idle` | Session ends | Logs workflow summary |
| `message.updated` | Message added | Validates JSON output format |

### Hook Details

#### `tool.execute.before`

**Trigger**: Before any tool is executed.

**Purpose**: Enforce routing table compliance.

**Behavior**:
1. Check if tool is `Task` (agent delegation)
2. Extract target agent name from tool parameters
3. Look up current agent's whitelist
4. If target not in whitelist → throw error, block execution
5. If target in whitelist → allow execution, log valid routing

#### `tool.execute.after`

**Trigger**: After any tool completes execution.

**Purpose**: Log workflow step completion.

**Behavior**:
1. Log tool name and result status
2. Track workflow progress
3. Enable debugging of pipeline execution

#### `session.created`

**Trigger**: When a new session is created.

**Purpose**: Detect initial agent identity.

**Behavior**:
1. Parse session title for "orchestrator" or "plankestrator"
2. Check session.agent field
3. Set `currentAgent` state variable
4. Log detected agent

#### `session.updated`

**Trigger**: When session state changes.

**Purpose**: Detect identity drift.

**Behavior**:
1. Re-detect agent identity
2. Compare with `currentAgent`
3. If different → log "IDENTITY DRIFT DETECTED" warning
4. Update `currentAgent` to new value

#### `session.idle`

**Trigger**: When session becomes idle (ends).

**Purpose**: Log workflow summary.

**Behavior**:
1. Compile statistics: tools called, agents invoked, errors
2. Log summary for debugging
3. Clear session state

#### `message.updated`

**Trigger**: When a message is added/updated in the session.

**Purpose**: Validate JSON output format.

**Behavior**:
1. Extract JSON from message content
2. Validate required fields per agent type
3. Validate field values against allowed values
4. Log errors if validation fails

---

## 4. Routing Tables

### orchestrator Whitelist (20 agents)

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
    'consistency-checker'
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

## 5. Error Messages

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
                consistency-checker

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
  "state": "CLASSIFY_TYPE",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|null",
  "plan_exists": true|false|null,
  "plan_source": "description or null",
  "goal": "one sentence description",
  "next_agent": "agent-name or null",
  "pipeline": ["agent1", "agent2"] or []
}
```

---

## 6. JSON Validation

### Required Fields per Agent

#### orchestrator

```json
{
  "agent": "orchestrator",
  "state": "CLASSIFY_TYPE",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|null",
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
| `state` | `["CLASSIFY_TYPE"]` |
| `type` | `["BUGFIX", "DEVOPS", "DEV", "DOCS", null]` |
| `complexity` | `["SIMPLE", "COMPLEX", "DEEP", null]` |
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
function validateOrchestratorJSON(json: any): ValidationResult {
  const errors: string[] = [];
  
  // Required fields
  const requiredFields = ['agent', 'state', 'type', 'complexity', 
                          'plan_exists', 'plan_source', 'goal', 
                          'next_agent', 'pipeline'];
  
  for (const field of requiredFields) {
    if (!(field in json)) {
      errors.push(`Missing required field: ${field}`);
    }
  }
  
  // Value validation
  if (json.agent !== 'orchestrator') {
    errors.push(`Invalid agent: ${json.agent} (expected: orchestrator)`);
  }
  
  if (!['BUGFIX', 'DEVOPS', 'DEV', 'DOCS', null].includes(json.type)) {
    errors.push(`Invalid type: ${json.type}`);
  }
  
  if (!['SIMPLE', 'COMPLEX', 'DEEP', null].includes(json.complexity)) {
    errors.push(`Invalid complexity: ${json.complexity}`);
  }
  
  // next_agent must be in whitelist or null
  if (json.next_agent !== null && 
      !ROUTING_TABLES.orchestrator.includes(json.next_agent)) {
    errors.push(`Invalid next_agent: ${json.next_agent} (not in whitelist)`);
  }
  
  return { valid: errors.length === 0, errors };
}
```

---

## 7. Agent Detection

The plugin detects which agent is running using multiple methods:

### Detection Methods (Priority Order)

1. **Session Title Match**
   - Checks if session title contains "orchestrator" or "plankestrator"
   - Case-insensitive matching
   - Highest priority

2. **Session.agent Field**
   - Direct field in session object
   - Set by OpenCode when agent is activated

3. **JSON in Messages**
   - Parses recent messages for `"agent": "..."` field
   - Falls back if other methods fail

### Detection Implementation

```typescript
function detectCurrentAgent(session: Session): AgentType | null {
  // Method 1: Session title
  if (session.title?.toLowerCase().includes('orchestrator')) {
    return 'orchestrator';
  }
  if (session.title?.toLowerCase().includes('plankestrator')) {
    return 'plankestrator';
  }
  
  // Method 2: Session.agent field
  if (session.agent === 'orchestrator' || session.agent === 'plankestrator') {
    return session.agent;
  }
  
  // Method 3: JSON in messages
  for (const message of session.messages) {
    const jsonMatch = message.content.match(/\{[\s\S]*"agent"\s*:\s*"(orchestrator|plankestrator)"[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return parsed.agent;
    }
  }
  
  return null; // Could not detect
}
```

### Detection Flow

```
Session Created/Updated
        │
        ▼
┌─────────────────────┐
│ Check Session Title │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │ Found?    │
    └─────┬─────┘
     Yes  │  No
    ┌─────┴─────┐
    │           ▼
    │   ┌───────────────────┐
    │   │ Check session.agent│
    │   └─────────┬─────────┘
    │             │
    │       ┌─────┴─────┐
    │       │ Found?    │
    │       └─────┬─────┘
    │        Yes  │  No
    │       ┌─────┴─────┐
    │       │           ▼
    │       │   ┌─────────────────────┐
    │       │   │ Parse messages for  │
    │       │   │ "agent" JSON field  │
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

### Detection Mechanism

The plugin tracks `currentAgent` state and compares it on every session update:

```typescript
// On session.updated hook
const detectedAgent = detectCurrentAgent(session);

if (detectedAgent && detectedAgent !== currentAgent) {
  // Identity drift detected!
  logWarning('IDENTITY DRIFT DETECTED', {
    previousAgent: currentAgent,
    newAgent: detectedAgent,
    sessionId: session.id
  });
  
  // Update state
  currentAgent = detectedAgent;
}
```

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
client.app.log('info', 'Workflow enforcement plugin initialized');
client.app.log('debug', `Valid routing: ${currentAgent} → ${targetAgent}`);
client.app.log('error', `WORKFLOW VIOLATION: ${currentAgent} cannot call ${targetAgent}`);
```

---

## 10. Known Issues

### 1. Agent Detection May Fail

**Issue**: If session title doesn't contain "orchestrator" or "plankestrator", and session.agent is not set, detection falls back to parsing messages.

**Symptoms**:
- `currentAgent` remains `null`
- Routing checks may be skipped
- JSON validation may not run

**Workaround**: Ensure session titles include the agent name.

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

## 11. Configuration Reference

### Full Plugin Configuration

```typescript
// ~/.config/opencode/plugins/workflow-enforcement.ts

import { Plugin } from '@opencode-ai/plugin';

export const WorkflowEnforcement: Plugin = {
  name: 'workflow-enforcement',
  version: '1.0.0',
  
  hooks: {
    'tool.execute.before': async (context, tool, params) => {
      // Routing table enforcement
    },
    'tool.execute.after': async (context, tool, result) => {
      // Log completion
    },
    'session.created': async (context, session) => {
      // Detect initial agent
    },
    'session.updated': async (context, session) => {
      // Detect identity drift
    },
    'session.idle': async (context, session) => {
      // Log workflow summary
    },
    'message.updated': async (context, message) => {
      // Validate JSON output
    }
  }
};
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
    'consistency-checker'
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