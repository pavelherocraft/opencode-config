# Architecture Requirements

This file is the single source of truth for the OpenCode dual-primary-agent architecture. All other files must be consistent with this document.

## 1. Routing Tables

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

Note: 29 unique subagents + 2 primary agents = 31 unique agents total.

## 2. Pipelines

### BUGFIX (SIMPLE)

```
bugfix-triage → worker → consistency-checker → utility
```

### BUGFIX DEEP

```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → utility
```

### DEV SIMPLE

```
worker → consistency-checker → utility
```

### DEV COMPLEX

```
dev-planner → dev-professor → dev-reviewer → rework → utility
```

### DEVOPS

```
devops-agent → devops-reviewer
```

### DOCS

```
docs-writer → consistency-checker → utility
```

### PLAN

```
plan-writer-* → plan-reviewer-*
```

### RESEARCH

```
research-writer-* → research-reviewer
```

## 3. JSON Validation Fields

### orchestrator Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"orchestrator"` |
| `state` | string | `"CLASSIFY_TYPE"` |
| `type` | string \| null | `"BUGFIX"`, `"DEVOPS"`, `"DEV"`, `"DOCS"`, `null` |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `"DEEP"`, `null` |
| `plan_exists` | boolean \| null | `true`, `false`, `null` |
| `plan_source` | string \| null | description or `null` |
| `goal` | string | one sentence description |
| `next_agent` | string \| null | agent name from whitelist or `null` |
| `pipeline` | string[] | array of agent names or `[]` |

### plankestrator Required Fields

| Field | Type | Valid Values |
|-------|------|--------------|
| `agent` | string | `"plankestrator"` |
| `state` | string | `"CLASSIFY"`, `"EXECUTE"`, `"REVIEW"`, `"COMPLETE"` |
| `type` | string \| null | `"PLAN"`, `"RESEARCH"`, `"RESEARCH+PLAN"`, `null` |
| `complexity` | string \| null | `"SIMPLE"`, `"COMPLEX"`, `null` |
| `goal` | string | one sentence description |
| `next_agent` | string \| null | agent name from whitelist or `null` |
| `pipeline` | string[] | array of agent names or `[]` |

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

## 4. MCP Servers

| Server Name | MCP Tool Prefix | Purpose |
|-------------|-----------------|---------|
| zread | `zread_` | GitHub repository reading: `search_doc`, `get_repo_structure`, `read_file` |
| webSearchPrime | `webSearchPrime_` | Web search: `web_search_prime` |
| webReader | `webReader_` | URL content reading: `webReader` |

### Usage Rules

- Use `webSearchPrime` for all web searches — do NOT use `webfetch`
- Use `webReader` for reading URL content — do NOT use `webfetch`
- Use `zread` tools for GitHub repositories — do NOT use `webfetch` or manual browsing

## 5. Identity Probe Whitelists

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

## 6. Outdated Terms

These terms must NOT appear in any agent .md files, plugin code, or configuration:

| Term | Status | Replacement |
|------|--------|-------------|
| `ensemble` | REMOVE | Use `pipeline` or `workflow` |
| `team_*` (any team-prefixed name) | REMOVE | No replacement — legacy concept |
| `4747` | REMOVE | No replacement — debug artifact |

## 7. Primary Agent Roles

| Agent | Handles | Workflows |
|-------|---------|-----------|
| orchestrator | Operational and execution tasks | BUGFIX, DEVOPS, DEV, DOCS |
| plankestrator | Planning and research tasks | PLAN, RESEARCH, RESEARCH+PLAN |

Agents do NOT call each other — the user must manually switch between them.

## 8. File Locations

### Configuration

| Item | Path |
|------|------|
| Main Config | `~/.config/opencode/opencode.json` |
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Agents | `~/.config/opencode/agents/*.md` |
| Architecture (this file) | Project root `ARCHITECTURE.md` |

### Data Storage

| Item | Path | Format |
|------|------|--------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | JSON |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Various |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | JSON |
| Logs | `~/.local/share/opencode/log/` | `.log` files |

### Documentation

| Item | Location |
|------|----------|
| Project Rules | `AGENTS.md` (project root) |
| Plugin Docs | `PLUGIN.md` (project root) |
| Identity Probes | `identity_probe_section.md` (project root) |
| MCP Setup | `MCP_SETUP.md` (project root) |

## 9. Plugin Hooks

The workflow-enforcement plugin implements 6 lifecycle hooks:

| Hook | When | Purpose |
|------|------|---------|
| `tool.execute.before` | Before any tool call | Routing table enforcement — blocks invalid agent calls |
| `tool.execute.after` | After tool completes | Logs tool completion |
| `session.created` | New session starts | Detects which agent is running |
| `session.updated` | Session changes | Detects identity drift |
| `session.idle` | Session ends | Logs workflow summary |
| `message.updated` | Message added | Validates JSON output format |

## 10. Identity Verification Format

Both primary agents must output identity verification to prevent drift:

### Required Output Format

```
✓ IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].
```

### JSON Output Requirement

All agents must include an `"agent"` field in their JSON output:

```json
{
  "agent": "orchestrator",
  ...
}
```

or

```json
{
  "agent": "plankestrator",
  ...
}
```
