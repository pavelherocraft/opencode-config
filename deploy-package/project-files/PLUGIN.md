# Workflow Enforcement Plugin

## 1. Overview

Enforces routing table compliance, prevents identity drift, validates JSON output format.

### Purpose
- Routing Table Enforcement
- Identity Drift Detection
- JSON Output Validation
- Workflow Step Logging

## 2. Plugin Structure

Location: `~/.config/opencode/plugins/workflow-enforcement.ts`

```typescript
export const WorkflowEnforcement: Plugin
```

## 3. Lifecycle Hooks

| Hook | When | What |
|------|------|------|
| `event` | System events | Handles session.created, session.idle, message.updated |
| `tool.execute.before` | Before tool call | Routing table enforcement |
| `tool.execute.after` | After tool completes | Logs completion |

## 4. Routing Tables

### orchestrator (21 agents)
orchestrator-identity-probe, dev-reviewer, dev-professor, mcp-github, worker, bugfix, rework, mcp-read, utility, bugfix-triage, plan-bug, devops-agent, devops-reviewer, dev-planner, mcp-search, docs-writer, summarizer, execute-bug, consistency-checker, view-image, docs-planner

### plankestrator (9 agents)
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly

## 5. Error Messages

- `WORKFLOW VIOLATION` — routing table breach
- `IDENTITY DRIFT DETECTED` — agent identity changed
- `INVALID JSON OUTPUT` — missing/invalid fields
- `JSON OUTPUT REQUIRED` — Task tool called before JSON output
- `PRIMARY AGENT FORBIDDEN ACTION TOOL` — primary agent tried action tool

## 6. JSON Validation

### orchestrator Required Fields
agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline

### plankestrator Required Fields
agent, state, type, complexity, goal, next_agent, pipeline

## 7. Agent Detection (Priority Order)
1. IDENTITY VERIFIED text (highest)
2. JSON output in messages
3. Reverse routing lookup (fallback)

## 8. Identity Lock (v3)
- Locked at session.start from session.agent field
- Drift = hard error (not soft warning)
- Forbidden vocabulary check between primary agents

## 9. Debugging

Log patterns:
- `Workflow enforcement plugin initialized`
- `Valid routing: X → Y`
- `WORKFLOW VIOLATION`
- `IDENTITY DRIFT`
- `INVALID JSON`

## 10. File Locations

| File | Location |
|------|----------|
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Config | `~/.config/opencode/opencode.json` |
| Logs | `~/.local/share/opencode/log/*.log` |
