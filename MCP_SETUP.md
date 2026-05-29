# MCP Setup Guide — OpenCode Agent Orchestration System

Полное руководство по развертыванию системы оркестрации агентов OpenCode на машинах коллег.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Installation Steps](#3-installation-steps)
4. [Configuration](#4-configuration)
5. [Agent Reference](#5-agent-reference)
6. [MCP Servers](#6-mcp-servers)
7. [File Locations](#7-file-locations)
8. [Troubleshooting](#8-troubleshooting)
9. [Verification Checklist](#9-verification-checklist)

---

## 1. Overview

### System Architecture

OpenCode использует архитектуру с двумя primary-агентами:

| Primary Agent | Role | Workflows |
|---------------|------|-----------|
| **orchestrator** | Operational tasks | BUGFIX, DEVOPS, DEV, DOCS |
| **plankestrator** | Planning & research | PLAN, RESEARCH, RESEARCH+PLAN |

### Agent Count

| Category | Count |
|----------|-------|
| Primary agents | 2 |
| Subagents | 31 |
| **Total unique agents** | **33** |

### Models Used

| Model | Provider | Agents Using It |
|-------|----------|-----------------|
| `glm-5` | alibaba-coding-plan | orchestrator, plankestrator, identity-probes, docs-writer, research-writer-simple, plan-reviewer-simple |
| `qwen3.6-plus` | alibaba-coding-plan | worker, bugfix, bugfix-triage, plan-bug, dev-planner, devops-reviewer, plan-writer-simple, consistency-checker |
| `glm-5.1` | bailian-token-plan | dev-professor, plan-writer-complex, research-writer-complex, execute-bug, rework |
| `k2p6` | kimi-for-coding | dev-reviewer, plan-reviewer-complex, research-reviewer, view-image |
| `MiniMax-M2.7` | minimax-coding-plan | mcp-github, mcp-read, mcp-search, summarizer, devops, devops-agent, devops-readonly |

### MCP Servers

| Server | Type | Purpose |
|--------|------|---------|
| zread | Remote | GitHub repository operations (search docs, read files, get structure) |
| webSearchPrime | Remote | Web search |
| webReader | Remote | URL content reading |
| serena | Local | Code symbol operations (find, rename, replace, delete) |
| unity-mcp | Remote | Unity Editor operations |
| zai-mcp-server | Local | Image analysis (fallback for view-image) |

---

## 2. Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18+ | Plugin runtime, MCP servers |
| OpenCode CLI | Latest | Agent orchestration |
| Git | 2.x | Repository operations |
| Python | 3.10+ | Serena MCP server |
| uv | Latest | Python package manager (for Serena) |

### For Unity Projects (Optional)

| Software | Version | Purpose |
|----------|---------|---------|
| Unity Editor | 2021.3 LTS+ | Unity MCP server host |
| unity-mcp package | Latest | Unity MCP integration |

### Required API Keys

| Provider | Key Variable | Purpose |
|----------|-------------|---------|
| Alibaba (bailian-token-plan) | Embedded in config | Qwen, GLM models |
| Z.AI | Embedded in config | zread, webSearchPrime, webReader, zai-mcp-server |
| Kimi | Via zai-mcp-server | k2p6 model access |

---

## 3. Installation Steps

### Step 1: Install OpenCode CLI

```bash
npm install -g opencode
```

### Step 2: Install Serena

```bash
# Download and install Serena
# See: https://github.com/orbstack/serena (or project-specific instructions)
# Place serena.exe in a directory in your PATH, e.g.:
# %USERPROFILE%\.local\bin\serena.exe
```

Verify installation:
```bash
serena --version
```

### Step 3: Install zai-mcp-server

```bash
npx -y @z_ai/mcp-server
```

### Step 4: Configure Unity MCP (Optional — for Unity projects only)

1. Install Unity 2021.3 LTS or later
2. Install unity-mcp package via Unity Package Manager:
   - Open Package Manager
   - Add package from git URL: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
3. Start Unity Editor
4. Start MCP server: `Window > MCP for Unity > Start Server`
5. Server runs on `http://localhost:8080/mcp`

### Step 5: Create Directory Structure

```powershell
# Windows (PowerShell)
mkdir -p $HOME\.config\opencode\plugins
mkdir -p $HOME\.config\opencode\agents
```

### Step 6: Copy Configuration Files

```powershell
# Copy opencode.json
cp opencode-config/opencode.json $HOME\.config\opencode\opencode.json

# Copy plugin
cp plugins/workflow-enforcement.ts $HOME\.config\opencode\plugins\workflow-enforcement.ts

# Copy all agent files
cp agents/*.md $HOME\.config\opencode\agents\
```

### Step 7: Copy Project Files

Copy these files to your project root:
- `AGENTS.md` — Project rules and agent permissions
- `ARCHITECTURE.md` — Architecture requirements
- `PLUGIN.md` — Plugin documentation

---

## 4. Configuration

### opencode.json Structure

The main configuration file contains:

1. **Providers** — Model provider definitions with API keys and endpoints
2. **MCP Servers** — Server connections (remote and local)
3. **Agents** — All 33 agent definitions with models, permissions, and prompts
4. **Commands** — Custom command shortcuts
5. **Plugin** — Workflow enforcement plugin

### Key Configuration Sections

#### Providers

```json
"provider": {
  "bailian-token-plan": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Alibaba Token Plan",
    "options": {
      "baseURL": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
      "apiKey": "YOUR_API_KEY"
    },
    "models": {
      "qwen3.6-plus": { "name": "Qwen3.6 Plus", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "glm-5.1": { "name": "GLM-5.1", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "glm-5": { "name": "GLM-5", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } }
    }
  }
}
```

#### MCP Servers

```json
"mcp": {
  "zread": {
    "url": "https://api.z.ai/api/mcp/zread/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "webSearchPrime": {
    "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "webReader": {
    "url": "https://api.z.ai/api/mcp/web_reader/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "serena": {
    "type": "local",
    "command": ["serena", "start-mcp-server", "--transport", "stdio", "--context=ide", "--project-from-cwd"],
    "enabled": true
  },
  "unity-mcp": {
    "type": "remote",
    "url": "http://localhost:8080/mcp",
    "enabled": true
  },
  "zai-mcp-server": {
    "type": "local",
    "command": ["npx", "-y", "@z_ai/mcp-server"],
    "environment": {
      "Z_AI_API_KEY": "YOUR_Z_AI_KEY",
      "Z_AI_MODE": "ZAI"
    },
    "enabled": true
  }
}
```

---

## 5. Agent Reference

### Complete Agent List

| Agent | Mode | Model | Role |
|-------|------|-------|------|
| **orchestrator** | primary | alibaba-coding-plan/glm-5 | Task classifier and delegator (BUGFIX/DEVOPS/DEV/DOCS) |
| **plankestrator** | primary | alibaba-coding-plan/glm-5 | Planning and research state machine |
| **orchestrator-identity-probe** | subagent | alibaba-coding-plan/glm-5 | Identity verification for orchestrator |
| **plankestrator-identity-probe** | subagent | alibaba-coding-plan/glm-5 | Identity verification for plankestrator |
| **worker** | subagent | alibaba-coding-plan/qwen3.6-plus | Simple development implementation |
| **bugfix** | subagent | alibaba-coding-plan/qwen3.6-plus | Bug fixing |
| **bugfix-triage** | subagent | alibaba-coding-plan/qwen3.6-plus | Initial bug analysis |
| **plan-bug** | subagent | alibaba-coding-plan/qwen3.6-plus | Bug fix planning |
| **dev-planner** | subagent | alibaba-coding-plan/qwen3.6-plus | Development planning |
| **devops-reviewer** | subagent | alibaba-coding-plan/qwen3.6-plus | DevOps review |
| **plan-writer-simple** | subagent | alibaba-coding-plan/qwen3.6-plus | Simple planning |
| **consistency-checker** | subagent | alibaba-coding-plan/qwen3.6-plus | Architecture consistency validation |
| **dev-professor** | subagent | bailian-token-plan/glm-5.1 | Development guidance |
| **plan-writer-complex** | subagent | bailian-token-plan/glm-5.1 | Complex planning |
| **research-writer-complex** | subagent | bailian-token-plan/glm-5.1 | Complex research |
| **execute-bug** | subagent | bailian-token-plan/glm-5.1 | Bug fix implementation |
| **rework** | subagent | bailian-token-plan/glm-5.1 | Rework on feedback |
| **dev-reviewer** | subagent | kimi-for-coding/k2p6 | Code review |
| **plan-reviewer-complex** | subagent | kimi-for-coding/k2p6 | Complex plan review |
| **research-reviewer** | subagent | kimi-for-coding/k2p6 | Research review |
| **view-image** | subagent | kimi-for-coding/k2p6 | Image analysis |
| **research-writer-simple** | subagent | alibaba-coding-plan/glm-5 | Simple research |
| **plan-reviewer-simple** | subagent | alibaba-coding-plan/glm-5 | Simple plan review |
| **docs-writer** | subagent | alibaba-coding-plan/glm-5 | Documentation writing |
| **mcp-github** | subagent | minimax-coding-plan/MiniMax-M2.7 | GitHub operations |
| **mcp-read** | subagent | minimax-coding-plan/MiniMax-M2.7 | File reading |
| **mcp-search** | subagent | minimax-coding-plan/MiniMax-M2.7 | Web search |
| **summarizer** | subagent | minimax-coding-plan/MiniMax-M2.7 | Content summarization |
| **devops** | subagent | minimax-coding-plan/MiniMax-M2.7 | DevOps tasks |
| **devops-agent** | subagent | minimax-coding-plan/MiniMax-M2.7 | DevOps operations |
| **devops-readonly** | subagent | minimax-coding-plan/MiniMax-M2.7 | DevOps read-only |
| **utility** | subagent | alibaba-coding-plan/qwen3.6-plus | Syntax checking, formatting |

### Routing Tables

#### orchestrator Whitelist (21 agents)

| Agent | Role |
|-------|------|
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
| view-image | Image analysis |

#### plankestrator Whitelist (9 agents)

| Agent | Role |
|-------|------|
| plankestrator-identity-probe | Identity verification |
| plan-writer-simple | Simple planning |
| plan-writer-complex | Complex planning |
| plan-reviewer-simple | Simple plan review |
| plan-reviewer-complex | Complex plan review |
| research-writer-simple | Simple research |
| research-writer-complex | Complex research |
| research-reviewer | Research review |
| devops-readonly | DevOps read-only |

### Pipelines

| Pipeline | Flow |
|----------|------|
| BUGFIX SIMPLE | bugfix-triage → worker → utility |
| BUGFIX DEEP | bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility |
| DEV SIMPLE (без плана) | worker → utility |
| DEV SIMPLE (с планом) | worker → consistency-checker → utility |
| DEV COMPLEX | dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility |
| DEVOPS | devops-agent → devops-reviewer |
| DOCS | docs-writer → utility |
| PLAN | plan-writer-* → plan-reviewer-* |
| RESEARCH | research-writer-* → research-reviewer |

### Key Agent Permissions

#### Worker — bash: allow

Worker MUST have `bash: allow` to execute commands:
- npm operations (`npm install`, `npm run build`, `npm run test`)
- git operations (`git status`, `git add`, `git commit`, `git push`)
- file operations (`mkdir`, `touch`, `rm`, `cp`)
- linting tools (`eslint`, `prettier`, `tsc --noEmit`)
- test runners (`jest`, `vitest`, `pytest`, `cargo test`)

#### View-Image — Build Agents

All build agents have `task.view-image: allow`:

| Agent | Use Case |
|-------|----------|
| worker | Analyze UI screenshots, diagrams, error images |
| bugfix | Analyze error screenshots during bug triage |
| execute-bug | Visual verification of bug fixes |
| rework | Compare before/after UI changes |

#### view-image Agent Restrictions

view-image is restricted from using MCP servers — it analyzes images directly through the model:
- **Denied**: zread, webSearchPrime, webReader, serena, unity-mcp, zai-mcp-server
- **Allowed**: read, glob, grep (for file access)

---

## 6. MCP Servers

### zread

- **Type**: Remote
- **URL**: `https://api.z.ai/api/mcp/zread/mcp`
- **Tools**: `zread_search_doc`, `zread_read_file`, `zread_get_repo_structure`
- **Purpose**: Search documentation, issues, PRs, and code in GitHub repositories

### webSearchPrime

- **Type**: Remote
- **URL**: `https://api.z.ai/api/mcp/web_search_prime/mcp`
- **Tools**: `webSearchPrime_web_search_prime`
- **Purpose**: Web search with time and domain filters

### webReader

- **Type**: Remote
- **URL**: `https://api.z.ai/api/mcp/web_reader/mcp`
- **Tools**: `webReader_webReader`
- **Purpose**: Fetch and convert web pages to markdown

### serena

- **Type**: Local
- **Command**: `serena start-mcp-server --transport stdio --context=ide --project-from-cwd`
- **Tools**: `serena_find_symbol`, `serena_find_referencing_symbols`, `serena_get_symbols_overview`, `serena_rename_symbol`, `serena_safe_delete_symbol`, `serena_replace_symbol_body`, `serena_insert_after_symbol`
- **Purpose**: Code symbol operations (PRIMARY for all code operations)

### unity-mcp

- **Type**: Remote
- **URL**: `http://localhost:8080/mcp`
- **Tools**: 20+ Unity Editor tools
- **Purpose**: Unity Editor operations (PRIMARY for Unity projects)
- **Prerequisites**: Unity Editor running with MCP server started

### zai-mcp-server

- **Type**: Local
- **Command**: `npx -y @z_ai/mcp-server`
- **Purpose**: Image analysis (fallback when view-image unavailable)

---

## 7. File Locations

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| opencode.json | `~/.config/opencode/opencode.json` | Main configuration |
| workflow-enforcement.ts | `~/.config/opencode/plugins/workflow-enforcement.ts` | Workflow plugin |
| [agent].md | `~/.config/opencode/agents/[name].md` | Agent definitions |

### Data Storage

| Directory | Location | Purpose |
|-----------|----------|---------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite database |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | Session state |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | Task tracking |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Tool results |
| Logs | `~/.local/share/opencode/log/` | Execution logs |

### Project Files

| File | Location | Purpose |
|------|----------|---------|
| AGENTS.md | Project root | Project rules and agent permissions |
| ARCHITECTURE.md | Project root | Architecture requirements |
| PLUGIN.md | Project root | Plugin documentation |
| MCP_SETUP.md | Project root | This setup guide |

---

## 8. Troubleshooting

### Common Issues

#### Plugin Not Loading

**Symptoms:**
- No "Workflow enforcement plugin initialized" log
- Routing violations not blocked

**Solution:**
```powershell
# Check plugin path in opencode.json
cat $HOME\.config\opencode\opencode.json | Select-String "plugin"

# Verify plugin file exists
Test-Path $HOME\.config\opencode\plugins\workflow-enforcement.ts
```

#### MCP Server Not Connecting

**Symptoms:**
- MCP tools not available
- "MCP server not found" errors

**Solution:**
- Check MCP configuration in opencode.json
- Verify API keys are correct
- For serena: ensure `serena.exe` is in PATH
- For unity-mcp: ensure Unity Editor is running with MCP server started

#### Agent Identity Drift

**Symptoms:**
- "IDENTITY DRIFT DETECTED" warnings
- Agent calling wrong subagents

**Solution:**
- Check agent file frontmatter matches opencode.json
- Verify agent description contains correct name
- Ensure identity verification output is correct format

#### Routing Violation

**Symptoms:**
- "WORKFLOW VIOLATION" errors
- Task tool calls blocked

**Solution:**
- Check routing table in plugin matches opencode.json whitelist
- Verify agent is calling correct subagent for its type
- Ensure JSON output includes correct `"agent"` field

#### view-image Cannot Read Files

**Symptoms:**
- view-image reports it cannot access files

**Solution:**
- Ensure view-image has `read: allow`, `glob: allow`, `grep: allow` permissions
- view-image should analyze images directly through the model, not use MCP servers

### Debug Commands

```powershell
# View recent logs
Get-Content $HOME\.local\share\opencode\log\*.log -Tail 100

# Search for violations
Select-String "WORKFLOW VIOLATION" $HOME\.local\share\opencode\log\*.log

# Search for drift
Select-String "IDENTITY DRIFT" $HOME\.local\share\opencode\log\*.log

# Search for JSON errors
Select-String "INVALID JSON" $HOME\.local\share\opencode\log\*.log

# View all plugin activity
Select-String "workflow-enforcement" $HOME\.local\share\opencode\log\*.log
```

---

## 9. Verification Checklist

### Pre-Deployment

- [ ] Node.js 18+ installed
- [ ] OpenCode CLI installed
- [ ] Serena installed and in PATH
- [ ] zai-mcp-server available via npx
- [ ] Directory structure created

### Configuration

- [ ] opencode.json copied to `~/.config/opencode/`
- [ ] Plugin copied to `~/.config/opencode/plugins/`
- [ ] All agent files copied to `~/.config/opencode/agents/`
- [ ] API keys configured correctly
- [ ] MCP server URLs correct

### Post-Deployment

- [ ] OpenCode starts without errors
- [ ] Plugin initialization log appears
- [ ] MCP tools available (zread_*, webSearchPrime_*, webReader_*, serena_*, unity-mcp_*)
- [ ] orchestrator session works
- [ ] plankestrator session works
- [ ] Routing violations blocked correctly
- [ ] JSON validation works
- [ ] Identity drift detection works

### Test Commands

```bash
# Test orchestrator
opencode --agent orchestrator
# Should see: "Workflow enforcement plugin initialized"
# Should see: "Session created — agent detected: orchestrator"

# Test plankestrator
opencode --agent plankestrator
# Should see: "Session created — agent detected: plankestrator"

# Test routing violation (should be blocked)
# In orchestrator session, try calling plan-writer-simple
# Should see: "WORKFLOW VIOLATION" error

# Test MCP tools
# In any session, use zread_search_doc
# Should return GitHub search results
```

---

## Summary

| Component | Count | Location |
|-----------|-------|----------|
| Primary agents | 2 | `~/.config/opencode/agents/` |
| Subagents | 31 | `~/.config/opencode/agents/` |
| MCP servers | 6 | Configured in opencode.json |
| Plugin hooks | 3 | workflow-enforcement.ts |
| Routing tables | 2 | orchestrator (21), plankestrator (9) |
| Pipelines | 9 | BUGFIX, DEV, DEVOPS, DOCS, PLAN, RESEARCH |

### Quick Reference

| Task | Command |
|------|---------|
| Start orchestrator | `opencode --agent orchestrator` |
| Start plankestrator | `opencode --agent plankestrator` |
| View logs | `Get-Content ~/.local/share/opencode/log/*.log -Tail 100` |
| Check config | `cat ~/.config/opencode/opencode.json` |
| List agents | `ls ~/.config/opencode/agents/` |

---

**Document Version:** 2.0
**Last Updated:** 2026-05-29
**Author:** OpenCode Documentation Team
