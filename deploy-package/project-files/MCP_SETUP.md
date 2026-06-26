# MCP Setup Guide — OpenCode Agent Orchestration System

## 1. Overview

OpenCode uses two primary agents:
- **orchestrator** — BUGFIX, DEVOPS, DEV, DOCS
- **plankestrator** — PLAN, RESEARCH, RESEARCH+PLAN

32 total agents (2 primary + 30 subagents).

## 2. Prerequisites

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18+ | Plugin runtime |
| OpenCode CLI | Latest | Agent orchestration |
| Git | 2.x | Repository operations |
| Python | 3.10+ | Serena MCP |
| uv | Latest | Python packages |

### Optional (Unity)
| Unity Editor | 2021.3 LTS+ | Unity MCP host |
| unity-mcp | Latest | Unity MCP integration |

### API Keys
| Provider | Key | Purpose |
|----------|-----|---------|
| Bifrost LiteLLM | `LITELLM_API_KEY` (env) | All LLM + Z.AI MCP servers |

## 3. Installation

```powershell
# Create directories
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\plugins"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\agents"

# Copy files
Copy-Item "opencode.json" "$env:USERPROFILE\.config\opencode\opencode.json" -Force
Copy-Item "agents\*.md" "$env:USERPROFILE\.config\opencode\agents\" -Force
Copy-Item "plugins\*" "$env:USERPROFILE\.config\opencode\plugins\" -Force

# Set API key
[Environment]::SetEnvironmentVariable("LITELLM_API_KEY", "your-key", "User")
```

## 4. MCP Servers

| Server | Type | URL |
|--------|------|-----|
| zai_web_reader | Remote | `https://hcbifrost.herocraft.com/litellm/zai_web_reader/mcp` |
| zai_web_search | Remote | `https://hcbifrost.herocraft.com/litellm/zai_web_search/mcp` |
| zai_zread | Remote | `https://hcbifrost.herocraft.com/litellm/zai_zread/mcp` |
| serena | Local | `serena.exe start-mcp-server --transport stdio` |
| unity-mcp | Remote | `http://localhost:8080/mcp` |

## 5. Agent Definitions (32 agents)

### Primary: orchestrator, plankestrator
### Subagents: worker, bugfix, bugfix-triage, execute-bug, plan-bug, dev-planner, dev-professor, dev-reviewer, rework, consistency-checker, utility, docs-writer, docs-planner, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-reviewer, devops-readonly, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, view-image, orchestrator-identity-probe, plankestrator-identity-probe

## 6. Pipelines

| Pipeline | Flow |
|----------|------|
| BUGFIX SIMPLE | bugfix-triage → worker → utility |
| BUGFIX DEEP | bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → [max 3] → utility |
| DEV SIMPLE | worker → utility |
| DEV COMPLEX | dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → [max 3] → utility |
| DEVOPS | devops-agent → devops-reviewer |
| DOCS | docs-writer → utility |

## 7. Troubleshooting

| Problem | Solution |
|---------|----------|
| Plugin not loading | Check path in opencode.json |
| MCP not connecting | Check API keys and URLs |
| Identity drift | Check agent .md files match opencode.json |
| Routing violation | Check routing tables match |

## 8. Verification Checklist

- [ ] Node.js 18+ installed
- [ ] OpenCode CLI installed
- [ ] LITELLM_API_KEY set
- [ ] opencode.json copied
- [ ] 32 agent files copied
- [ ] Plugin copied
- [ ] serena.exe installed
- [ ] opencode starts without errors
