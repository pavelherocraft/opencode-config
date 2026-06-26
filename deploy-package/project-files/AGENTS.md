# Project Rules

## MCP Tools Rules

### Search
Always use `zai_web_search` MCP tool for web search. Do NOT use webfetch.

### Read URLs
Always use `zai_web_reader` MCP tool for reading webpage content. Do NOT use webfetch.

### GitHub Repositories
Always use `zai_zread` MCP tools for GitHub repositories.

## Image Analysis Rules

### view-image agent is PRIMARY for image analysis
Call via Task tool with `subagent_type: "view-image"`. Uses `bifrost-litellm/Kimi K2.6` with direct vision.

## Serena MCP Rules

Serena tools are PRIMARY for code operations. Built-in tools (grep, read, edit) are SECONDARY.

| Task | PRIMARY (Serena) | SECONDARY (Built-in) |
|------|------------------|---------------------|
| Find symbol | `serena_find_symbol` | grep |
| Find usages | `serena_find_referencing_symbols` | grep |
| File overview | `serena_get_symbols_overview` | read |
| Rename symbol | `serena_rename_symbol` | edit |
| Delete symbol | `serena_safe_delete_symbol` | edit |
| Replace body | `serena_replace_symbol_body` | edit |
| Insert code | `serena_insert_after_symbol` | edit |

## unity-mcp Rules

unity-mcp is PRIMARY for ALL Unity operations. Available for ALL agents.

## Architecture Requirements

All architecture requirements are defined in ARCHITECTURE.md.

## Dual Primary Agents Architecture

| Primary Agent | Workflows |
|---------------|-----------|
| orchestrator | BUGFIX, DEVOPS, DEV, DOCS |
| plankestrator | PLAN, RESEARCH, RESEARCH+PLAN |

## Routing Tables

### orchestrator Whitelist (21 agents)
orchestrator-identity-probe, dev-reviewer, dev-professor, mcp-github, worker, bugfix, rework, mcp-read, utility, bugfix-triage, plan-bug, devops-agent, devops-reviewer, dev-planner, mcp-search, docs-writer, summarizer, execute-bug, consistency-checker, view-image, docs-planner

### plankestrator Whitelist (9 agents)
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly

## Key Agent Permissions

### Worker Bash Permission — CRITICAL
Worker MUST have `bash: allow` for npm, git, tests, linting, CLI tools.

### View-Image Permission
All build agents have `task.view-image: allow`.

## Pipelines

| Pipeline | Flow |
|----------|------|
| BUGFIX SIMPLE | bugfix-triage → worker → utility |
| BUGFIX DEEP | bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [rework max 3] → utility |
| DEV SIMPLE (no plan) | worker → utility |
| DEV SIMPLE (with plan) | worker → consistency-checker → [rework max 3] → utility |
| DEV COMPLEX | dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [rework max 3] → utility |
| DEV SUPERCOMPLEX | PER STEP: dev-planner → dev-professor → dev-reviewer → consistency-checker → [rework max 3] → utility |
| DEVOPS | devops-agent → devops-reviewer |
| DOCS SIMPLE | docs-writer → utility |
| DOCS DEEP | docs-planner → docs-writer → dev-reviewer → rework → consistency-checker → [rework max 3] → utility |
| PLAN | plan-writer-* → plan-reviewer-* |
| RESEARCH | research-writer-* → research-reviewer |

### Auto-DOCS Hook
After final `utility` step of BUGFIX/DEV pipelines, if `requires_docs_update: true` → call `docs-writer → utility`.

## Identity Verification

Both primary agents output: `IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].`

## Identity Lock Mechanism (v3)
1. Session start — plugin reads `session.agent` from `session.created`
2. RUNTIME IDENTITY block in agent prompts
3. Identity drift = hard error
4. Forbidden vocabulary check
5. Model: both run on `bifrost-litellm/QWEN3.7-plus`

## Workflow Enforcement Plugin
Location: `./plugins/workflow-enforcement.ts`

## File Locations
- Main Config: `~/.config/opencode/opencode.json`
- Plugin: `~/.config/opencode/plugins/workflow-enforcement.ts`
- Agents: `~/.config/opencode/agents/*.md`
