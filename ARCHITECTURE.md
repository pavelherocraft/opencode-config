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
| 10 | devops-agent | DevOps tasks |
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
## Subagent Models

| Agent | Model |
|-------|-------|
| worker | alibaba-coding-plan/qwen3.6-plus |
| bugfix-triage | alibaba-coding-plan/qwen3.6-plus |
| bugfix | alibaba-coding-plan/qwen3.6-plus |
| plan-bug | alibaba-coding-plan/qwen3.6-plus |
| execute-bug | zai-coding-plan/glm-5.1 |
| dev-planner | alibaba-coding-plan/qwen3.6-plus |
| dev-professor | zai-coding-plan/glm-5.1 |
| dev-reviewer | kimi-for-coding/k2p6 |
| rework | zai-coding-plan/glm-5.1 |
| consistency-checker | alibaba-coding-plan/qwen3.6-plus |
| docs-writer | alibaba-coding-plan/glm-5 |
| utility | minimax-coding-plan/MiniMax-M2.7 |
| mcp-github | minimax-coding-plan/MiniMax-M2.7 |
| mcp-read | minimax-coding-plan/MiniMax-M2.7 |
| mcp-search | minimax-coding-plan/MiniMax-M2.7 |
| summarizer | minimax-coding-plan/MiniMax-M2.7 |
| devops-agent | alibaba-coding-plan/qwen3.6-plus |
| devops-reviewer | alibaba-coding-plan/qwen3.6-plus |

### Permission Notes

| Agent | Special Permissions |
|-------|-------------------|
| devops-reviewer | `read: allow` in addition to `bash: allow` |
| devops-agent | `bash: allow` only |


### Write Permissions (plankestrator subagents)

| Agent | Permission | Restriction |
|-------|------------|-------------|
| plan-writer-simple | `write: allow` | Only .md files, user request required |
| plan-writer-complex | `write: allow` | Only .md files, user request required |
| plan-reviewer-simple | `write: allow` | Only .md files, user request required |
| plan-reviewer-complex | `write: allow` | Only .md files, user request required |
| research-writer-simple | `write: allow` | Only .md files, user request required |
| research-writer-complex | `write: allow` | Only .md files, user request required |
| research-reviewer | `write: allow` | Only .md files, user request required |
| devops-readonly | `write: allow` | Only .md files, user request required (backup) |

### Permission Authority

⚠️ IMPORTANT: opencode.json is the authoritative source for agent permissions

**Frontmatter permissions in agent .md files are documentation only.**
They are **overridden by opencode.json** configuration.

**Rule:** Always ensure opencode.json matches the intended permissions defined in ARCHITECTURE.md.

**Warning:** If frontmatter says `write: allow` but opencode.json says `"write": "deny"`, the agent will NOT have write access. The write tool will NOT be injected.

**Example:**
```yaml
# agent.md frontmatter (documentation only)
permission:
  write: allow  # ← This is NOT used by opencode!
```

```json
// opencode.json (authoritative)
"permission": {
  "write": "allow"  // ← This is what opencode actually uses!
}
```

**Both must match for the agent to work correctly.**

**Note:** plankestrator has `write: deny` — it MUST delegate to subagents, never write directly.

**Restrictions enforced in agent prompts:**
- File type: ONLY `.md` (Markdown) files
- User request: ONLY when user explicitly asks to write/save
- Forbidden: Any non-.md files (code, config, etc.)

### Direct Write Instruction

All writer agents have a "Direct Write Instruction" section in their prompts:

- **Write directly** using `write: allow` permission
- **DO NOT call other agents** for file operations
- **DO NOT delegate** to devops-readonly or any other agent

devops-readonly is for READING only — use it to read files, but NEVER call it for writing.

### Plankestrator Delegation Rule

plankestrator is a pure orchestrator — it MUST ALWAYS delegate to subagents:

| Task Type | Subagent to Call |
|-----------|------------------|
| PLAN (simple) | `plan-writer-simple` |
| PLAN (complex) | `plan-writer-complex` |
| RESEARCH (simple) | `research-writer-simple` |
| RESEARCH (complex) | `research-writer-complex` |
| RESEARCH+PLAN | `research-writer-*` → `plan-writer-*` |

**File output handling:**
- If user requests "write plan to X.md", plankestrator passes instruction to subagent
- Subagent (with `write: allow`) handles the actual file writing
- plankestrator NEVER writes files directly

## 2. Pipelines

### BUGFIX (SIMPLE)

```
bugfix-triage → worker → utility
```

### BUGFIX DEEP

```
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility
```

### DEV SIMPLE

```
worker → utility
```

### DEV COMPLEX

```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility
```

### DEVOPS

```
devops-agent → devops-reviewer
```

### DOCS

```
docs-writer → utility
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

### Plugin Agent Detection

The workflow-enforcement plugin detects the agent using multiple methods (priority order):

1. **IDENTITY VERIFIED text** — highest priority
   - Extracted from "IDENTITY VERIFIED: I am orchestrator..." text
   - `extractIdentityFromMessage()` function in plugin

2. **JSON output** — secondary priority
   - Extracted from JSON `"agent"` field
   - `extractJSONFromMessage()` function in plugin

3. **Reverse routing lookup** — fallback
   - If agent calls a subagent, detect based on routing table
   - `detectAgentFromSubagent()` function in plugin

This ensures correct agent identification even if session data is incorrect.
