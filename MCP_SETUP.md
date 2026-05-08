# MCP Setup — OpenCode Infrastructure Documentation

Complete guide for replicating the entire OpenCode infrastructure on a new machine or for a new project.

## Table of Contents

1. [Overview](#1-overview)
2. [Dual Primary Agents Architecture](#2-dual-primary-agents-architecture)
3. [Routing Tables](#3-routing-tables)
4. [Pipelines](#4-pipelines)
5. [JSON Output Format](#5-json-output-format)
6. [Workflow Enforcement Plugin](#6-workflow-enforcement-plugin)
7. [Identity Verification](#7-identity-verification)
8. [Agent Files](#8-agent-files)
9. [MCP Servers](#9-mcp-servers)
10. [Serena MCP Server](#10-serena-mcp-server)
11. [Unity MCP Server (Official)](#11-unity-mcp-server-official)
12. [Serena Language Configuration](#12-serena-language-configuration)
13. [Step-by-Step Deployment Guide](#13-step-by-step-deployment-guide)
14. [Troubleshooting](#14-troubleshooting)
15. [File Locations Reference](#15-file-locations-reference)
16. [Appendices](#appendices)

---

## 1. Overview

OpenCode uses a **dual-primary-agent architecture** with MCP (Model Context Protocol) server integration for extended capabilities.

### Key Components

| Component | Count | Description |
|-----------|-------|-------------|
| **MCP Servers** | 5 | zread, webSearchPrime, webReader, Serena, Unity |
| **Primary Agents** | 2 | orchestrator, plankestrator |
| **Subagents** | 29 | 20 for orchestrator, 9 for plankestrator |
| **Pipelines** | 8 | BUGFIX (2), DEV (2), DEVOPS, DOCS, PLAN, RESEARCH |
| **Plugin Hooks** | 6 | lifecycle hooks for enforcement |
| **Identity Probes** | 2 | One per primary agent |

### Key Principles

1. **Separation of Concerns**: orchestrator handles operational tasks, plankestrator handles planning and research
2. **Single Source of Truth**: ARCHITECTURE.md contains all architectural requirements
3. **Automatic Validation**: consistency-checker validates files against ARCHITECTURE.md
4. **Strict Routing**: Plugin blocks calls to agents outside whitelist
5. **IDE-Level Coding**: Serena provides semantic code operations via language servers

---

## 2. Dual Primary Agents Architecture

OpenCode uses two primary agents that **DO NOT call each other** — the user must manually switch between them.

### orchestrator

**Handles operational and execution tasks:**

| Task Type | Description |
|-----------|-------------|
| BUGFIX | Bug fixing workflows |
| DEVOPS | DevOps operations |
| DEV | Development tasks |
| DOCS | Documentation writing |

### plankestrator

**Handles planning and research tasks:**

| Task Type | Description |
|-----------|-------------|
| PLAN | Planning workflows |
| RESEARCH | Research workflows |
| RESEARCH+PLAN | Combined research and planning |

### How Agents Work

```
┌─────────────────────────────────────────────────────────────┐
│                     User Request                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │   Which Primary Agent?        │
              │                               │
              │  BUGFIX/DEVOPS/DEV/DOCS       │
              │  → orchestrator               │
              │                               │
              │  PLAN/RESEARCH/RESEARCH+PLAN  │
              │  → plankestrator              │
              └───────────────────────────────┘
                              │
           ┌──────────────────┴──────────────────┐
           │                                     │
           ▼                                     ▼
┌─────────────────────┐               ┌─────────────────────┐
│   orchestrator      │               │   plankestrator     │
│                     │               │                     │
│  20 subagents       │               │  9 subagents        │
│  (whitelist)        │               │  (whitelist)        │
└─────────────────────┘               └─────────────────────┘
           │                                     │
           ▼                                     ▼
    Pipeline Flow                          Pipeline Flow
```

### When to Switch Between Agents

| Current Agent | Switch To | When |
|---------------|-----------|------|
| orchestrator | plankestrator | Need to create a plan before implementing |
| plankestrator | orchestrator | Plan is complete, ready to execute |
| orchestrator | plankestrator | Need research before development |
| plankestrator | orchestrator | Research complete, ready to implement |

**Important**: Agents cannot call each other. The user must explicitly request the switch.

---

## 3. Routing Tables

### orchestrator Whitelist (20 agents)

| # | Agent Name | Role |
|---|------------|------|
| 1 | orchestrator-identity-probe | Identity verification |
| 2 | dev-reviewer | Code review |
| 3 | dev-professor | Development guidance |
| 4 | mcp-github | GitHub operations |
| 5 | worker | Simple development tasks |
| 6 | bugfix | Bug fixing |
| 7 | rework | Rework on feedback |
| 8 | mcp-read | File reading |
| 9 | utility | Syntax checking, formatting |
| 10 | devops | DevOps tasks |
| 11 | bugfix-triage | Initial bug analysis |
| 12 | plan-bug | Bug fix planning |
| 13 | devops-agent | DevOps operations |
| 14 | devops-reviewer | DevOps review |
| 15 | dev-planner | Development planning |
| 16 | mcp-search | Web search |
| 17 | docs-writer | Documentation writing |
| 18 | summarizer | Content summarization |
| 19 | execute-bug | Bug fix implementation |
| 20 | consistency-checker | Architecture consistency validation |

### plankestrator Whitelist (9 agents)

| # | Agent Name | Role |
|---|------------|------|
| 1 | plankestrator-identity-probe | Identity verification |
| 2 | plan-writer-simple | Simple planning |
| 3 | plan-writer-complex | Complex planning |
| 4 | plan-reviewer-simple | Simple plan review |
| 5 | plan-reviewer-complex | Complex plan review |
| 6 | research-writer-simple | Simple research |
| 7 | research-writer-complex | Complex research |
| 8 | research-reviewer | Research review |
| 9 | devops-readonly | DevOps read-only |

### Agent Count Summary

| Primary Agent | Whitelist Count | Total (primary + whitelist) |
|---------------|-----------------|-----------------------------|
| orchestrator | 20 | 21 (orchestrator + 20 subagents) |
| plankestrator | 9 | 10 (plankestrator + 9 subagents) |
| **Grand Total** | **29** | **31** |

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

## 4. Pipelines

### BUGFIX (SIMPLE)

```
bugfix-triage → worker → utility
```

Simple bug fixes use a straightforward pipeline: triage, implementation, validation.

### BUGFIX DEEP

```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
```

Complex bug fixes include planning, execution, review, rework cycles, and consistency validation.

### DEV SIMPLE

```
worker → utility
```

Simple development tasks: implementation → validation.

### DEV COMPLEX

```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
```

Complex development tasks include planning, guidance, review, rework, and consistency validation.

### DEVOPS

```
devops-agent → devops-reviewer
```

DevOps operations: implementation and review.

### DOCS

```
docs-writer → utility
```

Documentation writing followed by validation.

### PLAN

```
plan-writer-* → plan-reviewer-*
```

Planning workflows include writing and review, with specialized agents per complexity level.

### RESEARCH

```
research-writer-* → research-reviewer
```

Research workflows include writing and review.

### Pipeline Summary

| Pipeline | Steps | Uses consistency-checker |
|----------|-------|--------------------------|
| BUGFIX SIMPLE | 3 | ❌ No |
| BUGFIX DEEP | 7 | ✅ Yes |
| DEV SIMPLE | 2 | ❌ No |
| DEV COMPLEX | 6 | ✅ Yes |
| DEVOPS | 2 | ❌ No |
| DOCS | 2 | ❌ No |
| PLAN | 2 | ❌ No |
| RESEARCH | 2 | ❌ No |

---

## 5. JSON Output Format

### orchestrator Required Fields (8 fields)

| Field | Type | Valid Values | Description |
|-------|------|--------------|-------------|
| `agent` | string | `"orchestrator"` | Agent identifier |
| `type` | string \| null | `"BUGFIX"`, `"DEVOPS"`, `"DEV"`, `"DOCS"`, `null` | Task type |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `"DEEP"`, `null` | Task complexity |
| `plan_exists` | boolean \| null | `true`, `false`, `null` | Whether a plan exists |
| `plan_source` | string \| null | description or `null` | Source of the plan |
| `goal` | string | one sentence | Goal description |
| `next_agent` | string \| null | agent name from whitelist or `null` | Next agent to call |
| `pipeline` | string[] | array of agent names or `[]` | Pipeline sequence |

### plankestrator Required Fields (7 fields)

| Field | Type | Valid Values | Description |
|-------|------|--------------|-------------|
| `agent` | string | `"plankestrator"` | Agent identifier |
| `state` | string | `"CLASSIFY"`, `"EXECUTE"`, `"REVIEW"`, `"COMPLETE"` | Current state |
| `type` | string \| null | `"PLAN"`, `"RESEARCH"`, `"RESEARCH+PLAN"`, `null` | Task type |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `null` | Task complexity |
| `goal` | string | one sentence | Goal description |
| `next_agent` | string \| null | agent name from whitelist or `null` | Next agent to call |
| `pipeline` | string[] | array of agent names or `[]` | Pipeline sequence |

### consistency-checker Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"consistency-checker"` |
| `checks_performed` | number | integer |
| `issues_found` | number | integer |
| `issues_fixed` | number | integer |
| `issues_unfixable` | number | integer |
| `details` | array | array of check result objects |
| `files_modified` | array | list of file paths |
| `escalate_to` | string \| null | `"dev-reviewer"` or `null` |

### JSON Output Examples

#### orchestrator Example

``json
{
  "agent": "orchestrator",
  "type": "BUGFIX",
  "complexity": "DEEP",
  "plan_exists": false,
  "plan_source": null,
  "goal": "Fix the authentication timeout issue in the API gateway",
  "next_agent": "bugfix-triage",
  "pipeline": ["bugfix-triage", "plan-bug", "execute-bug", "dev-reviewer", "rework", "consistency-checker", "utility"]
}
```

#### plankestrator Example

``json
{
  "agent": "plankestrator",
  "state": "CLASSIFY",
  "type": "PLAN",
  "complexity": "COMPLEX",
  "goal": "Create a migration plan for the database schema refactoring",
  "next_agent": "plan-writer-complex",
  "pipeline": ["plan-writer-complex", "plan-reviewer-complex"]
}
```

---

## 6. Workflow Enforcement Plugin

### Location

```
~/.config/opencode/plugins/workflow-enforcement.ts
```

### Purpose

| Function | Description |
|----------|-------------|
| **Routing Table Enforcement** | Blocks calls to agents outside whitelist |
| **Identity Drift Detection** | Detects unexpected identity changes mid-session |
| **JSON Output Validation** | Validates required fields and values |
| **Workflow Step Logging** | Logs all workflow steps for debugging |

### Lifecycle Hooks (6 hooks)

| Hook | When | Purpose |
|------|------|---------|
| `tool.execute.before` | Before any tool call | Routing table enforcement, reverse routing lookup |
| `tool.execute.after` | After tool completes | Logs tool completion |
| `session.created` | New session starts | Detects which agent is running |
| `session.updated` | Session changes | Detects identity drift |
| `session.idle` | Session ends | Logs workflow summary |
| `message.updated` | Message added | Validates JSON output format |

### Plugin Structure

```typescript
export const WorkflowEnforcement: Plugin = async ({ client, $ }) => {
  return {
    event: async ({ event }) => {
      // Handles session.created, session.idle, message.updated
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

### Error Messages

#### Routing Violation

```
🚫 WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT

Current Agent: orchestrator
Attempted Call: plan-writer-simple
Allowed Agents: orchestrator-identity-probe, dev-reviewer, ...

This violates the routing table configuration.
Please follow the correct workflow for your agent type.

Orchestrator handles: BUGFIX, DEVOPS, DEV, DOCS
Plankestrator handles: PLAN, RESEARCH, RESEARCH+PLAN
```

#### Identity Drift Detection

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

#### Invalid JSON Output

```
❌ INVALID JSON OUTPUT

Agent: orchestrator
Missing Fields: plan_exists, plan_source
Errors:
  - Missing required field: plan_exists
  - Invalid value for type: PLAN (expected: BUGFIX|DEVOPS|DEV|DOCS|null)
```

### Configuration in opencode.json

``json
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["./plugins/workflow-enforcement.ts"],
  "mcp": { ... },
  "agents": { ... }
}
```

---

## 7. Identity Verification

### Required Output Format

```
✓ IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].
```

### Examples

```
✓ IDENTITY VERIFIED: I am orchestrator. I am NOT plankestrator.
✓ IDENTITY VERIFIED: I am plankestrator. I am NOT orchestrator.
```

### Identity Probe Whitelists

| Primary Agent | Allowed Probe | Denied Probe |
|---------------|---------------|--------------|
| orchestrator | `orchestrator-identity-probe` ✅ | `plankestrator-identity-probe` ❌ |
| plankestrator | `plankestrator-identity-probe` ✅ | `orchestrator-identity-probe` ❌ |

### Probe Procedure

```
Step 0 — IDENTITY PROBE (MANDATORY FIRST STEP):
1. Attempt to call orchestrator-identity-probe
2. If SUCCESS → You are orchestrator → Output identity verification
3. If DENIED → Attempt to call plankestrator-identity-probe
4. If SUCCESS → You are plankestrator → Output identity verification
5. If DENIED → IDENTITY ERROR → STOP
```

### How Identity Probes Work

1. **Probe Agent**: A minimal agent that only returns success when called by the correct primary agent
2. **Routing Table Check**: Plugin checks if the calling agent is in the probe's whitelist
3. **Success/Denied**: If caller is allowed, probe succeeds; otherwise, it's denied
4. **Verification Output**: Primary agent outputs the identity verification message

---

## 8. Agent Files

### Location

```
~/.config/opencode/agents/*.md
```

### Required Agent Files

| Agent | File | Purpose |
|-------|------|---------|
| orchestrator | `orchestrator.md` | Primary agent for operational tasks |
| plankestrator | `plankestrator.md` | Primary agent for planning |
| orchestrator-identity-probe | `orchestrator-identity-probe.md` | Probe for orchestrator |
| plankestrator-identity-probe | `plankestrator-identity-probe.md` | Probe for plankestrator |
| worker | `worker.md` | Simple development tasks |
| utility | `utility.md` | Validation and formatting |
| consistency-checker | `consistency-checker.md` | Architecture validation |
| docs-writer | `docs-writer.md` | Documentation writing |

> **Note:** The table above shows primary and key auxiliary agents. All agents from the routing tables in Section 3 must have corresponding `.md` files.

### Key Agent Permissions

Some agents have specific permission configurations that differ from defaults:

| Agent | Permission | Reason |
|-------|------------|--------|
| orchestrator | `edit: deny`, `write: deny`, `bash: deny` | Primary agent only routes tasks, doesn't execute |
| plankestrator | `edit: deny`, `write: deny`, `bash: deny` | Primary agent only plans, doesn't execute |
| devops-agent | `bash: allow` | Executes commands, creates files |
| devops-reviewer | `bash: allow`, `read: allow`, `edit: deny`, `write: deny` | **Reviewers need bash for git read-only commands** (`git status`, `git log`, `git diff`) |
| worker | `edit: allow`, `write: allow`, `bash: allow` | Implements code changes |
| utility | `bash: allow` | Runs syntax checks, formatting tools |
| devops-readonly | `bash: deny`, `read: allow` | Pure read-only operations |

> **Important:** `devops-reviewer` has `bash: allow` specifically for **read-only git operations** (git status, git log, git diff, git show). This is required to verify commits and pushes without modifying the repository.

### Agent Models Reference

| Agent | Model | Notes |
|-------|-------|-------|
| **orchestrator** | `alibaba-coding-plan/glm-5` | Primary agent for operational tasks |
| **plankestrator** | `alibaba-coding-plan/glm-5` | Primary agent for planning |
| **worker** | `alibaba-coding-plan/qwen3.6-plus` | Simple development tasks |
| **devops-reviewer** | `alibaba-coding-plan/qwen3.6-plus` | DevOps verification |
| **devops-agent** | `minimax-coding-plan/MiniMax-M2.7` | DevOps execution |
| **devops-readonly** | `minimax-coding-plan/MiniMax-M2.7` | Read-only operations |
| **devops** | `minimax-coding-plan/MiniMax-M2.7` | DevOps tasks |
| **utility** | `minimax-coding-plan/MiniMax-M2.7` | Validation tools |
| **bugfix-triage** | `alibaba-coding-plan/qwen3.6-plus` | Bug analysis |
| **plan-bug** | `alibaba-coding-plan/qwen3.6-plus` | Bug fix planning |
| **dev-planner** | `alibaba-coding-plan/qwen3.6-plus` | Development planning |
| **docs-writer** | `alibaba-coding-plan/glm-5` | Documentation |
| **mcp-github** | `minimax-coding-plan/MiniMax-M2.7` | GitHub operations |
| **mcp-read** | `minimax-coding-plan/MiniMax-M2.7` | Web reading |
| **mcp-search** | `minimax-coding-plan/MiniMax-M2.7` | Web search |
| **summarizer** | `minimax-coding-plan/MiniMax-M2.7` | Summarization |
| **dev-reviewer** | `kimi-for-coding/k2p6` | Code review |
| **research-reviewer** | `kimi-for-coding/k2p6` | Research review |
| **plan-reviewer-complex** | `kimi-for-coding/k2p6` | Complex plan review |
| **dev-professor** | `zai-coding-plan/glm-5.1` | Development guidance |
| **execute-bug** | `zai-coding-plan/glm-5.1` | Bug fix execution |
| **rework** | `zai-coding-plan/glm-5.1` | Rework on feedback |
| **plan-writer-complex** | `zai-coding-plan/glm-5.1` | Complex planning |
| **research-writer-complex** | `zai-coding-plan/glm-5.1` | Complex research |

> **Note:** Models must be configured in **both** locations:
> 1. Agent `.md` file frontmatter (`model:` field) — **takes priority**
> 2. `opencode.json` agent config (`model` field) — fallback

### devops-reviewer Rules

**Purpose:** Validate DevOps operations after devops-agent execution.

**Permissions:**
```yaml
permission:
  edit: deny      # Cannot modify files
  write: deny     # Cannot create files  
  read: allow     # Can read files and logs
  bash: allow     # Can run READ-ONLY git commands
```

**Allowed bash commands (read-only):**
| Command | Purpose |
|---------|---------|
| `git status` | Verify clean working tree |
| `git log -N` | Check recent commits |
| `git diff` | Verify staged changes |
| `git show` | Review commit content |
| `git branch` | List branches |
| `git remote -v` | Verify remote config |
| `ls`, `cat` | Verify created files |

**Forbidden bash commands:**
| Command | Reason |
|---------|--------|
| `git commit` | Would modify repository |
| `git push` | Would modify remote |
| `git reset` | Would modify history |
| `git checkout` | Would change branch |
| `git merge` | Would modify history |
| Any write command | Reviewer is read-only |

**Verification checklist:**
1. Check git status — should be clean after commit
2. Check git log — commit should exist with correct message
3. Check git diff — no unexpected staged changes
4. Check remote sync — no unpushed commits (if applicable)
5. Verify created files — expected files should exist
6. Check exit codes — all commands should return 0
7. Review output logs — no errors or warnings

### Serena Usage Rules (MAXIMUM PRIORITY)

**⚠️ MANDATORY: Serena tools are PRIMARY for all code operations**

**Tool Priority Matrix:**

| Task | PRIMARY (Serena) | SECONDARY (Built-in) | Use Built-in ONLY When |
|------|------------------|---------------------|------------------------|
| Find symbol by name | `serena_find_symbol` | `grep` | Serena fails or pattern unknown |
| Find all references | `serena_find_referencing_symbols` | `grep` | Serena fails |
| File structure overview | `serena_get_symbols_overview` | `read` (entire file) | Serena fails |
| Rename across files | `serena_rename_symbol` | `edit` (regex replace) | Serena fails |
| Delete unused code | `serena_safe_delete_symbol` | `edit` | Serena fails |
| Replace function body | `serena_replace_symbol_body` | `edit` | Serena fails |
| Insert after symbol | `serena_insert_after_symbol` | `edit` (line numbers) | Serena fails |

**Permission Configuration:**

``json
{
  "permission": {
    "serena_find_symbol": "allow",
    "serena_find_referencing_symbols": "allow",
    "serena_get_symbols_overview": "allow",
    "serena_rename_symbol": "allow",
    "serena_safe_delete_symbol": "allow",
    "serena_replace_symbol_body": "allow",
    "serena_insert_after_symbol": "allow",
    "grep": "ask",
    "edit": "ask",
    "read": { "*.py": "ask", "*.ts": "ask", "*.js": "ask", "*": "allow" }
  }
}
```

**Behavior:**
- Serena tools → **auto-approved** → agent can use immediately
- Built-in tools (grep, edit, read for code files) → **asks user** → nudges agent to try Serena first

**AGENTS.md Integration:**

Add this section to your project's `AGENTS.md`:

```markdown
## Serena MCP Rules

### ⚠️ MANDATORY: Serena tools are PRIMARY for code operations

**DO NOT use built-in tools (grep, read, glob, edit) for:**
- Finding symbols/classes/functions → USE `serena_find_symbol`
- Finding references/usages → USE `serena_find_referencing_symbols`
- Understanding file structure → USE `serena_get_symbols_overview`
- Renaming across files → USE `serena_rename_symbol`
- Deleting code → USE `serena_safe_delete_symbol`
- Editing function/class body → USE `serena_replace_symbol_body`
- Inserting code → USE `serena_insert_after_symbol`

**Built-in tools are SECONDARY - use ONLY when:**
- Serena tool fails or is unavailable
- Searching for unknown text patterns (not symbol names)
- Reading specific file content at known locations
- Simple single-line edits where symbol boundaries are unclear
```

### orchestrator.md Content Summary

```markdown
# orchestrator

You are the orchestrator agent — the primary agent for operational and execution tasks.

## Identity Verification (MANDATORY FIRST STEP)

Before any other action, you MUST verify your identity:
1. Attempt to call orchestrator-identity-probe
2. If SUCCESS → You are orchestrator → Output identity verification
3. If DENIED → Attempt to call plankestrator-identity-probe
4. If SUCCESS → You are plankestrator → Output identity verification
5. If DENIED → IDENTITY ERROR → STOP

Required output format:
✓ IDENTITY VERIFIED: I am orchestrator. I am NOT plankestrator.

## Task Types You Handle

| Type | Description |
|------|-------------|
| BUGFIX | Bug fixing workflows |
| DEVOPS | DevOps operations |
| DEV | Development tasks |
| DOCS | Documentation writing |

## Routing Table (20 agents)

You can ONLY call these agents:
- orchestrator-identity-probe
- dev-reviewer
- ... (full list)

## JSON Output Format (MANDATORY)

Required fields: agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline

## Pipelines

BUGFIX SIMPLE: bugfix-triage → worker → utility
BUGFIX DEEP: bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
...
```

### plankestrator.md Content Summary

```markdown
# plankestrator

You are the plankestrator agent — the primary agent for planning and research tasks.

## Identity Verification (MANDATORY FIRST STEP)

Before any other action, you MUST verify your identity:
1. Attempt to call plankestrator-identity-probe
2. If SUCCESS → You are plankestrator → Output identity verification
3. If DENIED → Attempt to call orchestrator-identity-probe
4. If SUCCESS → You are orchestrator → Output identity verification
5. If DENIED → IDENTITY ERROR → STOP

Required output format:
✓ IDENTITY VERIFIED: I am plankestrator. I am NOT orchestrator.

## Task Types You Handle

| Type | Description |
|------|-------------|
| PLAN | Planning workflows |
| RESEARCH | Research workflows |
| RESEARCH+PLAN | Combined research and planning |

## Routing Table (9 agents)

You can ONLY call these agents:
- plankestrator-identity-probe
- plan-writer-simple
- ... (full list)

## JSON Output Format (MANDATORY)

Required fields: agent, state, type, complexity, goal, next_agent, pipeline

## Pipelines

PLAN: plan-writer-* → plan-reviewer-*
RESEARCH: research-writer-* → research-reviewer
```

### How to Create Custom Agents

1. Create a new `.md` file in `~/.config/opencode/agents/`
2. Define the agent's role and capabilities
3. Add the agent to the appropriate routing table in:
   - `workflow-enforcement.ts`
   - `ARCHITECTURE.md`
4. Add the agent to `opencode.json` under `agents`
5. Run `consistency-checker` to validate

---

## 9. MCP Servers

### Server Configuration

| Server | Tool Prefix | Purpose |
|--------|-------------|---------|
| **zread** | `zread_` | GitHub repository reading |
| **webSearchPrime** | `webSearchPrime_` | Web search |
| **webReader** | `webReader_` | URL content reading |
| **Serena** | `serena_` | IDE-level coding operations |

### zread (GitHub)

| Tool | Description |
|------|-------------|
| `zread_search_doc` | Search documentation, issues, PRs, and code in a repository |
| `zread_get_repo_structure` | Get directory structure and file list |
| `zread_read_file` | Read complete file content from repository |

### webSearchPrime (Web Search)

| Tool | Description |
|------|-------------|
| `webSearchPrime_web_search_prime` | Search the web for information |

### webReader (URL Reading)

| Tool | Description |
|------|-------------|
| `webReader_webReader` | Fetch and convert URL content to LLM-friendly format |

### Usage Rules

```
⚠️ IMPORTANT: Do NOT use webfetch!

- For web search → webSearchPrime
- For reading URLs → webReader
- For GitHub repositories → zread
- For symbol operations → Serena
```

### Usage Examples

```typescript
// Web search
webSearchPrime_web_search_prime({
  search_query: "OpenCode MCP integration",
  location: "en"
})
`
// Read URL
webReader_webReader({
  url: "https://docs.example.com/api",
  return_format: "markdown"
})
`
// GitHub repository
zread_search_doc({
  repo_name: "vitejs/vite",
  query: "configuration options"
})
`
zread_get_repo_structure({
  repo_name: "vitejs/vite",
  dir_path: "packages"
})
`
zread_read_file({
  repo_name: "vitejs/vite",
  file_path: "package.json"
})
```

---

## 10. Serena MCP Server

### What is Serena?

**Serena is the IDE for your coding agent.** It provides essential semantic code retrieval, editing, refactoring, and debugging tools that operate at the symbol level — just like an IDE.

Key capabilities:
- **Symbol-level operations**: Find symbols, get references, rename across files
- **Semantic editing**: Replace symbol bodies, insert before/after symbols, safe delete
- **Multi-language support**: 40+ programming languages via language servers
- **Agent-first design**: High-level abstractions, no line numbers or primitive search patterns

### Why Serena?

Without Serena, agents must use:
- `grep` for finding symbols (slow, imprecise)
- `read` entire files to understand structure (token-heavy)
- `edit` with search/replace for refactoring (error-prone)

With Serena, agents can:
- Find symbols by name in one call
- Get file structure without reading entire file
- Rename symbols across all files atomically
- Replace function/class bodies precisely

### Installation

```bash
# Install uv (package manager) if not already installed
# See: https://docs.astral.sh/uv/getting-started/installation/

# Install Serena
uv tool install -p 3.13 serena-agent@latest --prerelease=allow

# Initialize Serena (language server backend)
serena init

# Or initialize with JetBrains backend
serena init -b JetBrains
```

### Configuration in opencode.json

``json
{
  "mcp": {
    "servers": {
      "serena": {
        "type": "stdio",
        "command": "serena",
        "args": ["mcp-server", "--transport", "stdio"]
      }
    }
  }
}
```

### Serena Tools

| Tool | Description | When to Use |
|------|-------------|-------------|
| `serena_find_symbol` | Find symbol by name | Instead of grep for symbol search |
| `serena_find_referencing_symbols` | Find all references to a symbol | Instead of grep for references |
| `serena_get_symbols_overview` | Get file structure/outline | Instead of reading entire file |
| `serena_rename_symbol` | Rename symbol across codebase | Instead of edit with search/replace |
| `serena_safe_delete_symbol` | Delete unused symbol safely | Instead of manual edit |
| `serena_replace_symbol_body` | Replace function/class body | Instead of edit with line numbers |
| `serena_insert_after_symbol` | Insert code after symbol | Instead of edit with line numbers |

### Serena vs Built-in Tools

| Operation | Serena Tool | Built-in Tool |
|-----------|-------------|---------------|
| Find symbol by name | `serena_find_symbol` ✅ | `grep` ❌ |
| Find all references | `serena_find_referencing_symbols` ✅ | `grep` ❌ |
| Understand file structure | `serena_get_symbols_overview` ✅ | `read` (entire file) ❌ |
| Rename across files | `serena_rename_symbol` ✅ | `edit` with search/replace ❌ |
| Delete unused code | `serena_safe_delete_symbol` ✅ | `edit` ❌ |
| Replace function/class body | `serena_replace_symbol_body` ✅ | `edit` ❌ |
| Insert code near symbol | `serena_insert_after_symbol` ✅ | `edit` with line numbers ❌ |
| Unknown text pattern search | — | `grep` ✅ |
| Read specific file content | — | `read` ✅ |
| Find files by name | — | `glob` ✅ |
| Simple single-file edits | — | `edit` ✅ |
| Run commands/tests | — | `bash` ✅ |

### Integration with AGENTS.md Rules

Add this section to your project's `AGENTS.md`:

```markdown
### Serena MCP Rules

#### Symbol Operations → USE SERENA (ALWAYS)
| Operation | Serena Tool | Do NOT Use |
|-----------|-------------|------------|
| Find symbol by name | `serena_find_symbol` | grep |
| Find all references | `serena_find_referencing_symbols` | grep |
| Understand file structure | `serena_get_symbols_overview` | read (entire file) |
| Rename across files | `serena_rename_symbol` | edit with search/replace |
| Delete unused code | `serena_safe_delete_symbol` | edit |
| Replace function/class body | `serena_replace_symbol_body` | edit |
| Insert code near symbol | `serena_insert_after_symbol` | edit with line numbers |

#### Simple Operations → USE BUILT-IN TOOLS
| Operation | Built-in Tool |
|-----------|---------------|
| Unknown text pattern search | grep |
| Read specific file content | read |
| Find files by name | glob |
| Simple single-file edits | edit |
| Run commands/tests | bash |
```

---

## 11. Unity MCP Server (Official)

Unity MCP provides integration with Unity Editor for game development automation.

### Installation

1. **Requirements:**
   - Unity 6 (6000.0) or later
   - Unity Editor must be running

2. **Install Unity Package:**
   - Open Unity Editor
   - Go to `Window > Package Manager`
   - Click `+` → `Add package by name`
   - Enter: `com.unity.ai.assistant`
   - Click `Add`

3. **Auto-install Relay Binary:**
   - Start Unity Editor with the AI Assistant package
   - Relay binary will be installed automatically to:
     - Windows: `%USERPROFILE%\.unity\relay\relay_win.exe`
     - macOS: `~/.unity/relay/relay_macos`
     - Linux: `~/.unity/relay/relay_linux`

4. **First-time Connection:**
   - Open Unity Editor
   - Go to `Edit > Project Settings > AI > Unity MCP`
   - Click `Accept` to approve the connection

### Configuration

Add to `opencode.json`:

```json
"mcp": {
  "unity": {
    "type": "stdio",
    "command": ["C:\\Users\\Admin\\.unity\\relay\\relay_win.exe"],
    "args": ["--mcp"]
  }
}
```

For macOS/Linux, adjust the path accordingly.

### Available Tools

| Tool | Description |
|------|-------------|
| `Unity.ManageGameObject` | Create, find, modify, delete GameObjects |
| `Unity.ManageScene` | Load, save, create scenes, query hierarchy |
| `Unity.ManageAsset` | Asset management operations |
| `Unity.CreateScript` | Create C# scripts |
| `Unity.DeleteScript` | Delete C# scripts |
| `Unity.ManageScript` | CRUD operations on C# scripts |
| `Unity.ScriptApplyEdits` | Advanced script editing |
| `Unity.ApplyTextEdits` | Apply text edits to C# scripts |
| `Unity.ValidateScript` | Validate C# scripts |
| `Unity.ManageShader` | CRUD operations on shader files |
| `Unity.ReadConsole` | Read/clear Unity Editor console logs |
| `Unity.RunCommand` | Compile and execute C# scripts |
| `Unity.ImportExternalModel` | Import external models/assets |
| `Unity.ManageMenuItem` | Execute/list/refresh menu items |
| `Unity.ManageEditor` | Control/query Editor state, Tags, Layers |
| `Unity.GetSHA` | Get SHA256 for C# scripts |
| `Unity.ManageScriptCapabilities` | Manage script capabilities |
| `Unity.ResourceTools` | List and read project files |

### Usage Rules

See `AGENTS.md` → "Unity MCP Rules" section for mandatory usage guidelines.

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Relay binary not found | Start Unity Editor with AI Assistant package installed |
| Connection refused | Check Unity Editor is running, approve connection in Project Settings |
| Tool not available | Verify `com.unity.ai.assistant` package is installed |
| Permission denied | Run Unity Editor as administrator (Windows) or with sudo (Linux) |

---

## 12. Serena Language Configuration

### Project Configuration File

Location: `.serena/project.yml` in project root

### Supported Languages (Major)

| Language | Serena Key | Notes |
|----------|------------|-------|
| Python | `python` | No additional setup |
| TypeScript | `typescript` | Also supports JavaScript |
| JavaScript | `typescript` | Use TypeScript key |
| Java | `java` | No additional setup |
| C# | `csharp` | Requires .NET v10+ |
| C/C++ | `cpp` | Uses clangd; provide `compile_commands.json` |
| Go | `go` | Requires `gopls` |
| Rust | `rust` | Requires rustup |
| Ruby | `ruby` | Uses ruby-lsp |
| PHP | `php` | Uses Intelephense |
| Kotlin | `kotlin` | Uses official Kotlin LSP (pre-alpha) |
| Swift | `swift` | No additional setup |
| Scala | `scala` | Requires manual setup (Metals LSP) |
| Lua | `lua` | No additional setup |
| Dart | `dart` | No additional setup |
| Elixir | `elixir` | Requires Elixir installation |
| Haskell | `haskell` | Auto-locates HLS via ghcup |
| Julia | `julia` | No additional setup |
| F# | `fsharp` | Requires .NET v8.0+ |
| PowerShell | `powershell` | No additional setup |
| Bash | `bash` | No additional setup |
| Perl | `perl` | Requires Perl::LanguageServer |
| R | `r` | Requires `languageserver` R package |
| Zig | `zig` | Requires ZLS |
| Nix | `nix` | Requires nixd |
| Clojure | `clojure` | No additional setup |
| Erlang | `erlang` | Requires beam and erlang_ls |
| Elm | `elm` | Requires Elm compiler |
| Fortran | `fortran` | Requires fortls (`pip install fortls`) |
| Groovy | `groovy` | Requires groovy-language-server.jar |
| Haxe | `haxe` | Requires Haxe compiler 3.4.0+ |
| Vue | `vue` | 3.x with TypeScript; requires Node.js v18+ |
| Crystal | `crystal` | Requires Crystalline on PATH |
| Pascal | `pascal` | Uses Pascal/Lazarus (auto-downloaded) |
| OCaml | `ocaml` | Requires opam and ocaml-lsp-server |
| Lean 4 | `lean4` | Requires elan |
| Solidity | `solidity` | Experimental; requires Node.js |
| Ansible | `ansible` | Experimental; requires Node.js |
| Terraform | `terraform` | No additional setup |

### Experimental Languages

| Language | Serena Key | Notes |
|----------|------------|-------|
| JSON | json` | Must explicitly enable; requires Node.js |
| YAML | `yaml` | No additional setup |
| TOML | `toml` | No additional setup |
| Markdown | `markdown` | Must explicitly enable; for documentation-heavy projects |
| MATLAB | `matlab` | No additional setup |

### Example Configuration

```yaml
# .serena/project.yml

# Project name
project_name: "MyProject"

# Languages to enable
# First language is the default/fallback
languages:
  - python
  - typescript
  - json
  - yaml

# File encoding
encoding: "utf-8"

# Line ending convention (unset, lf, crlf, native)
line_ending:

# Language backend (LSP or JetBrains)
language_backend:

# Use .gitignore to ignore files
ignore_all_files_in_gitignore: true

# Additional paths to ignore
ignored_paths: []

# Read-only mode
read_only: false

# Tools to exclude
excluded_tools: []

# Initial prompt
initial_prompt: ""
```

### Language-Specific Notes

#### C/C++

```yaml
languages:
  - cpp

# For best results, provide compile_commands.json at repository root
# See: https://oraios.github.io/serena/03-special-guides/cpp_setup
```

#### C#

```yaml
languages:
  - csharp  # Uses Roslyn (requires .NET v10+)
  # or
  - csharp_omnisharp  # Uses OmniSharp
```

#### PHP

```yaml
languages:
  - php  # Uses Intelephense
  # Set INTELEPHENSE_LICENSE_KEY for premium features
  # or
  - php_phpactor  # Uses Phpactor (requires PHP 8.1+)
```

#### Ruby

```yaml
languages:
  - ruby  # Uses ruby-lsp
  # or
  - ruby_solargraph  # Uses Solargraph
```

### Adding Languages to Existing Project

1. Edit `.serena/project.yml`
2. Add language to the `languages` list
3. Restart Serena MCP server
4. Verify language server started

---

## 13. Step-by-Step Deployment Guide

### Prerequisites

| Requirement | Version | Installation |
|-------------|---------|--------------|
| Python | 3.13+ | System package manager |
| Node.js | 18+ | System package manager |
| uv | Latest | `curl -LsSf https://astral.sh/uv/install.sh | sh` |
| OpenCode | Latest | Follow OpenCode installation guide |

### Step 1: Install OpenCode

```bash
# Follow OpenCode installation instructions
# Ensure ~/.config/opencode/ directory exists
```

### Step 2: Create Directory Structure

```bash
# Linux/macOS
mkdir -p ~/.config/opencode/plugins
mkdir -p ~/.config/opencode/agents

# Windows (PowerShell)
mkdir -Force "$env:USERPROFILE\.config\opencode\plugins"
mkdir -Force "$env:USERPROFILE\.config\opencode\agents"
```

### Step 3: Copy Plugin File

```bash
# Linux/macOS
cp workflow-enforcement.ts ~/.config/opencode/plugins/

# Windows (PowerShell)
Copy-Item "workflow-enforcement.ts" "$env:USERPROFILE\.config\opencode\plugins\"
```

### Step 4: Copy Agent Files

```bash
# Linux/macOS
cp agents/*.md ~/.config/opencode/agents/

# Windows (PowerShell)
Copy-Item "agents\*.md" "$env:USERPROFILE\.config\opencode\agents\"
```

### Step 5: Configure opencode.json

Create or edit `~/.config/opencode/opencode.json`:

``json
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["./plugins/workflow-enforcement.ts"],
  "mcp": {
    "servers": {
      "zread": {
        "type": "remote",
        "url": "https://mcp.zread.dev"
      },
      "webSearchPrime": {
        "type": "remote",
        "url": "https://mcp.websearchprime.dev"
      },
      "webReader": {
        "type": "remote",
        "url": "https://mcp.webreader.dev"
      },
      "serena": {
        "type": "stdio",
        "command": "serena",
        "args": ["mcp-server", "--transport", "stdio"]
      }
    }
  },
  "agents": {
    "orchestrator": "./agents/orchestrator.md",
    "plankestrator": "./agents/plankestrator.md",
    "orchestrator-identity-probe": "./agents/orchestrator-identity-probe.md",
    "plankestrator-identity-probe": "./agents/plankestrator-identity-probe.md",
    "worker": "./agents/worker.md",
    "utility": "./agents/utility.md",
    "consistency-checker": "./agents/consistency-checker.md",
    "docs-writer": "./agents/docs-writer.md"
  }
}
```

> **Note:** Add all remaining agents from the routing tables in Section 3 to the `agents` object.

### Step 6: Install and Configure Serena

```bash
# Install Serena
uv tool install -p 3.13 serena-agent@latest --prerelease=allow

# Initialize Serena
serena init

# Verify installation
serena --version
```

### Step 7: Create AGENTS.md in Project

Create `AGENTS.md` in project root with:

```markdown
# Project Rules

## MCP Tools Rules

### Search
Always use webSearchPrime for web search. Do NOT use webfetch.

### Read URLs
Always use webReader for reading URL content. Do NOT use webfetch.

### GitHub Repositories
Always use zread tools for GitHub repositories.

### Serena MCP Rules
Use Serena for symbol operations. See detailed table in documentation.

## Architecture Requirements
All architecture requirements are defined in ARCHITECTURE.md.

## Dual Primary Agents Architecture
- orchestrator: BUGFIX, DEVOPS, DEV, DOCS
- plankestrator: PLAN, RESEARCH, RESEARCH+PLAN

## Routing Tables
See ARCHITECTURE.md for complete whitelists.

## Pipelines
See ARCHITECTURE.md for pipeline definitions.

## Identity Verification
Required format: ✓ IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].
```

### Step 8: Create ARCHITECTURE.md in Project

Create `ARCHITECTURE.md` in project root with routing tables, pipelines, JSON fields, etc.

### Step 9: Create Serena Project Configuration

Create `.serena/project.yml` in project root:

```yaml
project_name: "YourProject"
languages:
  - python
  - typescript
encoding: "utf-8"
ignore_all_files_in_gitignore: true
read_only: false
```

### Step 10: Verify Setup

```bash
# Linux/macOS
# Check plugin
ls -la ~/.config/opencode/plugins/workflow-enforcement.ts

# Check agents
ls -la ~/.config/opencode/agents/*.md

# Check project files
ls -la ./AGENTS.md ./ARCHITECTURE.md .serena/project.yml

# Check logs after starting OpenCode
tail -100 ~/.local/share/opencode/log/opencode.log

# Check plugin initialization
grep "Workflow enforcement plugin initialized" ~/.local/share/opencode/log/*.log
```

```powershell
# Windows (PowerShell)
Get-ChildItem "$env:USERPROFILE\.config\opencode\plugins\workflow-enforcement.ts"
Get-ChildItem "$env:USERPROFILE\.config\opencode\agents\*.md"
Get-ChildItem ".\AGENTS.md", ".\ARCHITECTURE.md", ".\.serena\project.yml"
Get-Content "$env:USERPROFILE\.local\share\opencode\log\opencode.log" -Tail 100
Select-String "Workflow enforcement plugin initialized" "$env:USERPROFILE\.local\share\opencode\log\*.log"
```

### Step 11: Test Routing Table Enforcement

1. Start session with orchestrator
2. Try calling `plan-writer-simple` (should be BLOCKED)
3. Try calling `worker` (should be ALLOWED)

Expected blocked call message:
```
🚫 WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT
Current Agent: orchestrator
Attempted Call: plan-writer-simple
...
```

### Step 12: Test Identity Probe

1. Start session with orchestrator
2. orchestrator should call `orchestrator-identity-probe`
3. Should output: `✓ IDENTITY VERIFIED: I am orchestrator. I am NOT plankestrator.`

### Deployment Checklist

| # | Step | Status |
|---|------|--------|
| 1 | Install prerequisites (Python, Node.js, uv) | ⬜ |
| 2 | Install OpenCode | ⬜ |
| 3 | Create `~/.config/opencode/plugins/` directory | ⬜ |
| 4 | Create `~/.config/opencode/agents/` directory | ⬜ |
| 5 | Copy `workflow-enforcement.ts` to plugins | ⬜ |
| 6 | Copy agent `.md` files to agents directory | ⬜ |
| 7 | Configure `opencode.json` | ⬜ |
| 8 | Install Serena (`uv tool install serena-agent`) | ⬜ |
| 9 | Initialize Serena (`serena init`) | ⬜ |
| 10 | Create `AGENTS.md` in project root | ⬜ |
| 11 | Create `ARCHITECTURE.md` in project root | ⬜ |
| 12 | Create `.serena/project.yml` in project root | ⬜ |
| 13 | Verify plugin initialization in logs | ⬜ |
| 14 | Test routing table enforcement | ⬜ |
| 15 | Test identity probe | ⬜ |
| 16 | Test Serena language detection | ⬜ |

---

## 14. Troubleshooting

### Plugin Not Loading

**Problem**: No "Workflow enforcement plugin initialized" in logs

**Solutions**:
1. Check path in `opencode.json`: `"plugins": ["./plugins/workflow-enforcement.ts"]`
2. Verify file exists: `ls ~/.config/opencode/plugins/workflow-enforcement.ts`
3. Check TypeScript syntax
4. Restart OpenCode

### Routing Violations Not Blocked

**Problem**: Agent can call agents outside whitelist

**Solutions**:
1. Check `currentAgent` detection: `grep "agent detected" ~/.local/share/opencode/log/*.log`
2. Verify routing tables in plugin match ARCHITECTURE.md
3. Check `tool.execute.before` hook is working
4. Run `consistency-checker` to validate configuration

### JSON Validation Errors

**Problem**: Invalid JSON not detected

**Solutions**:
1. Check `message.updated` event is handled
2. Verify `REQUIRED_JSON_FIELDS` in plugin
3. Ensure agent outputs valid JSON format
4. Check for missing fields in agent output

### Identity Drift Not Detected

**Problem**: Agent changes identity without warning

**Solutions**:
1. Check JSON contains `agent` field
2. Search logs: `grep "IDENTITY DRIFT" ~/.local/share/opencode/log/*.log`
3. Verify `session.updated` hook is working
4. Check agent outputs correct identity verification

### Serena Not Detecting Languages

**Problem**: Language servers not starting

**Solutions**:
1. Check `.serena/project.yml` has correct `languages` list
2. Verify language-specific dependencies are installed
3. Run `serena init` again
4. Check Serena logs for language server errors
5. Verify language key is correct (e.g., `typescript` for JavaScript)

### Serena Tools Not Available

**Problem**: Serena tools not appearing in tool list

**Solutions**:
1. Check Serena MCP server configuration in `opencode.json`
2. Verify Serena is installed: `serena --version`
3. Check MCP server is running: `serena mcp-server --transport stdio`
4. Restart OpenCode after Serena installation

### OpenCode Permissions Blocking Calls

**Problem**: Calls blocked before plugin hook runs

**Solutions**:
1. Check OpenCode's permission logs separately
2. Verify agent is in OpenCode's agent registry
3. Check agent file path in `opencode.json`

---

## 15. File Locations Reference

### Configuration Files

| Item | Path | Purpose |
|------|------|---------|
| Main Config | `~/.config/opencode/opencode.json` | OpenCode configuration |
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` | Workflow enforcement plugin |
| Agents | `~/.config/opencode/agents/*.md` | Agent definitions |
| Serena Config | `.serena/project.yml` | Serena project configuration |
| Serena Local | `.serena/project.local.yml` | Local overrides (not versioned) |

### Project Documentation

| Item | Location | Purpose |
|------|----------|---------|
| Project Rules | `AGENTS.md` | Rules for agents to follow |
| Architecture | `ARCHITECTURE.md` | Single source of truth for architecture |
| Plugin Docs | `PLUGIN.md` | Plugin documentation |
| MCP Setup | `MCP_SETUP.md` | This file |
| Identity Probes | `identity_probe_section.md` | Identity probe documentation |

### Data Storage

| Item | Path | Format |
|------|------|--------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | JSON |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Various |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | JSON |
| Logs | `~/.local/share/opencode/log/` | `.log` files |
| Serena Cache | `.serena/cache/` | Language server cache |

### Serena Files

| Item | Location | Purpose |
|------|----------|---------|
| Project Config | `.serena/project.yml` | Language and tool configuration |
| Local Overrides | `.serena/project.local.yml` | Local development settings |
| Gitignore | `.serena/.gitignore` | Ignore cache and local config |
| Memories | `.serena/memories/` | Project-specific memories |

---

## Appendices

### Appendix A: Debug Commands

```bash
# Linux/macOS
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

# Combined search
grep -E "(WORKFLOW VIOLATION|IDENTITY DRIFT|INVALID JSON|Workflow enforcement)" ~/.local/share/opencode/log/*.log
```

```powershell
# Windows (PowerShell)
Get-Content "$env:USERPROFILE\.local\share\opencode\log\opencode.log" -Tail 100
Select-String "WORKFLOW VIOLATION" "$env:USERPROFILE\.local\share\opencode\log\*.log"
Select-String "IDENTITY DRIFT" "$env:USERPROFILE\.local\share\opencode\log\*.log"
Select-String "INVALID JSON" "$env:USERPROFILE\.local\share\opencode\log\*.log"
Select-String "Workflow enforcement" "$env:USERPROFILE\.local\share\opencode\log\*.log"
Select-String "(WORKFLOW VIOLATION|IDENTITY DRIFT|INVALID JSON|Workflow enforcement)" "$env:USERPROFILE\.local\share\opencode\log\*.log"
```

### Appendix B: Architecture Summary

| Component | Count | Description |
|-----------|-------|-------------|
| MCP Servers | 5 | zread, webSearchPrime, webReader, Serena, Unity |
| Primary Agents | 2 | orchestrator, plankestrator |
| Subagents (orchestrator) | 20 | For operational tasks |
| Subagents (plankestrator) | 9 | For planning and research |
| Pipelines | 8 | BUGFIX (2), DEV (2), DEVOPS, DOCS, PLAN, RESEARCH |
| Plugin Hooks | 6 | lifecycle hooks for enforcement |
| Identity Probes | 2 | One per primary agent |
| Serena Languages | 40+ | Via language servers |

### Appendix C: Complete File List for Deployment

| File | Source | Target | Size |
|------|--------|--------|------|
| workflow-enforcement.ts | Project | `~/.config/opencode/plugins/` | ~512 lines |
| opencode.json | Config | `~/.config/opencode/` | ~50 lines |
| orchestrator.md | Project | `~/.config/opencode/agents/` | ~100 lines |
| plankestrator.md | Project | `~/.config/opencode/agents/` | ~80 lines |
| orchestrator-identity-probe.md | Project | `~/.config/opencode/agents/` | ~20 lines |
| plankestrator-identity-probe.md | Project | `~/.config/opencode/agents/` | ~20 lines |
| worker.md | Project | `~/.config/opencode/agents/` | ~50 lines |
| utility.md | Project | `~/.config/opencode/agents/` | ~30 lines |
| consistency-checker.md | Project | `~/.config/opencode/agents/` | ~60 lines |
| docs-writer.md | Project | `~/.config/opencode/agents/` | ~40 lines |
| AGENTS.md | Project | Project root | ~274 lines |
| ARCHITECTURE.md | Project | Project root | ~268 lines |
| PLUGIN.md | Project | Project root | ~856 lines |
| MCP_SETUP.md | Project | Project root | This file |
| .serena/project.yml | Project | Project root | ~157 lines |

### Appendix D: Serena Language Server Requirements

| Language | Additional Requirements |
|----------|------------------------|
| C# | .NET v10+, PowerShell 7+ (Windows) |
| C/C++ | compile_commands.json recommended |
| Go | gopls installed |
| Rust | rustup installed |
| Ruby | ruby-lsp (default) or Solargraph |
| PHP | Intelephense (default) or Phpactor |
| Elixir | Elixir installation |
| Haskell | HLS via ghcup, stack, or PATH |
| F# | .NET v8.0+ |
| Fortran | fortls (`pip install fortls`) |
| Perl | Perl::LanguageServer |
| R | languageserver R package |
| Scala | Metals LSP (manual setup) |
| Zig | ZLS installed |
| Nix | nixd installed |
| Erlang | beam and erlang_ls |
| Elm | Elm compiler |
| Groovy | groovy-language-server.jar |
| Haxe | Haxe compiler 3.4.0+, Node.js |
| OCaml | opam and ocaml-lsp-server |
| Lean 4 | elan |
| Crystal | Crystalline on PATH |
| JSON | Node.js and npm |
| Ansible | Node.js, npm, ansible in PATH |
| Solidity | Node.js, npm |

---

## Summary

This document provides complete instructions for replicating the OpenCode infrastructure:

1. **Dual Primary Agents**: orchestrator (operational) and plankestrator (planning)
2. **Routing Tables**: 20 agents for orchestrator, 9 for plankestrator
3. **Pipelines**: 8 workflows for different task types
4. **JSON Validation**: Required fields for each agent type
5. **Workflow Enforcement Plugin**: 6 hooks for routing, identity, and validation
6. **Identity Probes**: Verification mechanism for primary agents
7. **MCP Servers**: zread, webSearchPrime, webReader, Serena, Unity
8. **Unity MCP Server**: Official Unity Editor integration for game development automation
9. **Serena**: IDE-level coding agent with 40+ language support
10. **Deployment Guide**: Step-by-step instructions with checklist
11. **Troubleshooting**: Common issues and solutions

For detailed plugin documentation, see `PLUGIN.md`.
For architecture requirements, see `ARCHITECTURE.md`.
For project rules, see `AGENTS.md`.

---

## Recent Updates (2026-05-04)

### Added
- **Serena MCP Server** — Complete integration with OpenCode
- **Serena Language Configuration** — Support for 40+ languages
- **Serena MCP Rules** in AGENTS.md — Tool priority guidelines
- **Key Agent Permissions** section — Permission configurations for reviewers

### Changed
- **devops-reviewer** — `bash: deny` → `bash: allow` (for git read-only operations)
- **worker** — Model changed to `alibaba-coding-plan/qwen3.6-plus`
- **devops-reviewer** — Model changed to `alibaba-coding-plan/qwen3.6-plus`
- **orchestrator permission** — Added `serena_*: allow` for Serena tools
- **orchestrator prompt** — Added Tool Priority section

### Fixed
- **Workflow Enforcement Plugin** — Routing fallback for agent detection
- **TypeScript errors** — Type casts for plugin validation
- **JSON field inconsistency** — Removed `state` and `pipeline_step` from orchestrator prompt

### Deployment Checklist Update

After pulling latest changes, ensure:
1. Update agent `.md` files with correct models (worker, devops-reviewer)
2. Update `.serena/project.yml` with languages for your project
3. Review permission changes in `opencode.json`
4. Test Serena integration with `/mcps` command
