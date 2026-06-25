# Project Rules

## MCP Tools Rules

### Search

Always use the webSearchPrime MCP tool for web search. Do NOT use webfetch for searching.

- Use webSearchPrime for all web searches, finding information, documentation, and resources
- When the user asks you to find, search, or look up something — use webSearchPrime first
- Search queries work best in English; translate Russian queries to English before searching

### Read URLs

Always use the webReader MCP tool for reading webpage content. Do NOT use webfetch.

- Use webReader when you need to read or analyze content from a specific URL
- webReader returns structured content including title, main body, metadata, and links
- webfetch should NOT be used — prefer webReader for all URL reading tasks

### GitHub Repositories and Open Source Documentation

Always use the zread MCP tools for working with GitHub repositories. Do NOT use webfetch or manual browsing.

- Use search_doc to search documentation, issues, PRs, and code in any GitHub repository
- Use get_repo_structure to get the directory structure and file list of a repository
- Use read_file to read the complete content of a specific file in a repository
- When you ask about a library, framework, or open source project — use zread tools first

## Image Analysis Rules

### ⚠️ MANDATORY: view-image agent is PRIMARY for image analysis

**When you need to analyze an image, ALWAYS call view-image agent via Task tool:**

```
Task tool:
- subagent_type: "view-image"
- prompt: "Analyze this image: [describe what you need]"
```

**view-image uses kimi-for-coding/k2p6 with direct vision capabilities.**

**DO NOT use zai-mcp-server tools directly — delegate to view-image agent.**

**Rules:**
- User provides image path/URL → Call view-image
- Need to describe screenshot → Call view-image
- Need to extract text from image → Call view-image
- Need to understand diagram → Call view-image
- Need to analyze UI mockup → Call view-image
- Use zai-mcp-server only as FALLBACK when view-image unavailable

### Serena MCP Rules

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

### Tool Priority Table

| Task | PRIMARY (Serena) | SECONDARY (Built-in) |
|------|------------------|---------------------|
| Find symbol by name | `serena_find_symbol` | grep (fallback) |
| Find all usages | `serena_find_referencing_symbols` | grep (fallback) |
| File structure overview | `serena_get_symbols_overview` | read (fallback) |
| Rename symbol | `serena_rename_symbol` | edit (fallback) |
| Delete symbol | `serena_safe_delete_symbol` | edit (fallback) |
| Replace symbol body | `serena_replace_symbol_body` | edit (fallback) |
| Insert after symbol | `serena_insert_after_symbol` | edit (fallback) |
| Text pattern search | grep | — |
| Read file content | read | — |
| Find files by name | glob | — |

## unity-mcp Rules

### ⚠️ MANDATORY: Unity operations MUST use unity-mcp

**For Unity projects, ALWAYS use unity-mcp (CoplayDev) tools MAXIMALLY ALWAYS:**

**unity-mcp is PRIMARY for ALL Unity operations — use it MAXIMALLY ALWAYS**

**unity-mcp is available for ALL agents and modes, not just orchestrator and plankestrator.**

**unity-mcp tools → auto-approved → use immediately**
**Built-in tools → asks user → nudges to use unity-mcp**

**ALL agents can use unity-mcp:**
- orchestrator, plankestrator (primary agents)
- worker, bugfix, execute-bug, rework (implementation agents)
- dev-professor, dev-reviewer, dev-planner (development agents)
- consistency-checker, utility, docs-writer (validation agents)
- devops-agent, devops-reviewer, bugfix-triage, plan-bug (DevOps agents)
- mcp-github, mcp-read, mcp-search, summarizer (MCP agents)
- plan-writer-*, plan-reviewer-*, research-writer-*, research-reviewer (planning agents)
- devops-readonly (read-only agent)

**DO NOT use built-in tools (edit, write, bash) for:**
- Creating GameObjects → USE `unity-mcp_manage_gameobject`
- Creating Scenes → USE `unity-mcp_manage_scene`
- Creating C# Scripts → USE `unity-mcp_create_script`
- Editing C# Scripts → USE `unity-mcp_manage_script` or `unity-mcp_script_apply_edits`
- Importing Assets → USE `unity-mcp_manage_asset`
- Reading Console → USE `unity-mcp_read_console`

| Task | unity-mcp Tool | Do NOT Use |
|------|----------------|------------|
| Create/Find/Modify/Delete GameObjects | `unity-mcp_manage_gameobject` | edit (manual) |
| Modify GameObject | `unity-mcp_manage_gameobject` | edit (manual) |
| Create/Save Scene | `unity-mcp_manage_scene` | bash (manual) |
| Create C# Script | `unity-mcp_create_script` | write (manual) |
| Edit C# Script | `unity-mcp_manage_script` | edit (manual) |
| Import Assets | `unity-mcp_manage_asset` | bash (manual) |
| Read Console Logs | `unity-mcp_read_console` | read (log files) |
| Asset management operations | `unity-mcp_manage_asset` | bash (manual) |
| Delete C# scripts | `unity-mcp_delete_script` | bash (manual) |
| CRUD operations on C# scripts | `unity-mcp_manage_script` | edit (manual) |
| Advanced script editing | `unity-mcp_script_apply_edits` | edit (manual) |
| Apply text edits to C# scripts | `unity-mcp_apply_text_edits` | edit (manual) |
| CRUD operations on shader files | `unity-mcp_manage_shader` | edit (manual) |
| Validate C# scripts | `unity-mcp_validate_script` | bash (manual) |
| Control/query Editor state, Tags, Layers | `unity-mcp_manage_editor` | edit (manual) |
| Manage packages | `unity-mcp_manage_packages` | bash (manual) |
| Manage prefabs | `unity-mcp_manage_prefabs` | edit (manual) |
| Manage materials | `unity-mcp_manage_material` | edit (manual) |
| Manage animations | `unity-mcp_manage_animation` | edit (manual) |
| Manage physics | `unity-mcp_manage_physics` | edit (manual) |
| Manage UI Toolkit | `unity-mcp_manage_ui` | edit (manual) |
| Manage VFX | `unity-mcp_manage_vfx` | edit (manual) |
| Manage camera | `unity-mcp_manage_camera` | edit (manual) |
| Manage build | `unity-mcp_manage_build` | bash (manual) |
| Manage profiler | `unity-mcp_manage_profiler` | bash (manual) |
| Manage graphics | `unity-mcp_manage_graphics` | edit (manual) |
| Batch execute (10-100x faster) | `unity-mcp_batch_execute` | sequential calls |
| Unity docs lookup | `unity-mcp_unity_docs` | web search |
| Unity API reflection | `unity-mcp_unity_reflect` | guesswork |

**Built-in tools for Unity projects - use ONLY when:**
- unity-mcp is unavailable or not connected
- Unity Editor is not running
- Non-Unity files (README, config, etc.)

**Prerequisites:**
- Unity 2021.3 LTS or later
- Python 3.10+ and uv installed
- Unity MCP package installed via git URL: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
- Unity Editor must be running with MCP server started (`Window > MCP for Unity > Start Server`)
- Server runs on `http://localhost:8080/mcp`

## Architecture Requirements

All architecture requirements are defined in ARCHITECTURE.md in the project root.

- Routing tables (agent whitelists)
- Pipeline definitions
- JSON validation fields
- MCP server configurations
- Identity probe whitelists
- Outdated terms to check

The consistency-checker agent reads ARCHITECTURE.md to validate all configuration files.

## Dual Primary Agents Architecture

OpenCode uses two primary agents that handle different task types. Agents do NOT call each other — the user must manually switch between them.

### orchestrator


Handles operational and execution tasks:

- BUGFIX - Bug fixing workflows
- DEVOPS - DevOps operations
- DEV - Development tasks
- DOCS - Documentation writing

### plankestrator

Handles planning and research tasks:

- PLAN - Planning workflows
- RESEARCH - Research workflows
- RESEARCH+PLAN - Combined research and planning

## Routing Tables

### orchestrator Whitelist (21 agents)

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
| explore | Fast codebase exploration |
| view-image | Image analysis |

### plankestrator Whitelist (9 agents)

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

## Key Agent Permissions

### Worker Bash Permission — CRITICAL

Worker is the implementation agent — it MUST have `bash: allow` to execute commands:

| Command Type | Examples |
|--------------|----------|
| npm operations | `npm install`, `npm run build`, `npm run test` |
| git operations | `git status`, `git add`, `git commit`, `git push` |
| file operations | `mkdir`, `touch`, `rm`, `cp` |
| linting tools | `eslint`, `prettier`, `tsc --noEmit` |
| test runners | `jest`, `vitest`, `pytest`, `cargo test` |
| CLI tools | Any command-line tool execution |

**⚠️ CRITICAL:** Without `bash: allow`, worker cannot implement changes — it would be unable to:
- Install dependencies (`npm install`)
- Run tests (`npm run test`)
- Build projects (`npm run build`)
- Execute git operations
- Run linting/formatting tools
- Execute any CLI commands

**If worker reports "bash is not available", this is a configuration bug that must be fixed immediately.**

### View-Image Permission — Build Agents

All build agents have `task.view-image: allow` to delegate image analysis:

| Agent | Permission | Use Case |
|-------|------------|----------|
| worker | `view-image: allow` | Analyze UI screenshots, diagrams, error images |
| bugfix | `view-image: allow` | Analyze error screenshots during bug triage |
| execute-bug | `view-image: allow` | Visual verification of bug fixes |
| rework | `view-image: allow` | Compare before/after UI changes |

**Usage pattern:** Call via Task tool with `subagent_type: "view-image"`. view-image uses `kimi-for-coding/k2p6` with direct vision capabilities.

## Pipelines

### BUGFIX (SIMPLE)

bugfix-triage -> worker -> utility

Simple bug fixes use the straightforward pipeline with triage, implementation, and validation.

### BUGFIX DEEP

bugfix-triage -> plan-bug (writes bug_plan.md) -> execute-bug (reads bug_plan.md) -> dev-reviewer -> rework -> consistency-checker -> [rework loop, max 3] -> utility

Complex bug fixes include planning (plan-bug writes to bug_plan.md), execution (execute-bug reads from bug_plan.md), review, rework cycles, and consistency validation.

### DEV SIMPLE

DEV SIMPLE has two variants depending on whether a plan exists:

| Variant | Flow | When to Use |
|---------|------|-------------|
| DEV SIMPLE (без плана) | worker → utility | Straightforward tasks with no prior planning — direct implementation and validation. |
| DEV SIMPLE (с планом) | worker → consistency-checker → [rework loop, max 3] → utility | Tasks where a plan was created beforehand — implementation is validated against the plan by consistency-checker. If issues found, returns to worker for fixes (up to 3 iterations). |

**Decision rule:** If plan_exists=true, use the "с планом" variant. Otherwise, use the "без плана" variant.


### DEV COMPLEX


dev-planner -> dev-professor -> dev-reviewer -> rework -> consistency-checker -> [rework loop, max 3] -> utility


Complex development tasks include planning, guidance, review, rework, and consistency validation.

### DEV SUPERCOMPLEX

PER PLAN STEP: dev-planner -> dev-professor -> dev-reviewer -> consistency-checker -> [rework loop, max 3] -> utility

Super-complex tasks with a large plan (>3 steps) or huge volume of work. The full review/consistency/syntax chain runs **for every step** of the plan. Triggered by explicit request OR when a plan with more than 3 steps and huge volume of work exists.

### DEVOPS

devops-agent -> devops-reviewer

DevOps operations include implementation and review.

### DOCS

docs-writer -> utility

Documentation writing followed by validation.

### PLAN

plan-writer-* -> plan-reviewer-*

Planning workflows include writing and review, with specialized agents per plan type.

### RESEARCH

research-writer-* -> research-reviewer

Research workflows include writing and review.

## Identity Verification

Both primary agents output identity verification to prevent drift:

### Required Output Format

IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].

### JSON Output

Agents must include an agent field in their JSON output:

{
  agent: orchestrator | plankestrator,
  ...
}

## Identity Lock Mechanism (v3)

To prevent the orchestrator↔plankestrator confusion mode, the system uses a **machine-asserted identity lock** at session start:

1. **Session start** — `workflow-enforcement.ts` reads `session.agent` from the `session.created` event. If it identifies `orchestrator` or `plankestrator`, it sets `identityLocked = true` and records `lockedAgentName`. The agent cannot be re-bound after this point.
2. **RUNTIME IDENTITY block** — both primary agent prompts (`agents/orchestrator.md`, `agents/plankestrator.md`) start with an explicit `OPENCODE_AGENT_NAME = ...` block injected by opencode. The agent MUST check this block before any output; if it contradicts the agent file, the agent must refuse.
3. **Identity drift = hard error** — once `identityLocked = true`, any JSON output where `agent` does not match `lockedAgentName` is logged as `error` (not `warn`) and the agent's `currentAgent` value is NOT updated. Downstream Task calls are still validated against the locked routing table.
4. **Forbidden vocabulary check** — the plugin greps locked-agent message text for terminology that belongs to the other primary agent (e.g. orchestrator message containing "I am plankestrator" or "## PLAN"). Violations are logged as `error`.
5. **Model**: both primary agents run on `bifrost-litellm/QWEN3.7-plus` (Qwen 3.7 Plus via the bifrost-litellm provider).

### Session Naming Convention

Give every new session a clear name. The plugin uses the title as a fallback for identity detection if `session.agent` is not available. Recommended patterns:

- `orchestrator — fix login bug`
- `orchestrator — add user settings page`
- `plankestrator — plan auth refactor`
- `plankestrator — research state-management libs`

Avoid generic names like `New session` or `Untitled`. They prevent the plugin from locking identity early.

## Workflow Enforcement Plugin

### Location

./plugins/workflow-enforcement.ts

### Functionality

- Enforces routing tables via pre-call hooks
- Validates JSON output format includes required fields
- Detects and prevents identity drift
- Ensures agents stay within their whitelisted agent set

### Detailed Documentation


See PLUGIN.md for comprehensive documentation including:
- Lifecycle hooks (6 hooks)
- Error messages
- JSON validation rules
- Agent detection mechanism
- Debugging guide
- Known issues

### Installation

Configured in ~/.config/opencode/opencode.json under the plugins section.

## Data Storage

### Database

- File: opencode.db
- Format: SQLite
- Location: ~/.local/share/opencode/

### Session Storage

- Directory: storage/session_diff/
- Format: JSON files
- Content: Session differences and state changes

### Tool Outputs

- Directory: tool-output/
- Format: Various (JSON, text, logs)
- Content: Individual tool execution results

### Todo Lists

- Directory: storage/todo/
- Format: JSON files
- Content: Task lists and tracking

### Logs

- Directory: log/
- Format: .log files
- Content: Execution logs and debugging info

## File Locations

### Configuration

- Main Config: ~/.config/opencode/opencode.json
- Plugin: ~/.config/opencode/plugins/workflow-enforcement.ts
- Agents: ~/.config/opencode/agents/*.md

### Data


- Root: ~/.local/share/opencode/
- Database: ~/.local/share/opencode/opencode.db
- Storage: ~/.local/share/opencode/storage/
- Logs: ~/.local/share/opencode/log/
- Tool Outputs: ~/.local/share/opencode/tool-output/