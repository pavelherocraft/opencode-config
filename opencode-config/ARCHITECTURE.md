# Architecture Requirements

This file is the single source of truth for the OpenCode dual-primary-agent architecture. All other files must be consistent with this document.

## 1. Routing Tables

### orchestrator Whitelist (21 agents)

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
| 10 | bugfix-triage | Initial bug analysis |
| 11 | plan-bug | Bug fix planning |
| 12 | devops-agent | DevOps operations |
| 13 | devops-reviewer | DevOps review |
| 14 | dev-planner | Development planning |
| 15 | mcp-search | Web search |
| 16 | docs-writer | Documentation writing |
| 17 | summarizer | Content summarization |
| 18 | execute-bug | Bug fix implementation |
| 19 | consistency-checker | Architecture consistency validation |
| 20 | explore | Fast codebase exploration |
| 21 | view-image | Image analysis |
| 22 | devops | Legacy DevOps tasks (alias) |

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
| orchestrator | 21 | 22 (orchestrator + 21 subagents) |
| plankestrator | 9 | 10 (plankestrator + 9 subagents) |
| **Grand Total** | **30** | **32** |

Note: 30 unique subagents + 2 primary agents = 32 unique agents total.

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

| Agent | Special Permissions | Reason |
|-------|-------------------|--------|
| worker | `bash: allow` | Implementation agent — needs bash for npm install, git operations, running tests, executing commands |
| bugfix | `bash: allow` | Bug fixing agent — needs bash for running tests, git operations |
| execute-bug | `bash: allow` | Bug fix implementation — needs bash for running tests, executing commands |
| rework | `bash: allow` | Rework agent — needs bash for running tests, git operations |
| devops-reviewer | `read: allow` in addition to `bash: allow` | DevOps review — needs bash for running commands, read for checking files |
| devops-agent | `bash: allow` only | DevOps operations — needs bash for npm, docker, deployment commands |

### Worker Bash Permission Details

Worker is the implementation agent — it MUST have `bash: allow` to execute commands:

| Command Type | Examples |
|--------------|----------|
| npm operations | `npm install`, `npm run build`, `npm run test` |
| git operations | `git status`, `git add`, `git commit`, `git push` |
| file operations | `mkdir`, `touch`, `rm` |
| linting tools | `eslint`, `prettier`, `tsc` |
| test runners | `jest`, `vitest`, `pytest` |
| any CLI tools | Any command-line tool execution |

**Critical:** Without `bash: allow`, worker cannot implement changes — it would be unable to run tests, install dependencies, or execute any commands.


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
bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV SIMPLE

DEV SIMPLE has two variants depending on whether a plan exists:

| Variant | Flow | When to Use |
|---------|------|-------------|
| DEV SIMPLE (without plan) | `worker → utility` | plan_exists=false — direct implementation and validation |
| DEV SIMPLE (with plan) | `worker → consistency-checker → [rework loop, max 3] → utility` | plan_exists=true — plan-validated implementation with rework loop |

**Decision rule:** If plan_exists=true, use the "with plan" variant. Otherwise, use the "without plan" variant.

**Rework loop:** If consistency-checker finds critical issues, task returns to worker for fixes. Loop repeats up to 3 iterations. If consistency-checker passes → utility. If max iterations reached → failure report.

### DEV COMPLEX

```
dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility
```

**Rework loop:** If consistency-checker finds critical issues after the initial rework, task returns to `rework` for additional fixes. Loop repeats up to 3 iterations.

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
| `escalate_to` | string \| null | `"dev-reviewer"` \| `"rework"` \| `"worker"` \| `"execute-bug"` \| `null` |

### escalate_to Field — Expanded Values

The `escalate_to` field in consistency-checker output determines which agent receives the task when issues are found.

| Value | When to Use | Pipeline Context |
|-------|-------------|------------------|
| `"dev-reviewer"` | Issues require architectural review or design decisions | DEV COMPLEX, BUGFIX DEEP (before rework) |
| `"rework"` | Issues are concrete and can be fixed by applying feedback | DEV COMPLEX (after rework), BUGFIX DEEP (after rework), DEV PLAN EXISTS |
| `"worker"` | Issues are simple implementation fixes | DEV PLAN EXISTS (simple rework loop) |
| `"execute-bug"` | Issues are bug-specific and require targeted bug fix | BUGFIX DEEP (if rework cannot fix) |
| `null` | No escalation needed (consistency-checker passed) | All pipelines |

**Decision logic for consistency-checker:**
```
if issues_found == 0:
    escalate_to = null
elif issues are architectural/design-level:
    escalate_to = "dev-reviewer"
elif issues are concrete fixable items and pipeline has rework agent:
    escalate_to = "rework"
elif issues are simple implementation fixes:
    escalate_to = "worker"
elif issues are bug-specific:
    escalate_to = "execute-bug"
else:
    escalate_to = "dev-reviewer"  # default fallback
```

## 4. MCP Servers

| Server Name | MCP Tool Prefix | Purpose |
|-------------|-----------------|---------|
| zread | `zread_` | GitHub repository reading: `search_doc`, `get_repo_structure`, `read_file` |
| webSearchPrime | `webSearchPrime_` | Web search: `web_search_prime` |
| webReader | `webReader_` | URL content reading: `webReader` |
| serena | `serena_` | Code symbol operations: `find_symbol`, `rename_symbol`, etc. |
| unity | `Unity.` | Unity Editor operations: `ManageGameObject`, `ManageScene`, etc. |

### Usage Rules

- Use `webSearchPrime` for all web searches — do NOT use `webfetch`
- Use `webReader` for reading URL content — do NOT use `webfetch`
- Use `zread` tools for GitHub repositories — do NOT use `webfetch` or manual browsing

### Serena MCP Rules

**⚠️ MANDATORY: Serena tools are PRIMARY for code operations**

| Task | PRIMARY (Serena) | SECONDARY (Built-in) |
|------|------------------|---------------------|
| Find symbol by name | `serena_find_symbol` | grep (fallback) |
| Find all usages | `serena_find_referencing_symbols` | grep (fallback) |
| File structure overview | `serena_get_symbols_overview` | read (fallback) |
| Rename symbol | `serena_rename_symbol` | edit (fallback) |
| Delete symbol | `serena_safe_delete_symbol` | edit (fallback) |
| Replace symbol body | `serena_replace_symbol_body` | edit (fallback) |
| Insert after symbol | `serena_insert_after_symbol` | edit (fallback) |

**DO NOT use built-in tools (grep, read, glob, edit) for symbol operations — USE Serena tools MAXIMALLY ALWAYS**

### unity-mcp Rules

**⚠️ MANDATORY: unity-mcp is PRIMARY for Unity operations — use it MAXIMALLY ALWAYS**

| Task | unity-mcp Tool | Do NOT Use |
|------|----------------|------------|
| Create GameObject | `unity-mcp_manage_gameobject` | edit (manual) |
| Modify GameObject | `unity-mcp_manage_gameobject` | edit (manual) |
| Create/Save Scene | `unity-mcp_manage_scene` | bash (manual) |
| Create C# Script | `unity-mcp_create_script` | write (manual) |
| Edit C# Script | `unity-mcp_manage_script` | edit (manual) |
| Import Assets | `unity-mcp_manage_asset` | bash (manual) |
| Read Console Logs | `unity-mcp_read_console` | read (log files) |
| Validate Scripts | `unity-mcp_validate_script` | bash (manual) |

**unity-mcp tools → auto-approved → agent can use immediately**
**Built-in tools for Unity → asks user → nudges agent to use unity-mcp**

**DO NOT use built-in tools (edit, write, bash) for Unity operations — USE unity-mcp tools MAXIMALLY ALWAYS**

**Prerequisites:**
- Unity 2021.3 LTS or later
- Python 3.10+ and uv installed
- Unity MCP package from CoplayDev: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
- Unity Editor must be running with MCP server started

## unity-mcp Permissions

### ALL Agents Have unity-mcp Access

unity-mcp is available for ALL agents, not just orchestrator and plankestrator.

| Agent Category | unity-mcp Permission | Reason |
|----------------|---------------------|--------|
| Primary agents | `unity-mcp.*: allow` | orchestrator, plankestrator route Unity tasks |
| Implementation agents | `unity-mcp.*: allow` | worker, bugfix, execute-bug, rework implement Unity changes |
| Development agents | `unity-mcp.*: allow` | dev-professor, dev-reviewer, dev-planner guide Unity development |
| Validation agents | `unity-mcp.*: allow` | consistency-checker, utility, docs-writer validate Unity code |
| DevOps agents | `unity-mcp.*: allow` | devops-agent, devops-reviewer, bugfix-triage, plan-bug manage Unity builds |
| MCP agents | `unity-mcp.*: allow` | mcp-github, mcp-read, mcp-search, summarizer read Unity content |
| Planning agents | `unity-mcp.*: allow` | plan-writer-*, plan-reviewer-*, research-writer-*, research-reviewer plan Unity features |
| Read-only agents | `unity-mcp.*: allow` | devops-readonly reads Unity DevOps info |

### unity-mcp Tools Available

All agents can use these unity-mcp tools:
- `unity-mcp_manage_gameobject` — create, find, modify, delete GameObjects
- `unity-mcp_manage_scene` — load, save, create scenes, query hierarchy
- `unity-mcp_manage_asset` — asset management operations
- `unity-mcp_create_script` — create C# scripts
- `unity-mcp_delete_script` — delete C# scripts
- `unity-mcp_manage_script` — CRUD operations on C# scripts
- `unity-mcp_script_apply_edits` — advanced script editing
- `unity-mcp_apply_text_edits` — apply text edits to C# scripts
- `unity-mcp_validate_script` — validate C# scripts
- `unity-mcp_manage_shader` — CRUD operations on shader files
- `unity-mcp_read_console` — read/clear Unity Editor console logs
- `unity-mcp_manage_editor` — control/query Editor state, Tags, Layers
- `unity-mcp_manage_components` — add/remove/set properties on components
- `unity-mcp_manage_prefabs` — manage Unity Prefab assets
- `unity-mcp_manage_material` — manage Unity materials
- `unity-mcp_manage_animation` — manage Unity animation
- `unity-mcp_manage_vfx` — manage ParticleSystem, VisualEffect
- `unity-mcp_manage_camera` — manage cameras (Unity Camera + Cinemachine)
- `unity-mcp_manage_build` — manage Unity player builds
- `unity-mcp_manage_packages` — manage Unity packages
- `unity-mcp_manage_physics` — manage physics settings, collision matrix
- `unity-mcp_manage_ui` — manage Unity UI Toolkit
- `unity-mcp_manage_graphics` — manage rendering graphics
- `unity-mcp_manage_probuilder` — manage ProBuilder meshes
- `unity-mcp_manage_profiler` — Unity Profiler session control
- `unity-mcp_batch_execute` — batch execute (10-100x faster)
- `unity-mcp_unity_docs` — fetch official Unity documentation
- `unity-mcp_unity_reflect` — inspect Unity's live C# API

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
