# Architecture Requirements

Single source of truth for the OpenCode dual-primary-agent architecture.

## 1. Routing Tables

### orchestrator Whitelist (24 agents)
orchestrator-identity-probe, dev-reviewer, dev-professor, mcp-github, worker, bugfix, rework, mcp-read, utility, bugfix-triage, plan-bug, devops-agent, devops-reviewer, dev-planner, mcp-search, docs-writer, summarizer, execute-bug, consistency-checker, view-image, docs-planner, generate-image, generate-image-gpt, git-commit

### plankestrator Whitelist (10 agents)
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly, view-image

### Shared Utility Agents
view-image is a shared utility agent available to BOTH primary agents. It is listed in BOTH routing tables (orchestrator and plankestrator) and granted `task.view-image: allow` in both permission blocks in opencode.json. It is used for image analysis (screenshots, diagrams, error images) via the Task tool.

### Agent Count: 33 unique subagents + 2 primary = 35 total

## Subagent Models

| Agent | Model |
|-------|-------|
| worker | bifrost-litellm/MiniMax-M3 |
| bugfix-triage | bifrost-litellm/GLM-5.3-Flash (res) |
| bugfix | bifrost-litellm/QWEN3.7-plus |
| plan-bug | bifrost-litellm/MiniMax-M3 |
| execute-bug | bifrost-litellm/GLM-5.3 (res) |
| dev-planner | bifrost-litellm/qwen3.8-max |
| dev-professor | bifrost-litellm/GLM-5.3 (res) |
| dev-reviewer | bifrost-litellm/Kimi K3 |
| rework | bifrost-litellm/Kimi K3 |
| consistency-checker | bifrost-litellm/QWEN3.7-plus |
| docs-writer | bifrost-litellm/mimo-v2.5-pro |
| docs-planner | bifrost-litellm/aliyun/qwen3.8-flash |
| utility | bifrost-litellm/MiniMax-M2.7 |
| mcp-github | bifrost-litellm/MiniMax-M2.7 |
| mcp-read | bifrost-litellm/MiniMax-M2.7 |
| mcp-search | bifrost-litellm/MiniMax-M2.7 |
| summarizer | bifrost-litellm/MiniMax-M2.7 |
| devops-agent | bifrost-litellm/MiniMax-M3 |
| devops-reviewer | bifrost-litellm/qwen3.8-max |
| orchestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plankestrator-identity-probe | bifrost-litellm/QWEN3.7-plus |
| plan-writer-simple | bifrost-litellm/QWEN3.7-plus |
| plan-writer-complex | bifrost-litellm/qwen3.8-max |
| plan-reviewer-simple | bifrost-litellm/GLM-5.3 (res) |
| plan-reviewer-complex | bifrost-litellm/Kimi K3 |
| research-writer-simple | bifrost-litellm/mimo-v2.5-pro |
| research-writer-complex | bifrost-litellm/Kimi K3 |
| research-reviewer | bifrost-litellm/GLM-5.3 (res) |
| devops-readonly | bifrost-litellm/MiniMax-M3 |
| git-commit | bifrost-litellm/MiniMax-M3 |
| generate-image | bifrost-litellm/MiniMax-M3 |
| generate-image-gpt | bifrost-litellm/MiniMax-M3 |
| view-image | bifrost-litellm/Kimi K2.6 |

Note: primary agents (orchestrator, plankestrator) run on `bifrost-litellm/QWEN3.7-plus` and are documented in §Identity Lock Mechanism (v3), item 5 — not duplicated in the Subagent Models table.

### Permission Authority
agents/*.md is the authoritative source for agent definitions. Markdown frontmatter is merged AFTER opencode.json and wins on shared keys (model, prompt, shared permission keys). Never define `model` or `prompt` for an agent in opencode.json if that agent has a .md file.

## 2. Pipelines

| Pipeline | Flow |
|----------|------|
| BUGFIX SIMPLE | bugfix-triage → worker → utility |
| BUGFIX DEEP | bugfix-triage → plan-bug (→ bug_plan.md) → execute-bug (← bug_plan.md) → dev-reviewer → rework → consistency-checker → [max 3] → utility |
| DEV SIMPLE (no plan) | worker → utility |
| DEV SIMPLE (with plan) | worker → consistency-checker → [max 3] → utility |
| DEV COMPLEX | dev-planner (→ dev_plan.md) → dev-professor (← dev_plan.md) → dev-reviewer → rework → consistency-checker → [max 3] → utility |
| DEV SUPERCOMPLEX | PER STEP: dev-planner → dev-professor → dev-reviewer → consistency-checker → [max 3] → utility |
| DEVOPS | devops-agent → devops-reviewer |
| DOCS SIMPLE | docs-writer → utility |
| DOCS DEEP | docs-planner (→ docs_plan.md) → docs-writer (← docs_plan.md) → dev-reviewer → rework → consistency-checker → [max 3] → utility |
| PLAN | plan-writer-* → plan-reviewer-* |
| RESEARCH | research-writer-* → research-reviewer |

### Auto-DOCS Hook
After final `utility` of BUGFIX/DEV: if `requires_docs_update: true` → `docs-writer → utility`.

## 3. JSON Validation Fields

### orchestrator: agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline
### plankestrator: agent, state, type, complexity, goal, next_agent, pipeline

## 4. MCP Servers

| Server | Type | Purpose |
|--------|------|---------|
| zai_zread | Remote (Bifrost) | GitHub operations |
| zai_web_search | Remote (Bifrost) | Web search |
| zai_web_reader | Remote (Bifrost) | URL reading |
| serena | Local | Code symbol operations |
| unity-mcp | Remote (localhost:8080) | Unity Editor |

## 5. Identity Probe Whitelists

| Primary Agent | Allowed Probe | Denied Probe |
|---------------|---------------|--------------|
| orchestrator | orchestrator-identity-probe | plankestrator-identity-probe |
| plankestrator | plankestrator-identity-probe | orchestrator-identity-probe |

## 6. Outdated Terms
- `ensemble` → use `pipeline` or `workflow`
- `team_*` → REMOVE
- `4747` → REMOVE

## 7. Primary Agent Roles

| Agent | Handles |
|-------|---------|
| orchestrator | BUGFIX, DEVOPS, DEV, DOCS |
| plankestrator | PLAN, RESEARCH, RESEARCH+PLAN |

## 8. File Locations

| Item | Path |
|------|------|
| Main Config | `~/.config/opencode/opencode.json` |
| Plugin | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| Agents | `~/.config/opencode/agents/*.md` |
